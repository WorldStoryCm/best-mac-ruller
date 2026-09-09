import AppKit
import Combine
import RullerCore

struct DisplayInfo: Identifiable {
    let id: String
    let name: String
    let screen: NSScreen
    var geometry: DisplayGeometry {
        DisplayGeometry(width: screen.frame.width, height: screen.frame.height, scale: screen.backingScaleFactor)
    }
    var globalFrame: CGRect {
        CGRect(x: screen.frame.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - screen.frame.maxY,
               width: screen.frame.width, height: screen.frame.height)
    }
    func global(_ point: Position) -> Position { Position(globalFrame.minX + point.x, globalFrame.minY + point.y) }
    func local(_ point: Position) -> Position { Position(point.x - globalFrame.minX, point.y - globalFrame.minY) }
}

private struct GuideSnapshot: Equatable {
    var guides: [Guide]
    var attachments: [UUID: WindowAttachment]
}

@MainActor final class RullerModel: ObservableObject {
    @Published var guides: [Guide] = []
    @Published var selectedID: UUID? {
        didSet {
            if let selectedID, !selectedIDs.contains(selectedID) { selectedIDs = [selectedID] }
            else if selectedID == nil { selectedIDs = [] }
        }
    }
    @Published private(set) var selectedIDs: Set<UUID> = []
    @Published var isEditing = false
    @Published var isVisible = true
    @Published var tool: GuideKind?
    @Published var showLabels = true
    @Published var showDistances = true
    @Published var distanceAnchors: [String: Position] = [:]
    @Published var unit: MeasurementUnit = .points
    @Published var defaultColor: GuideColor = .coral
    @Published var defaultOpacity = 0.85
    @Published var defaultWidth = 1
    @Published var displays: [DisplayInfo] = []
    @Published var activeDisplayID = ""
    @Published var persistenceError: String?
    @Published var shortcutWarning: String?
    @Published var highContrast = false
    @Published var loupeEnabled = false
    @Published var loupeZoom = 8
    @Published var loupeError: String?
    @Published var shortcuts: [ShortcutAction: KeyBinding] = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
    @Published var recordingShortcut: ShortcutAction?
    @Published var shortcutError: String?
    @Published var attachments: [UUID: WindowAttachment] = [:]
    @Published var hiddenGuideIDs: Set<UUID> = []
    @Published var isPickingWindow = false
    @Published var attachmentMessage: String?
    var loupeFocus: (String, Position)?
    var showSettings: (() -> Void)?
    var beginShortcutRecording: ((ShortcutAction) -> Void)?
    var finishShortcutRecording: ((KeyBinding?) -> Void)?
    var resetShortcuts: (() -> Void)?
    var toggleLoupe: (() -> Void)?
    var pickWindow: ((Position) -> Void)?
    var revealPanel: (() -> Void)?
    var onInteractionChange: (() -> Void)?
    var undoHistory = UndoManager()
    private var transactionStart: GuideSnapshot?
    var hasTransaction: Bool { transactionStart != nil }
    private let storageURL: URL?
    private var saveTask: DispatchWorkItem?
    private var subscriptions = Set<AnyCancellable>()

