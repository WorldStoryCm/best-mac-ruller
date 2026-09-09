import Foundation
import CoreGraphics

public struct LoupeSample: Equatable {
    public let pixelRect: CGRect
    public let cursorPixel: Position
    public init(point: Position, display: DisplayGeometry, radius: Int) {
        let width = max(1, Int((display.width * display.scale).rounded()))
        let height = max(1, Int((display.height * display.scale).rounded()))
        let x = min(max(0, Int(floor(point.x * display.scale))), width - 1)
        let y = min(max(0, Int(floor(point.y * display.scale))), height - 1)
        let count = max(1, radius * 2 + 1)
        let w = min(width, count), h = min(height, count)
        let left = min(max(0, x - radius), width - w), top = min(max(0, y - radius), height - h)
        pixelRect = CGRect(x: left, y: top, width: w, height: h)
        cursorPixel = Position(Double(x - left), Double(y - top))
    }
}
