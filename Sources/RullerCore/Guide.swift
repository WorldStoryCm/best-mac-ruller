import Foundation

public enum GuideKind: String, Codable, CaseIterable {
    case vertical, horizontal, segment
    public var title: String {
        switch self { case .vertical: return "Vertical"; case .horizontal: return "Horizontal"; case .segment: return "Line" }
    }
    public var symbol: String {
        switch self { case .vertical: return "arrow.up.and.down"; case .horizontal: return "arrow.left.and.right"; case .segment: return "line.diagonal" }
    }
}

public enum GuideColor: String, Codable, CaseIterable {
    case coral, cyan, lime, violet, white, black
    public var rgb: (Double, Double, Double) {
        switch self {
        case .coral: return (1, 0.26, 0.33)
        case .cyan: return (0, 0.72, 1)
        case .lime: return (0.56, 0.88, 0.12)
        case .violet: return (0.66, 0.40, 1)
        case .white: return (1, 1, 1)
        case .black: return (0, 0, 0)
        }
    }
}

public enum MeasurementUnit: String, Codable, CaseIterable {
    case points, pixels
    public var suffix: String { self == .points ? "pt" : "px" }
    public func factor(scale: Double) -> Double { self == .pixels ? scale : 1 }
    public func step(scale: Double) -> Double { 1 / factor(scale: scale) }
}

public struct Position: Codable, Equatable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}

public struct DisplayGeometry: Equatable {
    public var width: Double
    public var height: Double
    public var scale: Double
    public init(width: Double, height: Double, scale: Double) {
        self.width = width; self.height = height; self.scale = max(scale, 1)
    }
    public var maxX: Double { max(0, width - 1 / scale) }
    public var maxY: Double { max(0, height - 1 / scale) }
    public func clamped(_ p: Position) -> Position {
        Position(min(max(0, p.x), maxX), min(max(0, p.y), maxY))
    }
    public func snapped(_ p: Position, unit: MeasurementUnit) -> Position {
        let f = unit.factor(scale: scale)
        return clamped(Position((p.x * f).rounded() / f, (p.y * f).rounded() / f))
    }
}

public struct Guide: Identifiable, Codable, Equatable {
    public var id: UUID
    public var displayID: String
    public var kind: GuideKind
    public var start: Position
    public var end: Position
    public var color: GuideColor
    public var opacity: Double
    public var widthPixels: Int
    public init(id: UUID = UUID(), displayID: String, kind: GuideKind, start: Position,
                end: Position? = nil, color: GuideColor = .coral, opacity: Double = 0.85, widthPixels: Int = 1) {
        self.id = id; self.displayID = displayID; self.kind = kind; self.start = start
        self.end = end ?? start; self.color = color; self.opacity = opacity; self.widthPixels = widthPixels
    }

    public var length: Double { hypot(end.x - start.x, end.y - start.y) }

    public func distance(to point: Position) -> Double {
        switch kind {
        case .vertical: return abs(point.x - start.x)
        case .horizontal: return abs(point.y - start.y)
        case .segment:
            let dx = end.x - start.x, dy = end.y - start.y
            let squared = dx * dx + dy * dy
            guard squared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
            let t = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / squared, 0), 1)
            return hypot(point.x - start.x - t * dx, point.y - start.y - t * dy)
        }
    }

    /// Clamp the translation, preserving a segment's length at screen edges.
    public mutating func translate(dx: Double, dy: Double, in display: DisplayGeometry) {
        let loX = kind == .segment ? min(start.x, end.x) : start.x
        let hiX = kind == .segment ? max(start.x, end.x) : start.x
        let loY = kind == .segment ? min(start.y, end.y) : start.y
        let hiY = kind == .segment ? max(start.y, end.y) : start.y
        let x = kind == .horizontal ? 0 : min(max(dx, -loX), display.maxX - hiX)
        let y = kind == .vertical ? 0 : min(max(dy, -loY), display.maxY - hiY)
        start.x += x; end.x += x; start.y += y; end.y += y
    }

    public static func constrainedEndpoint(from start: Position, to end: Position) -> Position {
        let length = hypot(end.x - start.x, end.y - start.y)
        let angle = (atan2(end.y - start.y, end.x - start.x) / (.pi / 4)).rounded() * (.pi / 4)
        return Position(start.x + cos(angle) * length, start.y + sin(angle) * length)
    }
}

public struct SavedState: Codable {
    public var version = 1
    public var guides: [Guide]
    public var unit: MeasurementUnit
    public var showLabels: Bool
    public var defaultColor: GuideColor
    public var defaultOpacity: Double
    public var defaultWidth: Int
    // Optional additions keep version 1 files from earlier releases readable.
    public var showDistances: Bool?
    public var distanceAnchors: [String: Position]?
    public init(guides: [Guide], unit: MeasurementUnit, showLabels: Bool,
                defaultColor: GuideColor, defaultOpacity: Double, defaultWidth: Int,
                showDistances: Bool = true, distanceAnchors: [String: Position] = [:]) {
        self.guides = guides; self.unit = unit; self.showLabels = showLabels
        self.defaultColor = defaultColor; self.defaultOpacity = defaultOpacity; self.defaultWidth = defaultWidth
        self.showDistances = showDistances; self.distanceAnchors = distanceAnchors
    }
}
