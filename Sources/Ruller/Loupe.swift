import AppKit
import ScreenCaptureKit
import CoreImage
import RullerCore

final class LoupeRenderer {
    private let context = CIContext(options: [.cacheIntermediates: false])
    func crop(_ buffer: CVPixelBuffer, sample: LoupeSample) -> CGImage? {
        let full = CIImage(cvPixelBuffer: buffer), r = sample.pixelRect
        return context.createCGImage(full, from: CGRect(x: r.minX, y: full.extent.height - r.maxY, width: r.width, height: r.height))
    }
}

// ScreenCaptureKit supplies immutable pixel buffers. Retaining the buffer keeps
// its IOSurface alive until the main-thread renderer releases this frame.
private struct CapturedFrame: @unchecked Sendable {
    let pixels: CVPixelBuffer
    let streamID: ObjectIdentifier
}

@MainActor final class LoupeController: NSObject, SCStreamOutput, SCStreamDelegate {
    private unowned let model: RullerModel
    private let panel: NSPanel
    let view = LoupeView(frame: NSRect(x: 0, y: 0, width: 208, height: 244))
    private let renderer = LoupeRenderer()
    private var stream: SCStream?
    private var buffer: CVPixelBuffer?
    private var displayID: String?
    private var timer: Timer?
    private var starting = false
    private var generation = 0
    private var lastMouse: NSPoint?

    init(model: RullerModel) {
        self.model = model
        panel = NSPanel(contentRect: view.bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        if #available(macOS 14.0, *) { panel.collectionBehavior.insert(.canJoinAllApplications) }
        panel.contentView = view
        panel.setAccessibilityLabel("Ruller pixel loupe")
    }

    func toggle() {
        if model.loupeEnabled { stop(); return }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            model.loupeError = "Loupe needs Screen Recording access to read pixels. Allow Ruller in System Settings, then try again."
            model.revealPanel?(); return
        }
        model.loupeError = nil; model.loupeEnabled = true
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        tick()
    }

    func stop() {
        generation += 1; starting = false
        timer?.invalidate(); timer = nil; buffer = nil; displayID = nil
        view.image = nil; panel.orderOut(nil)
        model.loupeEnabled = false; model.loupeFocus = nil
        let old = stream; stream = nil
        if let old { Task { try? await old.stopCapture() } }
    }

