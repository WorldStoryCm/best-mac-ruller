import AppKit
import RullerCore

struct TrackedWindow: Equatable {
    var id: CGWindowID
    var ownerPID: pid_t
    var title: String
    var frame: CGRect
    var isOnScreen: Bool
}

struct WindowAttachment: Equatable {
    var window: TrackedWindow
    var startOffset: Position
    var endOffset: Position
}

@MainActor final class WindowTracker {
    private unowned let model: RullerModel
    private let readWindows: () -> [TrackedWindow]
    private let windowAtPoint: (Position) -> TrackedWindow?
    private var timer: Timer?
    var didAttach: ((TrackedWindow) -> Void)?

    init(model: RullerModel, readWindows: (() -> [TrackedWindow])? = nil,
         windowAtPoint: ((Position) -> TrackedWindow?)? = nil) {
        self.model = model
        self.readWindows = readWindows ?? { Self.systemWindows() }
        self.windowAtPoint = windowAtPoint ?? { Self.systemWindow(at: $0) }
    }

    static func systemWindows(excludingPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> [TrackedWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { trackedWindow($0, excludingPID: excludingPID) }
    }

    private static func trackedWindow(_ info: [String: Any], excludingPID: pid_t) -> TrackedWindow? {
        guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != excludingPID,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds), frame.width > 1, frame.height > 1 else { return nil }
        let owner = info[kCGWindowOwnerName as String] as? String ?? "Window"
        let name = info[kCGWindowName as String] as? String ?? ""
        return TrackedWindow(id: id, ownerPID: pid, title: name.isEmpty ? owner : "\(owner) — \(name)", frame: frame,
                             isOnScreen: (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false)
    }

    static func systemWindow(at point: Position) -> TrackedWindow? {
        // AppKit uses actual mouse hit-testing: z-order, transparent regions,
        // floating windows and click-through windows all behave like a real click.
        // Our model uses Quartz's top-left origin; AppKit uses the bottom-left.
        let screenPoint = NSPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
        let ownWindows = Set(NSApp.windows.map(\.windowNumber))
        var below = 0, visited = Set<Int>()
        while true {
            let number = NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: below)
            guard number > 0, number <= Int(UInt32.max), visited.insert(number).inserted else { return nil }
            if ownWindows.contains(number) { below = number; continue }
            let id = CGWindowID(number)
            guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
                  let info = list.first,
                  let window = trackedWindow(info, excludingPID: ProcessInfo.processInfo.processIdentifier),
                  window.id == id, window.isOnScreen else { return nil }
            return window
        }
    }

    func attach(at point: Position) {
        guard !model.selectedIDs.isEmpty else { return }
        guard let window = windowAtPoint(point) else {
            model.attachmentMessage = "No window here. Click inside an application window, or press Esc."
            return
        }
        model.beginTransaction()
        for guide in model.selectedGuides {
            guard let display = model.displays.first(where: { $0.id == guide.displayID }) else { continue }
            let start = display.global(guide.start), end = display.global(guide.end)
            model.attachments[guide.id] = WindowAttachment(window: window,
                startOffset: Position(start.x - window.frame.minX, start.y - window.frame.minY),
                endOffset: Position(end.x - window.frame.minX, end.y - window.frame.minY))
        }
        model.commitTransaction()
        model.isPickingWindow = false
        model.attachmentMessage = "Following \(window.title)"
        didAttach?(window)
        model.setEditing(false)
        synchronize()
    }

    func synchronize() {
        if model.attachments.isEmpty { stop(); return }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() { timer?.invalidate(); timer = nil }

    func poll() {
        guard !model.hasTransaction else { return }
        let windows = Dictionary(readWindows().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var guides = model.guides, attachments = model.attachments
        var hidden = Set<UUID>()
        for i in guides.indices {
            let id = guides[i].id
            guard var link = attachments[id] else { continue }
            guard let window = windows[link.window.id], window.ownerPID == link.window.ownerPID else {
                attachments.removeValue(forKey: id)
                model.attachmentMessage = "Window closed. Its guides now stay fixed on screen."
                continue
            }
            if !window.isOnScreen { hidden.insert(id); continue }
            let display = model.displays.max { a, b in
                func area(_ r: CGRect) -> Double { r.isNull ? 0 : r.width * r.height }
                return area(a.globalFrame.intersection(window.frame)) < area(b.globalFrame.intersection(window.frame))
            }
            guard let display else { continue }
            // Recompute from the window origin, not from accumulated deltas. Returning
            // from another display or an offscreen position cannot introduce drift.
            guides[i].displayID = display.id
            guides[i].start = display.local(Position(window.frame.minX + link.startOffset.x, window.frame.minY + link.startOffset.y))
            guides[i].end = display.local(Position(window.frame.minX + link.endOffset.x, window.frame.minY + link.endOffset.y))
            link.window = window; attachments[id] = link
        }
        if guides != model.guides { model.guides = guides }
        if attachments != model.attachments { model.attachments = attachments }
        if hidden != model.hiddenGuideIDs { model.hiddenGuideIDs = hidden }
        if let selected = model.selected,
           model.activeDisplayID != selected.displayID || model.selectedGuides.contains(where: { $0.displayID != selected.displayID }) {
            model.select(ids: model.selectedIDs, displayID: selected.displayID)
        }
        synchronize()
    }
}
