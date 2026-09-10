import AppKit
import RullerCore

@MainActor func runWindowAttachmentIntegrationTests(appModel: RullerModel? = nil, appOverlay: OverlayView? = nil) {
    let helper = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/window-fixture")
    guard FileManager.default.isExecutableFile(atPath: helper.path) else { fatalError("Build the window fixture with make test") }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ruller-attach-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let process = Process(); process.executableURL = helper; process.arguments = [folder.path]
    try! process.run()
    defer {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        try? FileManager.default.removeItem(at: folder)
    }
    func wait(_ condition: () -> Bool, message: () -> String = { "Window integration timed out" }) {
        let deadline = Date(timeIntervalSinceNow: 3)
        while !condition() && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03)) }
        precondition(condition(), message())
    }
    func command(_ text: String) -> [String: Any] {
        try! text.write(to: folder.appendingPathComponent("command"), atomically: true, encoding: .utf8)
        var state: [String: Any] = [:]
        wait {
            if let data = try? Data(contentsOf: folder.appendingPathComponent("state")),
               let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { state = value }
            return state["command"] as? String == text
        }
        return state
    }
    let frontFolder = folder.appendingPathComponent("front")
    try! FileManager.default.createDirectory(at: frontFolder, withIntermediateDirectories: true)
    let front = Process(); front.executableURL = helper; front.arguments = [frontFolder.path]
    defer { if front.isRunning { front.terminate(); front.waitUntilExit() } }
    func frontCommand(_ text: String) -> [String: Any] {
        try! text.write(to: frontFolder.appendingPathComponent("command"), atomically: true, encoding: .utf8)
        var state: [String: Any] = [:]
        wait {
            if let data = try? Data(contentsOf: frontFolder.appendingPathComponent("state")),
               let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { state = value }
            return state["command"] as? String == text
        }
        return state
    }
    let state = command("ready")
    let id = CGWindowID(state["id"] as! Int)
    var window: TrackedWindow?
    wait { window = WindowTracker.systemWindows().first { $0.id == id }; return window?.isOnScreen == true }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
    let initial = WindowTracker.systemWindows().first { $0.id == id }!.frame
    let model = appModel ?? RullerModel(storageURL: nil)
    model.clear()
    let display = model.displays.first!
    let tracker = WindowTracker(model: model)
    defer { tracker.stop() }
    let guide = model.add(kind: .vertical, at: display.local(Position(initial.minX + 20, initial.minY + 50)), displayID: display.id)
    model.add(kind: .horizontal, at: display.local(Position(initial.minX + 20, initial.minY + 50)), displayID: display.id)
    model.selectAll()
    model.armWindowPicker()
    if model.pickWindow == nil { model.pickWindow = { tracker.attach(at: $0) } }
    let fallback = OverlayView(model: model, display: display)
    let panel = OverlayPanel(contentRect: display.screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false; panel.contentView = fallback
    defer { panel.close() }
    let overlay = appOverlay ?? fallback
    let eventWindow = overlay.window!
    let point = display.local(Position(initial.midX, initial.midY))
    let event = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: point.x, y: eventWindow.frame.height - point.y), modifierFlags: [], timestamp: 0,
                                  windowNumber: eventWindow.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    overlay.mouseDown(with: event)
    precondition(model.attachments.count == 2 && model.attachments[guide]?.window.id == id, "Attach failed. Helper \(id) bounds \(initial), current \(String(describing: WindowTracker.systemWindows().first { $0.id == id })), selected \(String(describing: model.attachments[guide]?.window)), message \(String(describing: model.attachmentMessage))")
    precondition(!model.isEditing && !model.isPickingWindow)
    let before = model.guides
    _ = command("move")
    wait({ model.guides[0].start.x == before[0].start.x + 40 && model.guides[1].start.y == before[1].start.y - 30 }, message: {
        "Movement failed. Before \(before.map(\.start)), after \(model.guides.map(\.start)), transaction \(model.hasTransaction), attachments \(model.attachments), live \(String(describing: WindowTracker.systemWindows().first { $0.id == id }))"
    })
    _ = command("hide")
    wait { model.hiddenGuideIDs.count == 2 }
    _ = command("show")
    wait { model.hiddenGuideIDs.isEmpty }
    // A second application's overlapping window must win even above layer zero.
    try! front.run()
    let frontState = frontCommand("ready")
    let frontID = CGWindowID(frontState["id"] as! Int)
    let backFrame = WindowTracker.systemWindows().first { $0.id == id }!.frame
    _ = frontCommand("position \(backFrame.minX) \(backFrame.minY)")
    _ = frontCommand("float")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
    func clickOverlap() {
        model.armWindowPicker()
        let local = display.local(Position(backFrame.midX, backFrame.midY))
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: local.x, y: eventWindow.frame.height - local.y), modifierFlags: [], timestamp: 0,
                                     windowNumber: eventWindow.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
        overlay.mouseDown(with: click)
    }
    clickOverlap()
    precondition(model.attachments[guide]?.window.id == frontID,
                 "Attach selected the background app instead of the overlapping floating window")
    _ = frontCommand("normal")
    _ = frontCommand("pass-through")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    clickOverlap()
    precondition(model.attachments[guide]?.window.id == id,
                 "A click-through window must not steal Attach from the window underneath")
    _ = frontCommand("capture-mouse")
    _ = frontCommand("front")
    clickOverlap()
    precondition(model.attachments[guide]?.window.id == frontID, "Front normal window should receive Attach")
    _ = frontCommand("hide")
    clickOverlap()
    precondition(model.attachments[guide]?.window.id == id, "Hidden windows must not receive Attach")
    print("Overlap passed: separate apps, floating window, click-through window, normal front window, hidden window.")
    if let second = model.displays.dropFirst().first,
       let secondOverlay = NSApp.windows.compactMap({ $0.contentView as? OverlayView }).first(where: { $0.model === model && $0.display.id == second.id }),
       let secondWindow = secondOverlay.window {
        let target = second.global(Position(80, 120))
        _ = command("position \(target.x) \(target.y)")
        wait { model.guides.allSatisfy { $0.displayID == second.id } }
        let targetFrame = WindowTracker.systemWindows().first { $0.id == id }!.frame
        let local = second.local(Position(targetFrame.midX, targetFrame.midY))
        model.armWindowPicker()
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: local.x, y: secondWindow.frame.height - local.y), modifierFlags: [], timestamp: 0,
                                     windowNumber: secondWindow.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 1)!
        secondOverlay.mouseDown(with: click)
        precondition(model.attachments[guide]?.window.id == id, "Attach must use the clicked display's screen coordinates")
        print("Second display passed: attached window and picker coordinates move across screens.")
    }
    _ = command("close")
    wait { model.hiddenGuideIDs.count == 2 || model.attachments.isEmpty }
    try! "quit".write(to: folder.appendingPathComponent("command"), atomically: true, encoding: .utf8)
    wait { !process.isRunning }
    wait { model.attachments.isEmpty }
    print("Attach integration passed: choose a separate app's window, timer-driven movement, hide/show, exit.")
}