    private func startCapture(on display: DisplayInfo) {
        starting = true; generation += 1
        let request = generation
        let old = stream; stream = nil; buffer = nil; displayID = nil
        Task { [weak self] in
            guard let self else { return }
            if let old { try? await old.stopCapture() }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard self.model.loupeEnabled, self.generation == request else { return }
                let number = (display.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                guard let source = content.displays.first(where: { $0.displayID == number }) else { throw CocoaError(.featureUnsupported) }
                let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display: source, excludingApplications: ownApp, exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.width = Int((display.geometry.width * display.geometry.scale).rounded())
                config.height = Int((display.geometry.height * display.geometry.scale).rounded())
                config.minimumFrameInterval = CMTime(value: 1, timescale: 15)
                config.queueDepth = 3; config.showsCursor = false; config.capturesAudio = false
                config.pixelFormat = kCVPixelFormatType_32BGRA
                let capture = SCStream(filter: filter, configuration: config, delegate: self)
                try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "Ruller.loupe.frames"))
                self.stream = capture; self.displayID = display.id
                try await capture.startCapture()
                if self.generation != request { try? await capture.stopCapture(); return }
                self.starting = false
            } catch {
                guard self.generation == request else { return }
                self.stop()
                self.model.loupeError = "Loupe could not start: \(error.localizedDescription)"
            }
        }
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let frame = CapturedFrame(pixels: pixels, streamID: ObjectIdentifier(stream))
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream.map(ObjectIdentifier.init) == frame.streamID, self.model.loupeEnabled else { return }
            self.buffer = frame.pixels // Retain one IOSurface; only the small loupe crop is rendered.
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let identity = ObjectIdentifier(stream)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream.map(ObjectIdentifier.init) == identity else { return }
            self.stop(); self.model.loupeError = "Screen capture stopped. Enable Loupe to try again."
        }
    }

    private func tick() {
        guard model.loupeEnabled else { return }
        let mouse = NSEvent.mouseLocation
        if lastMouse != mouse { model.loupeFocus = nil; lastMouse = mouse }
        let focusDisplay = model.loupeFocus.flatMap { focus in model.displays.first { $0.id == focus.0 } }
        guard let display = focusDisplay ?? model.displays.first(where: { $0.screen.frame.contains(mouse) }) else { panel.orderOut(nil); return }
        let point = model.loupeFocus?.1 ?? Position(mouse.x - display.screen.frame.minX, display.screen.frame.maxY - mouse.y)
        if displayID != display.id && !starting { startCapture(on: display) }
        let scale = display.geometry.scale
        let cell = Double(model.loupeZoom) / scale
        let radius = Int(ceil(192 / cell / 2))
        let sample = LoupeSample(point: point, display: display.geometry, radius: radius)
        view.cellSize = cell; view.cursorPixel = sample.cursorPixel
        if let buffer, displayID == display.id {
            view.image = renderer.crop(buffer, sample: sample)
        } else { view.image = nil }
        let f = model.unit.factor(scale: scale)
        view.caption = "X \(format(floor(point.x * scale) / scale * f))  Y \(format(floor(point.y * scale) / scale * f)) \(model.unit.suffix)"
        view.zoomCaption = "\(model.loupeZoom)× · \(model.shortcutLabel(.loupe)) to hide"
        view.needsDisplay = true
        let frame = display.screen.visibleFrame
        var x = mouse.x + 28, y = mouse.y - panel.frame.height - 28
        if x + panel.frame.width > frame.maxX { x = mouse.x - panel.frame.width - 28 }
        if y < frame.minY { y = mouse.y + 28 }
        x = min(max(x, frame.minX), frame.maxX - panel.frame.width)
        y = min(max(y, frame.minY), frame.maxY - panel.frame.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y)); panel.orderFrontRegardless()
    }
}

final class LoupeView: NSView {
    var image: CGImage?
    var cursorPixel = Position(0, 0)
    var cellSize = 4.0
    var caption = ""
    var zoomCaption = ""
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor(white: 0.10, alpha: 0.98).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        let viewport = CGRect(x: 8, y: 8, width: 192, height: 192)
        context.saveGState(); context.clip(to: viewport)
        if let image {
            // Center the pointer's exact backing pixel, even at the display edges.
            let origin = CGPoint(x: viewport.midX - (cursorPixel.x + 0.5) * cellSize,
                                 y: viewport.midY - (cursorPixel.y + 0.5) * cellSize)
            let target = CGRect(origin: origin, size: CGSize(width: Double(image.width) * cellSize, height: Double(image.height) * cellSize))
            NSGraphicsContext.current?.imageInterpolation = .none
            NSImage(cgImage: image, size: target.size).draw(in: target, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            if cellSize >= 4 {
                let grid = NSBezierPath(); grid.lineWidth = 0.5
                for x in 0...image.width { grid.move(to: CGPoint(x: origin.x + Double(x) * cellSize, y: target.minY)); grid.line(to: CGPoint(x: origin.x + Double(x) * cellSize, y: target.maxY)) }
                for y in 0...image.height { grid.move(to: CGPoint(x: target.minX, y: origin.y + Double(y) * cellSize)); grid.line(to: CGPoint(x: target.maxX, y: origin.y + Double(y) * cellSize)) }
                NSColor.black.withAlphaComponent(0.25).setStroke(); grid.stroke()
            }
            let pixel = NSBezierPath(rect: CGRect(x: viewport.midX - cellSize / 2, y: viewport.midY - cellSize / 2, width: cellSize, height: cellSize))
            NSColor.white.setStroke(); pixel.lineWidth = 3; pixel.stroke()
            NSColor.systemRed.setStroke(); pixel.lineWidth = 1.5; pixel.stroke()
        } else {
            ("Starting loupe…" as NSString).draw(at: CGPoint(x: 48, y: 92), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.white])
        }
        context.restoreGState()
        (caption as NSString).draw(at: CGPoint(x: 10, y: 207), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.white])
        (zoomCaption as NSString).draw(at: CGPoint(x: 10, y: 225), withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.lightGray])
    }
}
