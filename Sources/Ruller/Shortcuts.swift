import AppKit
import Carbon
import SwiftUI
import RullerCore

extension KeyBinding {
    var carbonModifiers: UInt32 {
        (modifiers & 1 != 0 ? UInt32(controlKey) : 0) | (modifiers & 2 != 0 ? UInt32(optionKey) : 0) |
        (modifiers & 4 != 0 ? UInt32(cmdKey) : 0) | (modifiers & 8 != 0 ? UInt32(shiftKey) : 0)
    }

    init(event: NSEvent) {
        let flags = event.modifierFlags
        let modifiers: UInt32 = (flags.contains(.control) ? 1 : 0) | (flags.contains(.option) ? 2 : 0) |
            (flags.contains(.command) ? 4 : 0) | (flags.contains(.shift) ? 8 : 0)
        let special: [UInt16: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 76: "⌤", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers,
                  label: special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "")
    }
}

@MainActor final class ShortcutManager {
    private unowned let model: RullerModel
    private let perform: (ShortcutAction) -> Void
    private var references: [ShortcutAction: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?

    init(model: RullerModel, perform: @escaping (ShortcutAction) -> Void) {
        self.model = model; self.perform = perform
        model.beginShortcutRecording = { [weak self] action in self?.beginRecording(action) }
        model.finishShortcutRecording = { [weak self] shortcut in self?.finishRecording(shortcut) }
        model.resetShortcuts = { [weak self] in self?.restoreDefaults() }
    }

    func start() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr else { return result }
            let manager = Unmanaged<ShortcutManager>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                if manager.model.recordingShortcut == nil, let action = ShortcutAction.allCases.first(where: { $0.hotKeyID == id.id }) {
                    manager.perform(action)
                }
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { model.shortcutWarning = "Global shortcuts unavailable. Use the ruler menu."; return }
        registerAll()
    }

    private func releaseKeys() { references.values.forEach { UnregisterEventHotKey($0) }; references = [:] }
    func stop() { releaseKeys(); if let handler { RemoveEventHandler(handler) }; handler = nil }

    private func register(_ shortcut: KeyBinding, action: ShortcutAction) -> EventHotKeyRef? {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers,
                                        EventHotKeyID(signature: 0x52554C52, id: action.hotKeyID), GetApplicationEventTarget(), 0, &reference)
        return status == noErr ? reference : nil
    }

    private func registerAll() {
        releaseKeys()
        guard handler != nil else { return }
        var unavailable: [String] = []
        for action in ShortcutAction.allCases {
            guard let shortcut = model.shortcuts[action] else { continue }
            if let reference = register(shortcut, action: action) { references[action] = reference }
            else { unavailable.append(shortcut.display) }
        }
        model.shortcutWarning = unavailable.isEmpty ? nil : "Shortcut in use: \(unavailable.joined(separator: ", ")). Change it in Shortcuts."
    }

    private func beginRecording(_ action: ShortcutAction) {
        releaseKeys() // Previously assigned combinations must also reach the recorder.
        model.shortcutError = nil; model.recordingShortcut = action
    }

    func finishRecording(_ shortcut: KeyBinding?) {
        guard let action = model.recordingShortcut else { return }
        if let shortcut {
            guard shortcut.isValid else { model.shortcutError = "Include Control, Option, or Command with a key."; return }
            if let other = model.shortcuts.first(where: { $0.key != action && $0.value.hasSameKeys(as: shortcut) }) {
                model.shortcutError = "Already assigned to \(other.key.title.lowercased())."; return
            }
            guard let reference = register(shortcut, action: action) else {
                model.shortcutError = "That combination is in use by macOS or another app. Try another."; return
            }
            UnregisterEventHotKey(reference)
            model.shortcuts[action] = shortcut
        }
        model.recordingShortcut = nil; model.shortcutError = nil
        registerAll(); model.save()
    }

    private func restoreDefaults() {
        model.recordingShortcut = nil; model.shortcutError = nil
        model.shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
        registerAll(); model.save()
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var model: RullerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Keyboard shortcuts").font(.system(size: 20, weight: .semibold))
            Text("Click a shortcut, then press your combination.\nInclude Control, Option, or Command. Esc cancels.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(ShortcutAction.allCases) { action in
                HStack {
                    Text(action.title).font(.system(size: 12))
                    Spacer()
                    ShortcutRecorder(model: model, action: action).frame(width: 150, height: 28)
                }
            }
            if let error = model.shortcutError ?? model.shortcutWarning {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Restore defaults") { model.resetShortcuts?() }.disabled(model.recordingShortcut != nil)
                Spacer()
                if model.recordingShortcut != nil { Button("Cancel recording") { model.finishShortcutRecording?(nil) } }
            }.controlSize(.small)
        }.padding(24).frame(width: 430).background(.regularMaterial)
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var model: RullerModel
    let action: ShortcutAction
    func makeNSView(context: Context) -> ShortcutRecordButton {
        let button = ShortcutRecordButton()
        button.bezelStyle = .rounded
        button.model = model; button.shortcutAction = action
        button.target = button; button.action = #selector(ShortcutRecordButton.begin)
        return button
    }
    func updateNSView(_ button: ShortcutRecordButton, context: Context) {
        button.title = model.recordingShortcut == action ? "Press shortcut…" : model.shortcutLabel(action)
        button.setAccessibilityLabel("\(action.title): \(button.title)")
    }
}

private final class ShortcutRecordButton: NSButton {
    weak var model: RullerModel?
    var shortcutAction = ShortcutAction.controls
    override var acceptsFirstResponder: Bool { true }
    @objc func begin() { model?.beginShortcutRecording?(shortcutAction); window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        guard model?.recordingShortcut == shortcutAction else { super.keyDown(with: event); return }
        model?.finishShortcutRecording?(event.keyCode == 53 ? nil : KeyBinding(event: event))
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if model?.recordingShortcut == shortcutAction { keyDown(with: event); return true }
        return super.performKeyEquivalent(with: event)
    }
}
