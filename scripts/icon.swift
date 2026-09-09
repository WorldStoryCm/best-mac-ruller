import AppKit
import Foundation

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for multiplier in [1, 2] {
        let size = points * multiplier
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let scale = Double(size) / 1024
        let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
        let rect = NSRect(x: 64, y: 64, width: 896, height: 896)
        NSColor(srgbRed: 0.13, green: 0.14, blue: 0.16, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 205, yRadius: 205).fill()
        NSColor(srgbRed: 0.91, green: 0.87, blue: 0.78, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 230, y: 232, width: 160, height: 560), xRadius: 25, yRadius: 25).fill()
        for i in 0..<9 {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 230, y: 282 + i * 56))
            path.line(to: NSPoint(x: i % 2 == 0 ? 310 : 277, y: 282 + i * 56))
            path.lineWidth = 10; NSColor(srgbRed: 0.19, green: 0.20, blue: 0.22, alpha: 1).setStroke(); path.stroke()
        }
        NSColor(srgbRed: 1, green: 0.29, blue: 0.35, alpha: 1).setFill()
        NSRect(x: 495, y: 165, width: 10, height: 700).fill()
        NSRect(x: 170, y: 412, width: 690, height: 10).fill()
        NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: 480, y: 397, width: 40, height: 40)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png, properties: [:])!
        let suffix = multiplier == 2 ? "@2x" : ""
        try data.write(to: URL(fileURLWithPath: "\(output)/icon_\(points)x\(points)\(suffix).png"))
    }
}