    init(storageURL: URL?) {
        self.storageURL = storageURL
        undoHistory.groupsByEvent = false
        refreshDisplays()
        if let storageURL, FileManager.default.fileExists(atPath: storageURL.path) {
            do {
                let saved = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: storageURL))
                guard saved.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
                guides = saved.guides.filter { [$0.start.x, $0.start.y, $0.end.x, $0.end.y, $0.opacity].allSatisfy(\.isFinite) }.map {
                    var g = $0; g.opacity = min(max(g.opacity, 0.05), 1); g.widthPixels = min(max(g.widthPixels, 1), 8); return g
                }
                unit = saved.unit; showLabels = saved.showLabels; defaultColor = saved.defaultColor
                showDistances = saved.showDistances ?? true
                distanceAnchors = (saved.distanceAnchors ?? [:]).filter { $0.value.x.isFinite && $0.value.y.isFinite }
                highContrast = saved.highContrast ?? false
                let zoom = saved.loupeZoom ?? 8
                loupeZoom = [4, 8, 16].contains(zoom) ? zoom : 8
                // Ignore corrupt/duplicate bindings and keep the other shortcuts usable.
                for action in ShortcutAction.allCases {
                    if let binding = saved.shortcuts?[action.rawValue], binding.isValid {
                        shortcuts[action] = binding
                    }
                }
                if ShortcutAction.allCases.contains(where: { action in
                    shortcuts.contains { $0.key != action && $0.value.hasSameKeys(as: shortcuts[action]!) }
                }) { shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) }) }
                defaultOpacity = min(max(saved.defaultOpacity, 0.05), 1); defaultWidth = min(max(saved.defaultWidth, 1), 8)
                normalizeGuides()
            } catch { persistenceError = "Saved guides could not be read. A fresh set will be saved when you edit." }
        }
        selectedID = guides.first(where: { $0.displayID == activeDisplayID })?.id
        objectWillChange.sink { [weak self] _ in
            // Published values are delivered before mutation; save on the next turn.
            DispatchQueue.main.async { self?.scheduleSave() }
        }.store(in: &subscriptions)
    }

    var selected: Guide? { guides.first { $0.id == selectedID } }
    var selectedGuides: [Guide] { guides.filter { selectedIDs.contains($0.id) } }
    var drawableGuides: [Guide] { guides.filter { !hiddenGuideIDs.contains($0.id) } }
    var activeDisplay: DisplayInfo? { displays.first { $0.id == activeDisplayID } ?? displays.first }
    var selectedDisplay: DisplayInfo? { displays.first { $0.id == selected?.displayID } ?? activeDisplay }
    var factor: Double { unit.factor(scale: selectedDisplay?.geometry.scale ?? 1) }
    var visibleGuides: [Guide] { guides.filter { $0.displayID == activeDisplayID } }
    var visibleGaps: [GuideGap] { GuideGap.adjacent(in: drawableGuides, displayID: activeDisplayID) }
    var color: GuideColor { selected?.color ?? defaultColor }
    var opacity: Double { selected?.opacity ?? defaultOpacity }
    var width: Int { selected?.widthPixels ?? defaultWidth }

    func refreshDisplays() {
        displays = NSScreen.screens.map { screen in
            let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue()
            let id = uuid.map { CFUUIDCreateString(nil, $0) as String } ?? String(number)
            return DisplayInfo(id: id, name: screen.localizedName, screen: screen)
        }
        if !displays.contains(where: { $0.id == activeDisplayID }) { activeDisplayID = displays.first?.id ?? "" }
        normalizeGuides()
    }

    private func normalizeGuides() {
        for i in guides.indices {
            guard let display = displays.first(where: { $0.id == guides[i].displayID }) else { continue }
            guides[i].start = display.geometry.clamped(guides[i].start)
            guides[i].end = display.geometry.clamped(guides[i].end)
        }
    }

    func select(_ id: UUID?, extending: Bool = false, preserving: Bool = false) {
        guard let id, let guide = guides.first(where: { $0.id == id }) else { selectedIDs = []; selectedID = nil; return }
        var ids = selectedIDs
        if selected?.displayID != guide.displayID { ids = [] }
        if extending {
            if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        } else if !preserving || !ids.contains(id) { ids = [id] }
        select(ids: ids, displayID: guide.displayID)
        if ids.contains(id) { selectedID = id }
    }

    func select(ids: Set<UUID>, displayID: String) {
        activeDisplayID = displayID
        selectedIDs = ids.intersection(guides.filter { $0.displayID == displayID }.map(\.id))
        if selectedID == nil || !selectedIDs.contains(selectedID!) {
            selectedID = guides.first { selectedIDs.contains($0.id) }?.id
        }
    }

    func selectAll() { select(ids: Set(visibleGuides.filter { !hiddenGuideIDs.contains($0.id) }.map(\.id)), displayID: activeDisplayID) }

    func setEditing(_ editing: Bool) {
        commitTransaction()
        isEditing = editing; tool = nil
        isPickingWindow = false
        if !editing { loupeFocus = nil }
        if editing { isVisible = true }
        onInteractionChange?()
    }

    func arm(_ kind: GuideKind) {
        setEditing(true); tool = kind
        onInteractionChange?()
    }

    func toggleVisibility() {
        if isVisible { setEditing(false) }
        isVisible.toggle(); onInteractionChange?()
    }

    func beginTransaction() {
        if transactionStart == nil { transactionStart = GuideSnapshot(guides: guides, attachments: attachments) }
    }

    func commitTransaction() {
        guard let before = transactionStart else { return }
        transactionStart = nil
        refreshAttachmentOffsets()
        guard before != GuideSnapshot(guides: guides, attachments: attachments) else { return }
        registerUndo(before)
    }

    private func registerUndo(_ old: GuideSnapshot) {
        undoHistory.beginUndoGrouping()
        undoHistory.registerUndo(withTarget: self) { model in
            let current = GuideSnapshot(guides: model.guides, attachments: model.attachments)
            model.guides = old.guides; model.attachments = old.attachments
            model.hiddenGuideIDs.formIntersection(old.attachments.keys)
            model.registerUndo(current)
            model.select(ids: model.selectedIDs.intersection(old.guides.map(\.id)), displayID: model.activeDisplayID)
            if model.selectedID == nil { model.select(model.visibleGuides.last?.id) }
        }
        undoHistory.setActionName("Change Guides")
        undoHistory.endUndoGrouping()
    }

    func changeSelected(_ update: (inout Guide) -> Void) {
        guard let i = guides.firstIndex(where: { $0.id == selectedID }) else { return }
        let inTransaction = transactionStart != nil
        if !inTransaction { beginTransaction() }
        update(&guides[i])
        if !inTransaction { commitTransaction() }
    }

    @discardableResult func add(kind: GuideKind, at point: Position, displayID: String) -> UUID {
        let guide = Guide(displayID: displayID, kind: kind, start: point, color: defaultColor,
                          opacity: defaultOpacity, widthPixels: defaultWidth)
        guides.append(guide); select(guide.id)
        return guide.id
    }

    func nudge(dx: Double, dy: Double, fine: Bool = false, large: Bool = false) {
        guard let display = selectedDisplay else { return }
        let step = (fine ? 1 / display.geometry.scale : unit.step(scale: display.geometry.scale)) * (large ? 10 : 1)
        moveSelection(from: selectedGuides, dx: dx * step, dy: dy * step, display: display)
        if let selected {
            let mouse = NSEvent.mouseLocation
            let p = Position(mouse.x - display.screen.frame.minX, display.screen.frame.maxY - mouse.y)
            loupeFocus = (display.id, Position(selected.kind == .horizontal ? p.x : selected.start.x,
                                              selected.kind == .vertical ? p.y : selected.start.y))
        }
    }

    func moveSelection(from originals: [Guide], dx: Double, dy: Double, display: DisplayInfo) {
        let inTransaction = hasTransaction
        if !inTransaction { beginTransaction() }
        let moved = GuideSelection.translated(originals, dx: dx, dy: dy, in: display.geometry)
        for g in moved { if let i = guides.firstIndex(where: { $0.id == g.id }) { guides[i] = g } }
        if !inTransaction { commitTransaction() }
    }

    func setCoordinate(_ value: Double, axis: String) {
        guard value.isFinite, let display = selectedDisplay else { return }
        let raw = value / factor
        let position = (raw * display.geometry.scale).rounded() / display.geometry.scale
        if let selected, axis == "x" || axis == "y" {
            moveSelection(from: selectedGuides, dx: axis == "x" ? position - selected.start.x : 0,
                          dy: axis == "y" ? position - selected.start.y : 0, display: display)
            return
        }
        changeSelected { g in
            switch axis {
            case "x": g.translate(dx: position - g.start.x, dy: 0, in: display.geometry)
            case "y": g.translate(dx: 0, dy: position - g.start.y, in: display.geometry)
            case "x2": g.end = display.geometry.clamped(Position(position, g.end.y))
            case "y2": g.end = display.geometry.clamped(Position(g.end.x, position))
            default: break
            }
        }
    }

    private func styleSelection(_ update: (inout Guide) -> Void) {
        let inTransaction = hasTransaction
        if !inTransaction { beginTransaction() }
        for i in guides.indices where selectedIDs.contains(guides[i].id) { update(&guides[i]) }
        if !inTransaction { commitTransaction() }
    }
    func setColor(_ value: GuideColor) { defaultColor = value; styleSelection { $0.color = value } }
    func setOpacity(_ value: Double) { defaultOpacity = value; styleSelection { $0.opacity = value } }
    func setWidth(_ value: Int) { defaultWidth = value; styleSelection { $0.widthPixels = value } }
    func deleteSelected() {
        guard !selectedIDs.isEmpty else { return }
        beginTransaction()
        guides.removeAll { selectedIDs.contains($0.id) }
        attachments = attachments.filter { !selectedIDs.contains($0.key) }
        hiddenGuideIDs.subtract(selectedIDs)
        select(visibleGuides.last?.id); commitTransaction()
    }
    func clear() { beginTransaction(); guides.removeAll(); attachments.removeAll(); hiddenGuideIDs = []; select(nil); commitTransaction() }
    func duplicate() {
        guard !selectedGuides.isEmpty, let display = selectedDisplay else { return }
        beginTransaction()
        var copies = GuideSelection.translated(selectedGuides, dx: 20, dy: 20, in: display.geometry)
        for i in copies.indices {
            let oldID = copies[i].id; copies[i].id = UUID()
            if let attachment = attachments[oldID] { attachments[copies[i].id] = attachment }
        }
        guides.append(contentsOf: copies)
        select(ids: Set(copies.map(\.id)), displayID: display.id); commitTransaction()
    }

    func armWindowPicker() {
        guard !selectedIDs.isEmpty else { return }
        setEditing(true); isPickingWindow = true; attachmentMessage = nil
    }

    func detachSelection() {
        beginTransaction()
        attachments = attachments.filter { !selectedIDs.contains($0.key) }
        hiddenGuideIDs.subtract(selectedIDs)
        attachmentMessage = "Selected guides now stay fixed on screen."
        commitTransaction()
    }

    func refreshAttachmentOffsets() {
        for guide in guides {
            guard var attachment = attachments[guide.id], let display = displays.first(where: { $0.id == guide.displayID }) else { continue }
            let start = display.global(guide.start), end = display.global(guide.end)
            attachment.startOffset = Position(start.x - attachment.window.frame.minX, start.y - attachment.window.frame.minY)
            attachment.endOffset = Position(end.x - attachment.window.frame.minX, end.y - attachment.window.frame.minY)
            if attachment != attachments[guide.id] { attachments[guide.id] = attachment }
        }
    }

    func shortcutLabel(_ action: ShortcutAction) -> String { shortcuts[action]?.display ?? "—" }
    func undo() { commitTransaction(); undoHistory.undo() }
    func redo() { commitTransaction(); undoHistory.redo() }

    func valueLabel(for guide: Guide) -> String {
        let scale = displays.first { $0.id == guide.displayID }?.geometry.scale ?? 1
        let f = unit.factor(scale: scale)
        switch guide.kind {
        case .vertical: return "X \(format(guide.start.x * f)) \(unit.suffix)"
        case .horizontal: return "Y \(format(guide.start.y * f)) \(unit.suffix)"
        case .segment: return "\(format(guide.length * f)) \(unit.suffix)"
        }
    }

    func distanceLabel(for gap: GuideGap, scale: Double) -> String {
        "\(format(gap.value(unit: unit, scale: scale))) \(unit.suffix)"
    }

    func distanceAnchor(for display: DisplayInfo) -> Position {
        let fallback = Position(display.geometry.width / 2, display.screen.frame.maxY - display.screen.visibleFrame.maxY + 160)
        return display.geometry.clamped(distanceAnchors[display.id] ?? fallback)
    }

    private func scheduleSave() {
        guard storageURL != nil else { return }
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.save() }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
    }

    func save() {
        guard let storageURL else { return }
        let saved = SavedState(guides: guides, unit: unit, showLabels: showLabels,
                               defaultColor: defaultColor, defaultOpacity: defaultOpacity, defaultWidth: defaultWidth,
                               showDistances: showDistances, distanceAnchors: distanceAnchors,
                               highContrast: highContrast, shortcuts: Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) }), loupeZoom: loupeZoom)
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(saved)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            if persistenceError == nil { persistenceError = "Guides could not be saved: \(error.localizedDescription)" }
        }
    }
}

func format(_ value: Double) -> String {
    if value == value.rounded() { return String(format: "%.0f", value) }
    return String(format: "%.1f", value)
}
