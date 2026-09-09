import Foundation
import CoreGraphics

public enum GuideSelection {
    /// One shared, constrained translation keeps every selected gap unchanged.
    public static func translated(_ guides: [Guide], dx: Double, dy: Double, in display: DisplayGeometry) -> [Guide] {
        var minDX = -Double.infinity, maxDX = Double.infinity
        var minDY = -Double.infinity, maxDY = Double.infinity
        for g in guides {
            if g.kind != .horizontal {
                minDX = max(minDX, -min(g.start.x, g.end.x))
                maxDX = min(maxDX, display.maxX - max(g.start.x, g.end.x))
            }
            if g.kind != .vertical {
                minDY = max(minDY, -min(g.start.y, g.end.y))
                maxDY = min(maxDY, display.maxY - max(g.start.y, g.end.y))
            }
        }
        let x = minDX <= maxDX ? min(max(dx, minDX), maxDX) : 0
        let y = minDY <= maxDY ? min(max(dy, minDY), maxDY) : 0
        return guides.map { original in
            var g = original
            if g.kind != .horizontal { g.start.x += x; g.end.x += x }
            if g.kind != .vertical { g.start.y += y; g.end.y += y }
            return g
        }
    }

    public static func intersects(_ guide: Guide, rect: CGRect) -> Bool {
        let r = rect.standardized
        switch guide.kind {
        case .vertical: return (r.minX...r.maxX).contains(guide.start.x)
        case .horizontal: return (r.minY...r.maxY).contains(guide.start.y)
        case .segment:
            // Clip the finite segment against the selection rectangle.
            var lower = 0.0, upper = 1.0
            let dx = guide.end.x - guide.start.x, dy = guide.end.y - guide.start.y
            for (p, q) in [(-dx, guide.start.x - r.minX), (dx, r.maxX - guide.start.x),
                           (-dy, guide.start.y - r.minY), (dy, r.maxY - guide.start.y)] {
                if p == 0 { if q < 0 { return false }; continue }
                let t = q / p
                if p < 0 { lower = max(lower, t) } else { upper = min(upper, t) }
                if lower > upper { return false }
            }
            return true
        }
    }
}
