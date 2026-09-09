import AppKit
import Carbon
import SwiftUI
import CoreVideo
import RullerCore

@MainActor func runFeatureSmokeTests() {
    let model = RullerModel(storageURL: nil)
    guard let display = model.displays.first else { fatalError("No display") }
    let panel = OverlayPanel(contentRect: display.screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    let view = OverlayView(model: model, display: display); panel.contentView = view
    defer { panel.close() }
    model.showDistances = false; model.showLabels = false
    let a = model.add(kind: .vertical, at: Position(100, 200), displayID: display.id)
    let b = model.add(kind: .vertical, at: Position(150, 200), displayID: display.id)
    model.add(kind: .horizontal, at: Position(0, 400), displayID: display.id)
    model.setEditing(true)
    func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: panel.frame.height - y), modifierFlags: flags,
                           timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }
    view.mouseDown(with: mouse(.leftMouseDown, 100, 300)); view.mouseUp(with: mouse(.leftMouseUp, 100, 300))
    view.mouseDown(with: mouse(.leftMouseDown, 150, 300, flags: .shift)); view.mouseUp(with: mouse(.leftMouseUp, 150, 300, flags: .shift))
    precondition(model.selectedIDs == [a, b])
    view.mouseDown(with: mouse(.leftMouseDown, 100, 300))
    view.mouseDragged(with: mouse(.leftMouseDragged, 110, 320)); view.mouseUp(with: mouse(.leftMouseUp, 110, 320))
    precondition(model.guides[0].start.x == 110 && model.guides[1].start.x == 160)
    model.undo(); precondition(model.guides[0].start.x == 100 && model.guides[1].start.x == 150)
    model.redo(); precondition(model.guides[0].start.x == 110 && model.guides[1].start.x == 160)
    model.setColor(.cyan); precondition(model.selectedGuides.allSatisfy { $0.color == .cyan })
    view.mouseDown(with: mouse(.leftMouseDown, 80, 200))
    view.mouseDragged(with: mouse(.leftMouseDragged, 180, 300)); view.mouseUp(with: mouse(.leftMouseUp, 180, 300))
    precondition(model.selectedIDs == [a, b])
    model.duplicate(); precondition(model.selectedIDs.count == 2 && model.guides.count == 5)
    model.deleteSelected(); precondition(model.guides.count == 3)
    model.undo(); precondition(model.guides.count == 5)
    model.undo(); precondition(model.guides.count == 3)
    model.selectAll(); precondition(model.selectedIDs.count == 3)
    model.select(a, extending: true); precondition(model.selectedIDs.count == 2 && !model.selectedIDs.contains(a))
    print("Selection passed: Shift-click, marquee, group drag, styles, duplicate/delete, undo/redo.")

    model.select(ids: [a, b], displayID: display.id)
    let initialFrame = CGRect(x: display.globalFrame.minX + 50, y: display.globalFrame.minY + 80, width: 400, height: 300)
    var windows = [TrackedWindow(id: 4_000_000, ownerPID: 9_999, title: "Test window", frame: initialFrame, isOnScreen: true)]
    let tracker = WindowTracker(model: model, readWindows: { windows })
    tracker.attach(at: Position(initialFrame.midX, initialFrame.midY))
    precondition(model.attachments.count == 2 && !model.isEditing)
    windows[0].frame.origin.x += 30; windows[0].frame.origin.y += 20; tracker.poll()
    precondition(model.guides[0].start.x == 140 && model.guides[1].start.x == 190)
    model.nudge(dx: 1, dy: 0, fine: true)
    let fine = 1 / display.geometry.scale
    windows[0].frame = initialFrame; tracker.poll()
    precondition(model.guides[0].start.x == 110 + fine && model.guides[1].start.x == 160 + fine)
    windows[0].isOnScreen = false; tracker.poll()
    precondition(model.hiddenGuideIDs == [a, b] && model.drawableGuides.count == 1)
    windows[0].isOnScreen = true; windows[0].frame.origin.x += 10_000; tracker.poll()
    windows[0].frame = initialFrame; tracker.poll()
    precondition(model.guides[0].start.x == 110 + fine && model.hiddenGuideIDs.isEmpty)
    windows = []; tracker.poll()
    precondition(model.attachments.isEmpty && model.hiddenGuideIDs.isEmpty)
    tracker.stop()

    // Verify the OS metadata boundary with a window created by this test.
    let fixture = NSWindow(contentRect: CGRect(x: display.screen.visibleFrame.minX + 80, y: display.screen.visibleFrame.minY + 80, width: 160, height: 100),
                           styleMask: [.titled], backing: .buffered, defer: false)
    fixture.isReleasedWhenClosed = false; fixture.title = "Ruller window test"; fixture.orderFront(nil)
    fixture.displayIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    let metadata = WindowTracker.systemWindows(excludingPID: -1).first { $0.id == CGWindowID(fixture.windowNumber) }
    precondition(metadata != nil, "Own window \(fixture.windowNumber) missing from CGWindowList; level \(fixture.level.rawValue)")
    precondition(metadata!.frame.minX == fixture.frame.minX)
    precondition(metadata!.frame.minY == (NSScreen.screens.first?.frame.maxY ?? 0) - fixture.frame.maxY)
    fixture.close()
    print("Window attachment passed: OS bounds, tracking, relative nudge, hide/restore, offscreen return, closing.")

    let manager = ShortcutManager(model: model, perform: { _ in })
    model.beginShortcutRecording?(.controls)
    model.finishShortcutRecording?(ShortcutAction.edit.defaultShortcut)
    precondition(model.recordingShortcut == .controls && model.shortcutError != nil)
    let candidate = KeyBinding(keyCode: 79, modifiers: 15, label: "F18")
    var occupied: EventHotKeyRef?
    let registered = RegisterEventHotKey(candidate.keyCode, candidate.carbonModifiers,
                                         EventHotKeyID(signature: 0x54455354, id: 99), GetApplicationEventTarget(), 0, &occupied)
    precondition(registered == noErr)
    model.finishShortcutRecording?(candidate)
    precondition(model.recordingShortcut == .controls && model.shortcuts[.controls] != candidate)
    if let occupied { UnregisterEventHotKey(occupied) }
    model.finishShortcutRecording?(candidate)
    precondition(model.recordingShortcut == nil && model.shortcuts[.controls] == candidate)
    model.beginShortcutRecording?(.edit); model.finishShortcutRecording?(nil)
    precondition(model.shortcuts[.edit] == ShortcutAction.edit.defaultShortcut)
    manager.stop()
    print("Shortcuts passed: duplicate and OS conflict rejection, successful replacement, cancel.")

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ruller-preferences-\(UUID().uuidString)")
    do {
        let url = folder.appendingPathComponent("guides.json")
        let saved = RullerModel(storageURL: url)
        saved.guides = model.guides; saved.highContrast = true; saved.loupeZoom = 16
        saved.shortcuts[.controls] = ShortcutAction.edit.defaultShortcut
        saved.shortcuts[.edit] = ShortcutAction.controls.defaultShortcut
        saved.save()
        let restored = RullerModel(storageURL: url)
        precondition(restored.highContrast && restored.loupeZoom == 16 && !restored.loupeEnabled)
        precondition(restored.shortcuts == saved.shortcuts && restored.guides == saved.guides)
        try FileManager.default.removeItem(at: folder)
    } catch { fatalError("New preferences failed: \(error)") }
    print("Preferences passed: contrast, zoom, swapped shortcuts; loupe starts off.")
    let loupe = makeLoupeFixture()
    let bitmap = renderView(loupe)
    let top = bitmap.colorAt(x: bitmap.pixelsWide * 80 / 208, y: bitmap.pixelsHigh * 50 / 244)!.usingColorSpace(.deviceRGB)!
    let bottom = bitmap.colorAt(x: bitmap.pixelsWide * 80 / 208, y: bitmap.pixelsHigh * 158 / 244)!.usingColorSpace(.deviceRGB)!
    precondition(top.redComponent > 0.8 && bottom.redComponent < 0.3, "Loupe image must keep screen top/bottom orientation")
    print("Loupe rendering passed: Retina crop, top/bottom orientation, nearest-pixel image and cursor highlight.")
    let contrastModel = RullerModel(storageURL: nil)
    contrastModel.showLabels = false; contrastModel.showDistances = false; contrastModel.defaultOpacity = 1
    contrastModel.add(kind: .vertical, at: Position(32, 0), displayID: display.id)
    contrastModel.add(kind: .vertical, at: Position(32 + 1 / display.geometry.scale, 0), displayID: display.id)
    contrastModel.setColor(.cyan)
    let contrastView = OverlayView(model: contrastModel, display: display)
    contrastView.setFrameSize(NSSize(width: 64, height: 64))
    let plain = renderView(contrastView)
    contrastModel.highContrast = true
    let outlined = renderView(contrastView)
    for guide in contrastModel.guides {
        let x = Int(guide.start.x * Double(plain.pixelsWide) / 64)
        let expected = plain.colorAt(x: x, y: 20)!.usingColorSpace(.deviceRGB)!
        let actual = outlined.colorAt(x: x, y: 20)!.usingColorSpace(.deviceRGB)!
        precondition(abs(expected.redComponent - actual.redComponent) < 0.02 && abs(expected.greenComponent - actual.greenComponent) < 0.02 && abs(expected.alphaComponent - actual.alphaComponent) < 0.02,
                     "Contrast outline must not cover neighboring colored guides")
    }
    print("Contrast passed: guides one backing pixel apart retain their exact colored pixels.")
}

