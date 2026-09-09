import AppKit
import SwiftUI
import Carbon
import Combine
import RullerCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: RullerModel!
    private var palette: NSPanel!
    private var hosting: NSHostingView<PaletteView>!
    private var overlays: [(OverlayPanel, OverlayView)] = []
    private var statusItem: NSStatusItem!
    private var subscription: AnyCancellable?
    private var localMonitor: Any?
    private var hotKeys: [EventHotKeyRef] = []
    private var hotKeyHandler: EventHandlerRef?
    private var previouslyEditing = false
    private var previousApp: NSRunningApplication?
    private let smokeTest = CommandLine.arguments.contains("--smoke-test")
    private let renderPreview = CommandLine.arguments.contains("--render-preview")
    private let renderDistances = CommandLine.arguments.contains("--render-distances")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        model = RullerModel(storageURL: (smokeTest || renderPreview || renderDistances) ? nil : support.appendingPathComponent("Ruller/guides.json"))
        let menu = makeMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "ruler", accessibilityDescription: "Ruller")
        statusItem.button?.toolTip = "Ruller — screen alignment guides"
        statusItem.menu = menu
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem(); applicationItem.submenu = makeMenu(); mainMenu.addItem(applicationItem)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", #selector(undo), "z"), ("Redo", #selector(redo), "Z"),
                                     ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
                                     ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            if title == "Undo" || title == "Redo" { item.target = self }
            editMenu.addItem(item)
        }
        edit.submenu = editMenu; mainMenu.addItem(edit); NSApp.mainMenu = mainMenu

        hosting = NSHostingView(rootView: PaletteView(model: model))
        palette = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 650),
                          styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
        palette.title = "Ruller"
        palette.titleVisibility = .hidden
        palette.titlebarAppearsTransparent = true
        palette.isReleasedWhenClosed = false
        palette.isFloatingPanel = true
        palette.hidesOnDeactivate = false
        palette.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        palette.collectionBehavior = overlayBehavior()
        palette.contentView = hosting
        palette.isMovableByWindowBackground = true
        palette.setFrameAutosaveName("RullerControls")
        palette.delegate = self
        palette.standardWindowButton(.zoomButton)?.isHidden = true
        palette.standardWindowButton(.miniaturizeButton)?.isHidden = true
        if let screen = NSScreen.main, !UserDefaults.standard.bool(forKey: "RullerHasOpened") {
            palette.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.maxX - 374, y: screen.visibleFrame.maxY - 36))
        }
        if !smokeTest && !renderPreview && !renderDistances { UserDefaults.standard.set(true, forKey: "RullerHasOpened") }
        model.revealPanel = { [weak self] in self?.showControls() }
        model.onInteractionChange = { [weak self] in self?.updateWindows() }
        rebuildOverlays()
        subscription = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateWindows() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.palette else { return event }
            if event.keyCode == 53 { self.palette.makeFirstResponder(nil); self.model.setEditing(false); return nil }
            if self.palette.firstResponder is NSTextView { return event }
            return handleKey(event, model: self.model) ? nil : event
        }
        registerShortcuts()
        updateWindows()
        if smokeTest { runSmokeTest() }
        else if renderDistances { renderDistancePreview() }
        else if renderPreview { renderControls() }
        else { showControls() }
    }

    private func overlayBehavior() -> NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        if #available(macOS 14.0, *) { behavior.insert(.canJoinAllApplications) }
        return behavior
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ selector: Selector, key: String = "") {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key); item.target = self; menu.addItem(item)
        }
        add("Show / Hide Controls    ⌃⌥P", #selector(toggleControls))
        add("Edit / Click Through    ⌃⌥R", #selector(toggleEditing))
        add("Show / Hide Lines    ⌃⌥H", #selector(toggleVisibility))
        menu.addItem(.separator())
        add("Add Vertical Guide", #selector(addVertical))
        add("Add Horizontal Guide", #selector(addHorizontal))
        add("Draw a Line", #selector(addSegment))
        menu.addItem(.separator())
        add("Quit Ruller", #selector(quit), key: "q")
        return menu
    }

    private func rebuildOverlays() {
        for (panel, _) in overlays { panel.close() }
        overlays.removeAll()
        for display in model.displays {
            let panel = OverlayPanel(contentRect: display.screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
            panel.level = .statusBar
            panel.collectionBehavior = overlayBehavior()
            panel.ignoresMouseEvents = true
            panel.acceptsMouseMovedEvents = true
            panel.isMovable = false; panel.isMovableByWindowBackground = false
            panel.isExcludedFromWindowsMenu = true
            panel.animationBehavior = .none
            let view = OverlayView(model: model, display: display)
            panel.contentView = view
            // Borderless windows need the complete display frame, including the menu-bar region.
            panel.setFrame(display.screen.frame, display: true)
            overlays.append((panel, view))
        }
    }

    private func updateWindows() {
        let enteringEdit = model.isEditing && !previouslyEditing
        let leavingEdit = !model.isEditing && previouslyEditing
        if enteringEdit {
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = frontmost }
        }
        previouslyEditing = model.isEditing
        for (panel, view) in overlays {
            panel.ignoresMouseEvents = !model.isEditing
            if model.isVisible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
            if leavingEdit { view.resetGesture(); if panel.isKeyWindow { panel.resignKey() } }
            view.needsDisplay = true
        }
        if enteringEdit {
            let mouse = NSEvent.mouseLocation
            let target = overlays.first { $0.0.frame.contains(mouse) } ?? overlays.first
            target?.0.makeKey(); target?.0.makeFirstResponder(target?.1)
        }
        if leavingEdit { NSCursor.arrow.set(); previousApp?.activate(options: []); previousApp = nil }
        resizePalette()
        if palette.isVisible { palette.orderFrontRegardless() }
        statusItem.button?.appearsDisabled = !model.isVisible
    }

    private func resizePalette() {
        let fitting = hosting.fittingSize
        guard fitting.height.isFinite, fitting.height > 50 else { return }
        let height = fitting.height
        let contentHeight = palette.contentRect(forFrameRect: palette.frame).height
        if abs(contentHeight - height) > 1 { palette.setContentSize(NSSize(width: 350, height: height)) }
        if let screen = palette.screen ?? NSScreen.main {
            var frame = palette.frame
            frame.origin.x = min(max(frame.minX, screen.visibleFrame.minX), screen.visibleFrame.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, screen.visibleFrame.minY), screen.visibleFrame.maxY - frame.height)
            if frame != palette.frame { palette.setFrame(frame, display: true) }
        }
    }

    @objc private func screensChanged() {
        model.setEditing(false); model.refreshDisplays(); rebuildOverlays(); updateWindows()
    }
    @objc func showControls() { resizePalette(); palette.makeKeyAndOrderFront(nil) }
    @objc private func toggleControls() {
        if palette.isVisible { hideControls() } else { showControls() }
    }
    private func hideControls() {
        palette.makeFirstResponder(nil)
        model.setEditing(false)
        palette.orderOut(nil)
    }
    @objc private func toggleEditing() { model.setEditing(!model.isEditing) }
    @objc private func toggleVisibility() { model.toggleVisibility() }
    @objc private func addVertical() { model.arm(.vertical) }
    @objc private func addHorizontal() { model.arm(.horizontal) }
    @objc private func addSegment() { model.arm(.segment) }
    @objc private func undo() { model.undo() }
    @objc private func redo() { model.redo() }
    @objc private func quit() { NSApp.terminate(nil) }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideControls()
        return false
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showControls(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        model.commitTransaction(); model.save()
        hotKeys.forEach { UnregisterEventHotKey($0) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    private func registerShortcuts() {
        guard !smokeTest && !renderPreview && !renderDistances else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let error = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard error == noErr else { return error }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                switch id.id {
                case 1: delegate.toggleEditing()
                case 2: delegate.toggleVisibility()
                case 3: delegate.toggleControls()
                default: break
                }
            }
            return noErr
        }, 1, &eventType, pointer, &hotKeyHandler)
        guard result == noErr else { model.shortcutWarning = "Global shortcuts unavailable. Use the ruler in the menu bar."; return }
        for (key, id) in [(UInt32(kVK_ANSI_R), UInt32(1)), (UInt32(kVK_ANSI_H), UInt32(2)), (UInt32(kVK_ANSI_P), UInt32(3))] {
            var reference: EventHotKeyRef?
            let error = RegisterEventHotKey(key, UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x52554C52, id: id),
                                            GetApplicationEventTarget(), 0, &reference)
            if error == noErr, let reference { hotKeys.append(reference) }
            else { model.shortcutWarning = "A global shortcut is in use. All controls remain available in the menu bar." }
        }
    }

    private func runSmokeTest() {
        guard let display = model.displays.first else { fatalError("No screen available") }
        model.beginTransaction(); model.add(kind: .vertical, at: Position(120, 100), displayID: display.id); model.commitTransaction()
        model.setEditing(true)
        precondition(overlays.allSatisfy { !$0.0.ignoresMouseEvents })
        model.nudge(dx: 1, dy: 0, fine: true)
        precondition(model.selected?.start.x == 120 + 1 / display.geometry.scale)
        model.setEditing(false)
        precondition(overlays.allSatisfy { $0.0.ignoresMouseEvents && $0.0.isVisible })
        model.toggleVisibility()
        precondition(overlays.allSatisfy { !$0.0.isVisible && $0.0.ignoresMouseEvents })
        model.toggleVisibility()
        model.undo(); precondition(model.selected?.start.x == 120)
        model.redo(); precondition(model.selected?.start.x == 120 + 1 / display.geometry.scale)
        showControls()
        model.setEditing(true)
        let beforeHiding = model.guides
        toggleControls()
        precondition(!palette.isVisible && !model.isEditing)
        precondition(model.guides == beforeHiding && overlays.allSatisfy { $0.0.isVisible && $0.0.ignoresMouseEvents })
        toggleControls()
        precondition(palette.isVisible && model.guides == beforeHiding)
        hideControls()
        model.clear(); precondition(model.guides.isEmpty)
        // Exercise the app's own event handlers without posting events to the desktop.
        let (panel, view) = overlays[0]
        func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double, flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: panel.frame.height - y), modifierFlags: flags,
                               timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        model.arm(.vertical)
        view.mouseDown(with: mouse(.leftMouseDown, 200, 200))
        view.mouseDragged(with: mouse(.leftMouseDragged, 203, 230))
        view.mouseUp(with: mouse(.leftMouseUp, 203, 230))
        precondition(model.selected?.start.x == 203 && model.tool == nil)
        model.arm(.segment)
        view.mouseDown(with: mouse(.leftMouseDown, 400, 300))
        view.mouseDragged(with: mouse(.leftMouseDragged, 500, 303, flags: .shift))
        view.mouseUp(with: mouse(.leftMouseUp, 500, 303))
        precondition(model.selected?.start.y == model.selected?.end.y)
        precondition((model.selected?.length ?? 0) >= 100)
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!
        view.keyDown(with: escape)
        precondition(!model.isEditing && panel.ignoresMouseEvents)
        model.beginTransaction()
        model.add(kind: .horizontal, at: Position(0, 300), displayID: display.id)
        model.add(kind: .horizontal, at: Position(0, 318.5), displayID: display.id)
        model.commitTransaction()
        model.unit = .pixels
        let gap = model.visibleGaps.first!
        precondition(gap.distance == 18.5)
        precondition(view.distanceAnnotations().first?.text == "↕ \(format(18.5 * display.geometry.scale)) px")
        model.nudge(dx: 0, dy: 1)
        precondition(model.visibleGaps.first!.value(unit: .pixels, scale: display.geometry.scale) == 18.5 * display.geometry.scale + 1)
        model.undo()
        model.setEditing(true)
        let annotation = view.distanceAnnotations().first!
        let guidesBeforeMovingLabel = model.guides
        view.mouseDown(with: mouse(.leftMouseDown, annotation.badge.midX, annotation.badge.midY))
        view.mouseDragged(with: mouse(.leftMouseDragged, annotation.badge.midX + 64, annotation.badge.midY))
        view.mouseUp(with: mouse(.leftMouseUp, annotation.badge.midX + 64, annotation.badge.midY))
        precondition(model.guides == guidesBeforeMovingLabel)
        precondition(view.distanceAnnotations().first!.start.x == annotation.start.x + 64)
        model.setEditing(false)
        precondition(panel.ignoresMouseEvents && !view.distanceAnnotations().isEmpty)
        model.showDistances = false
        precondition(view.distanceAnnotations().isEmpty)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("ruller-test-\(UUID().uuidString)")
        do {
            let file = temporary.appendingPathComponent("guides.json")
            let saved = RullerModel(storageURL: file)
            saved.guides = model.guides; saved.unit = .pixels; saved.showLabels = false
            saved.showDistances = false; saved.distanceAnchors = model.distanceAnchors; saved.save()
            let restored = RullerModel(storageURL: file)
            precondition(restored.guides == model.guides && restored.unit == .pixels && !restored.showLabels)
            precondition(!restored.showDistances && restored.distanceAnchors == model.distanceAnchors)
            precondition(!restored.isEditing)
            try FileManager.default.removeItem(at: temporary)
        } catch { fatalError("Persistence smoke test failed: \(error)") }
        print("Ruller smoke test passed: \(overlays.count) display(s), overlay visibility, click-through, pixel nudge, undo/redo.")
        print("Input handlers passed: place/drag vertical, Shift-constrained segment, Escape restores click-through.")
        print("Persistence passed: guides, exact positions, units and labels survive save/reload; editing starts off.")
        print("Controls toggle passed: hides and shows the panel, keeps guides visible, and exits editing when hidden.")
        print("Distances passed: live pixel gap, nudge/undo, drag measurements without moving guides, click-through, hide, save/reload.")
        NSApp.terminate(nil)
    }

    private func renderControls() {
        guard let display = model.displays.first else { NSApp.terminate(nil); return }
        model.beginTransaction()
        model.add(kind: .horizontal, at: Position(0, 280), displayID: display.id)
        model.add(kind: .horizontal, at: Position(0, 298), displayID: display.id)
        model.add(kind: .vertical, at: Position(72, 0), displayID: display.id)
        model.commitTransaction()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.resizePalette()
            self.hosting.layoutSubtreeIfNeeded()
            guard let bitmap = self.hosting.bitmapImageRepForCachingDisplay(in: self.hosting.bounds) else { fatalError("Could not render controls") }
            self.hosting.cacheDisplay(in: self.hosting.bounds, to: bitmap)
            let output = CommandLine.arguments.last!
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
            print("Rendered controls: \(self.hosting.bounds.size) to \(output)")
            NSApp.terminate(nil)
        }
    }

    private func renderDistancePreview() {
        guard let display = model.displays.first else { NSApp.terminate(nil); return }
        model.unit = .pixels; model.showLabels = false
        model.distanceAnchors[display.id] = Position(365, 295)
        for y in [100.0, 100.5, 112.5, 168] { model.add(kind: .horizontal, at: Position(0, y), displayID: display.id) }
        for x in [64.0, 65, 160] { model.add(kind: .vertical, at: Position(x, 0), displayID: display.id) }
        let demo = OverlayView(model: model, display: display)
        demo.setFrameSize(NSSize(width: 720, height: 440))
        guard let bitmap = demo.bitmapImageRepForCachingDisplay(in: demo.bounds) else { fatalError("Could not render distances") }
        demo.cacheDisplay(in: demo.bounds, to: bitmap)
        // Render only our view into a standalone preview, without capturing the desktop.
        let output = CommandLine.arguments.last!
        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
        print("Rendered distance preview to \(output)")
        NSApp.terminate(nil)
    }
}

@main enum RullerApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
