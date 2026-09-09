import Foundation

/// Distance between guide coordinates, independent of the lines' stroke thickness.
public struct GuideGap: Identifiable, Equatable {
    public let firstID: UUID
    public let secondID: UUID
    public let kind: GuideKind
    public let lower: Double
    public let upper: Double
    public var id: String { "\(firstID):\(secondID)" }
    public var distance: Double { upper - lower }
    public var midpoint: Double { (lower + upper) / 2 }
    public func value(unit: MeasurementUnit, scale: Double) -> Double {
        distance * unit.factor(scale: scale)
    }

    public static func adjacent(in guides: [Guide], displayID: String) -> [GuideGap] {
        [GuideKind.horizontal, .vertical].flatMap { kind -> [GuideGap] in
            let ordered = guides.enumerated().filter { $0.element.displayID == displayID && $0.element.kind == kind }
                .sorted {
                    let a = kind == .horizontal ? $0.element.start.y : $0.element.start.x
                    let b = kind == .horizontal ? $1.element.start.y : $1.element.start.x
                    return a == b ? $0.offset < $1.offset : a < b
                }.map(\.element)
            return zip(ordered, ordered.dropFirst()).map { first, second in
                GuideGap(firstID: first.id, secondID: second.id, kind: kind,
                         lower: kind == .horizontal ? first.start.y : first.start.x,
                         upper: kind == .horizontal ? second.start.y : second.start.x)
            }
        }
    }
}

/// Pack labels along one axis. On dense runs, use additional lanes so even 1 px gaps stay legible.
public enum GapLabelLayout {
    public struct Placement: Equatable {
        public let center: Double
        public let lane: Int
    }
    public static func arrange(centers: [Double], lengths: [Double], lower: Double, upper: Double, spacing: Double = 6) -> [Placement] {
        precondition(centers.count == lengths.count)
        guard !centers.isEmpty else { return [] }
        let available = max(1, upper - lower)
        var output = Array(repeating: Placement(center: lower, lane: 0), count: centers.count)
        var batches: [[Int]] = [[]]
        var occupied = 0.0
        for index in centers.indices.sorted(by: { centers[$0] < centers[$1] }) {
            let length = min(max(1, lengths[index]), available)
            let required = length + (batches[batches.count - 1].isEmpty ? 0 : spacing)
            if occupied + required > available && !batches[batches.count - 1].isEmpty {
                batches.append([]); occupied = 0
            }
            occupied += length + (batches[batches.count - 1].isEmpty ? 0 : spacing)
            batches[batches.count - 1].append(index)
        }
        for (lane, batch) in batches.enumerated() {
            var edges: [Double] = []
            for index in batch {
                let length = min(max(1, lengths[index]), available)
                let previous = edges.last.map { $0 + min(max(1, lengths[batch[edges.count - 1]]), available) + spacing } ?? lower
                edges.append(max(previous, min(max(centers[index] - length / 2, lower), upper - length)))
            }
            for j in batch.indices.reversed() {
                let length = min(max(1, lengths[batch[j]]), available)
                let limit = j == batch.count - 1 ? upper - length : edges[j + 1] - spacing - length
                edges[j] = min(edges[j], limit)
                output[batch[j]] = Placement(center: edges[j] + length / 2, lane: lane)
            }
        }
        return output
    }
}
