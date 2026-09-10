// Documentation fixture: renders the real palette and overlay over sample content.
// No desktop capture, saved user state, window tracking, or global shortcuts.
import AppKit
import SwiftUI
import RullerCore

@MainActor private func bitmap(of view: NSView) -> NSBitmapImageRep {
    view.layoutSubtreeIfNeeded()
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return bitmap
}

private final class ExamplePage: NSView {
    override var isFlipped: Bool { true }
    let scale: Double
    init(scale: Double, size: NSSize) {
        self.scale = scale
        super.init(frame: NSRect(origin: .zero, size: size))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func box(_ rect: NSRect, fill: NSColor, radius: CGFloat = 0) {
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
    private func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat,
                      weight: NSFont.Weight = .regular, color: NSColor = .labelColor) {
        (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color
        ])
    }
    override func draw(_ dirtyRect: NSRect) {
        box(bounds, fill: NSColor(srgbRed: 0.87, green: 0.91, blue: 0.92, alpha: 1))
        let paper = NSRect(x: 28, y: 36, width: 802, height: 740)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.13)
        shadow.shadowBlurRadius = 20; shadow.shadowOffset = NSSize(width: 0, height: -5); shadow.set()
        box(paper, fill: .white, radius: 14)
        NSGraphicsContext.restoreGraphicsState()
        box(NSRect(x: 28, y: 36, width: 802, height: 58), fill: NSColor(white: 0.96, alpha: 1), radius: 14)
        box(NSRect(x: 28, y: 80, width: 802, height: 14), fill: NSColor(white: 0.96, alpha: 1))
        for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            box(NSRect(x: 48 + i * 19, y: 58, width: 11, height: 11), fill: color, radius: 6)
        }
        box(NSRect(x: 155, y: 47, width: 420, height: 33), fill: .white, radius: 7)
        text("example.com / journal", x: 178, y: 56, size: 12, color: .secondaryLabelColor)
        text("FIELDNOTES", x: 100, y: 130, size: 14, weight: .bold)
        text("Journal", x: 591, y: 131, size: 13, weight: .semibold)
        text("About", x: 678, y: 131, size: 13, color: .secondaryLabelColor)
        text("Small details. Better days.", x: 100, y: 210, size: 34, weight: .semibold)
        text("A journal about design, daily rituals, and making space.", x: 100, y: 264, size: 16,
             color: .secondaryLabelColor)
        // The guide at the intro's lower edge and the card top are 64 backing pixels apart.
        let cardY = 300 + 64 / scale
        box(NSRect(x: 100, y: cardY, width: 660, height: 166),
            fill: NSColor(srgbRed: 0.93, green: 0.95, blue: 0.91, alpha: 1), radius: 12)
        text("THE WEEKEND EDIT", x: 126, y: cardY + 27, size: 11, weight: .semibold,
             color: NSColor(srgbRed: 0.30, green: 0.39, blue: 0.28, alpha: 1))
        text("Less noise, more room.", x: 126, y: cardY + 58, size: 27, weight: .medium)
        text("Simple observations for a slower, more intentional week.",
             x: 126, y: cardY + 106, size: 14, color: .secondaryLabelColor)
        // A second section deliberately starts 2 backing pixels to the right.
        let shiftedX = 100 + 2 / scale
        text("Latest notes", x: shiftedX, y: 568, size: 22, weight: .semibold)
        text("On noticing the small things", x: shiftedX, y: 608, size: 16, weight: .medium)
        text("Five minutes of attention can change the shape of a day.",
             x: shiftedX, y: 638, size: 14, color: .secondaryLabelColor)
        text("DESIGN   /   4 MIN READ", x: shiftedX, y: 710, size: 10, weight: .medium,
             color: .secondaryLabelColor)
    }
}

@main private enum RenderExample {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: .aqua)
        let model = RullerModel(storageURL: nil)
        guard let display = model.displays.first else { fatalError("A graphical macOS session is required") }
        model.displays = [display]
        model.unit = .pixels; model.showLabels = false
        let scale = display.geometry.scale
        model.guides = [
            Guide(displayID: display.id, kind: .vertical, start: Position(100, 0), color: .coral, opacity: 1),
            Guide(displayID: display.id, kind: .vertical, start: Position(100 + 2 / scale, 0), color: .violet, opacity: 1),
            Guide(displayID: display.id, kind: .horizontal, start: Position(0, 300), color: .cyan, opacity: 1),
            Guide(displayID: display.id, kind: .horizontal, start: Position(0, 300 + 64 / scale), color: .cyan, opacity: 1)
        ]
        model.selectAll()
        model.distanceAnchors[display.id] = Position(650, 678)
        let size = NSSize(width: 1240, height: 820)
        let page = ExamplePage(scale: scale, size: size)
        let overlay = OverlayView(model: model, display: display)
        overlay.setFrameSize(size)
        let overlayBitmap = bitmap(of: overlay)
        let overlayImage = NSImage(size: size); overlayImage.addRepresentation(overlayBitmap)
        let guides = NSImageView(frame: page.bounds); guides.image = overlayImage
        guides.imageScaling = .scaleAxesIndependently
        page.addSubview(guides)

        let palette = NSHostingView(rootView: PaletteView(model: model))
        palette.setFrameSize(palette.fittingSize)
        let shell = NSView(frame: NSRect(x: 860, y: 36, width: 350, height: palette.frame.height + 24))
        shell.wantsLayer = true
        shell.layer?.backgroundColor = NSColor(white: 0.94, alpha: 1).cgColor
        shell.layer?.cornerRadius = 12
        shell.layer?.borderWidth = 0.5
        shell.layer?.borderColor = NSColor.black.withAlphaComponent(0.2).cgColor
        shell.addSubview(palette)
        let close = NSButton(frame: NSRect(x: 12, y: palette.frame.height + 7, width: 11, height: 11))
        close.title = ""; close.isBordered = false; close.wantsLayer = true
        close.layer?.backgroundColor = NSColor(white: 0.78, alpha: 1).cgColor
        close.layer?.cornerRadius = 5.5
        shell.addSubview(close)
        page.addSubview(shell)
        // An unshown window supplies AppKit layout/backing context; no user windows are read.
        let window = NSWindow(contentRect: page.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = page
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        let output = URL(fileURLWithPath: CommandLine.arguments.last!)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let result = bitmap(of: page)
        try result.representation(using: .png, properties: [:])!.write(to: output)
        print("Rendered example: \(result.pixelsWide)×\(result.pixelsHigh), real Ruller views, synthetic page")
    }
}
