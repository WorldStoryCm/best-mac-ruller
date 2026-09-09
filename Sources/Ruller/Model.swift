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
}

@MainActor final class RullerModel: ObservableObject {
    @Published var guides: [Guide] = []
    @Published var selectedID: UUID?
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
    var revealPanel: (() -> Void)?
    var onInteractionChange: (() -> Void)?
    var undoHistory = UndoManager()
    private var transactionStart: [Guide]?
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
    var activeDisplay: DisplayInfo? { displays.first { $0.id == activeDisplayID } ?? displays.first }
    var selectedDisplay: DisplayInfo? { displays.first { $0.id == selected?.displayID } ?? activeDisplay }
    var factor: Double { unit.factor(scale: selectedDisplay?.geometry.scale ?? 1) }
    var visibleGuides: [Guide] { guides.filter { $0.displayID == activeDisplayID } }
    var visibleGaps: [GuideGap] { GuideGap.adjacent(in: guides, displayID: activeDisplayID) }
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

    func select(_ id: UUID?) {
        selectedID = id
        if let selected { activeDisplayID = selected.displayID }
    }

    func setEditing(_ editing: Bool) {
        commitTransaction()
        isEditing = editing; tool = nil
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
        if transactionStart == nil { transactionStart = guides }
    }

    func commitTransaction() {
        guard let before = transactionStart else { return }
        transactionStart = nil
        guard before != guides else { return }
        registerUndo(before)
    }

    private func registerUndo(_ old: [Guide]) {
        undoHistory.beginUndoGrouping()
        undoHistory.registerUndo(withTarget: self) { model in
            let current = model.guides
            model.guides = old
            model.registerUndo(current)
            if !old.contains(where: { $0.id == model.selectedID }) { model.selectedID = old.last?.id }
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
        changeSelected { $0.translate(dx: dx * step, dy: dy * step, in: display.geometry) }
    }

    func setCoordinate(_ value: Double, axis: String) {
        guard value.isFinite, let display = selectedDisplay else { return }
        let raw = value / factor
        let position = (raw * display.geometry.scale).rounded() / display.geometry.scale
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

    func setColor(_ value: GuideColor) { defaultColor = value; changeSelected { $0.color = value } }
    func setOpacity(_ value: Double) { defaultOpacity = value; changeSelected { $0.opacity = value } }
    func setWidth(_ value: Int) { defaultWidth = value; changeSelected { $0.widthPixels = value } }
    func deleteSelected() {
        guard let id = selectedID else { return }
        beginTransaction(); guides.removeAll { $0.id == id }; selectedID = visibleGuides.last?.id; commitTransaction()
    }
    func clear() { beginTransaction(); guides.removeAll(); selectedID = nil; commitTransaction() }
    func duplicate() {
        guard var copy = selected, let display = selectedDisplay else { return }
        beginTransaction(); copy.id = UUID(); copy.translate(dx: 20, dy: 20, in: display.geometry)
        guides.append(copy); selectedID = copy.id; commitTransaction()
    }
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
                               showDistances: showDistances, distanceAnchors: distanceAnchors)
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