// Render our own synthetic pixels, without reading or saving the desktop.
@MainActor private func makeLoupeFixture() -> LoupeView {
    var buffer: CVPixelBuffer?
    precondition(CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
    let pixels = buffer!
    CVPixelBufferLockBaseAddress(pixels, [])
    let bytes = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
    let row = CVPixelBufferGetBytesPerRow(pixels)
    for y in 0..<64 { for x in 0..<64 {
        let p = y * row + x * 4
        let color: (UInt8, UInt8, UInt8) = x == 32 ? (232, 70, 80) : y < 32 ? (246, 246, 246) : (26, 33, 48)
        bytes[p] = color.2; bytes[p + 1] = color.1; bytes[p + 2] = color.0; bytes[p + 3] = 255
    } }
    CVPixelBufferUnlockBaseAddress(pixels, [])
    let sample = LoupeSample(point: Position(16, 16), display: DisplayGeometry(width: 32, height: 32, scale: 2), radius: 24)
    let view = LoupeView(frame: CGRect(x: 0, y: 0, width: 208, height: 244))
    view.image = LoupeRenderer().crop(pixels, sample: sample)
    precondition(view.image?.width == 49 && view.image?.height == 49)
    view.cursorPixel = sample.cursorPixel; view.cellSize = 4
    view.caption = "X 32  Y 32 px"; view.zoomCaption = "8× · ⌃⌥M to hide"
    return view
}

@MainActor private func renderView(_ view: NSView) -> NSBitmapImageRep {
    view.layoutSubtreeIfNeeded()
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return bitmap
}

@MainActor func renderFeaturePreviews(model: RullerModel, beside url: URL) {
    let settings = NSHostingView(rootView: ShortcutSettingsView(model: model))
    settings.setFrameSize(settings.fittingSize)
    for (name, view) in [("shortcuts.png", settings as NSView), ("loupe.png", makeLoupeFixture() as NSView)] {
        let file = url.deletingLastPathComponent().appendingPathComponent(name)
        try! renderView(view).representation(using: .png, properties: [:])!.write(to: file)
        print("Rendered \(name)")
    }
}
