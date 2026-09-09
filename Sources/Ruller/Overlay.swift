import AppKit
import RullerCore

extension GuideColor {
    var nsColor: NSColor {
        let (r, g, b) = rgb
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct GapAnnotation {
    let gap: GuideGap
    let start: CGPoint
    let end: CGPoint
    let badge: CGRect
    let text: String
}

@MainActor final class OverlayView: NSView {
    let model: RullerModel
    let display: DisplayInfo
    private var hover: Position?
    private var origin: Position?
    private var originalGuide: Guide?
    private var originalSelection: [Guide] = []
    private var marquee: CGRect?
    private var marqueeBase: Set<UUID>?
    private var newGuideID: UUID?
    private var movingEndpoint: Int?
    private var tracking: NSTrackingArea?
    private var draggingDistances: GuideKind?
    private var distanceDragAnchor: Position?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(model: RullerModel, display: DisplayInfo) {
        self.model = model; self.display = display
        super.init(frame: NSRect(origin: .zero, size: display.screen.frame.size))
        setAccessibilityLabel("Ruller overlay on \(display.name)")
        setAccessibilityHelp("Place or drag a guide. Arrow keys nudge. Escape makes the overlay click through.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }

    func resetGesture() {
        hover = nil; origin = nil; originalGuide = nil; newGuideID = nil; movingEndpoint = nil
        draggingDistances = nil; distanceDragAnchor = nil
        originalSelection = []; marquee = nil; marqueeBase = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        guard model.isVisible else { return }
        if model.isEditing {
            NSColor.black.withAlphaComponent(0.015).setFill(); bounds.fill()
        }
        let guides = model.drawableGuides.filter { $0.displayID == display.id }
        if model.highContrast {
            context.saveGState()
            // Keep every colored guide clear, including neighboring 1 px gaps.
            // Intersect successive exclusions so coincident guides remain excluded too.
            for guide in guides {
                context.addRect(bounds); context.addPath(guideBody(guide)); context.clip(using: .evenOdd)
            }
            for guide in guides { draw(guide, context: context, selected: false, outlineOnly: true) }
            context.restoreGState()
        }
        for guide in guides {
            draw(guide, context: context, selected: model.isEditing && model.selectedIDs.contains(guide.id))
        }
        for annotation in distanceAnnotations() { drawDistance(annotation) }
        if let marquee {
            NSColor.systemBlue.withAlphaComponent(0.12).setFill(); marquee.fill()
            NSColor.systemBlue.setStroke(); NSBezierPath(rect: marquee).stroke()
        }
        if model.isEditing, let tool = model.tool, let hover, origin == nil {
            let preview = Guide(displayID: display.id, kind: tool, start: hover, color: model.defaultColor,
                                opacity: 0.5, widthPixels: model.defaultWidth)
            if tool != .segment { draw(preview, context: context, selected: false) }
        }
        if model.isEditing {
            let message = model.isPickingWindow ? "CLICK A WINDOW  ·  Attach \(model.selectedIDs.count) guides  ·  Esc to cancel" : model.tool.map { "\($0.title.uppercased())  ·  \($0 == .segment ? "Drag to draw" : "Click to place")  ·  Esc to finish" }
                ?? "EDITING  ·  Shift-click or drag to select  ·  Esc to finish"
            drawBadge(message, at: CGPoint(x: bounds.midX - 205, y: display.screen.frame.maxY - display.screen.visibleFrame.maxY + 12), maximumWidth: 450)
        }
    }

    private func guideBody(_ guide: Guide) -> CGPath {
        let scale = display.geometry.scale, width = Double(guide.widthPixels) / scale
        let x = (guide.start.x * scale).rounded() / scale, y = (guide.start.y * scale).rounded() / scale
        if guide.kind == .vertical { return CGPath(rect: CGRect(x: x, y: 0, width: width, height: bounds.height), transform: nil) }
        if guide.kind == .horizontal { return CGPath(rect: CGRect(x: 0, y: y, width: bounds.width, height: width), transform: nil) }
        let offset = guide.widthPixels % 2 == 1 ? 0.5 / scale : 0
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x + offset, y: y + offset))
        path.addLine(to: CGPoint(x: (guide.end.x * scale).rounded() / scale + offset, y: (guide.end.y * scale).rounded() / scale + offset))
        return path.copy(strokingWithWidth: width, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
    }

    private func draw(_ guide: Guide, context: CGContext, selected: Bool, outlineOnly: Bool = false) {
        let scale = display.geometry.scale
        let width = Double(guide.widthPixels) / scale
        let x = (guide.start.x * scale).rounded() / scale
        let y = (guide.start.y * scale).rounded() / scale
        context.saveGState()
        context.setAlpha(guide.opacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        if outlineOnly {
            // Black and white borders stay visible on either background without screen capture.
            for (extra, color) in [(4.0 / scale, NSColor.white), (2.0 / scale, NSColor.black)] {
                context.setFillColor(color.cgColor); context.setStrokeColor(color.cgColor)
                if guide.kind == .vertical {
                    context.setShouldAntialias(false)
                    context.fill(CGRect(x: x - extra / 2, y: 0, width: width + extra, height: bounds.height))
                } else if guide.kind == .horizontal {
                    context.setShouldAntialias(false)
                    context.fill(CGRect(x: 0, y: y - extra / 2, width: bounds.width, height: width + extra))
                } else {
                    let offset = guide.widthPixels % 2 == 1 ? 0.5 / scale : 0
                    context.setLineWidth(width + extra)
                    context.move(to: CGPoint(x: x + offset, y: y + offset))
                    context.addLine(to: CGPoint(x: (guide.end.x * scale).rounded() / scale + offset,
                                               y: (guide.end.y * scale).rounded() / scale + offset))
                    context.strokePath()
                }
            }
            context.endTransparencyLayer(); context.restoreGState()
            return
        }
        context.setFillColor(guide.color.nsColor.cgColor)
        context.setStrokeColor(guide.color.nsColor.cgColor)
        switch guide.kind {
        case .vertical:
            context.setShouldAntialias(false)
            context.fill(CGRect(x: x, y: 0, width: width, height: bounds.height))
        case .horizontal:
            context.setShouldAntialias(false)
            context.fill(CGRect(x: 0, y: y, width: bounds.width, height: width))
        case .segment:
            let offset = guide.widthPixels % 2 == 1 ? 0.5 / scale : 0
            context.setLineWidth(width); context.setLineCap(.butt)
            context.move(to: CGPoint(x: x + offset, y: y + offset))
            context.addLine(to: CGPoint(x: (guide.end.x * scale).rounded() / scale + offset,
                                       y: (guide.end.y * scale).rounded() / scale + offset))
            context.strokePath()
        }
        context.endTransparencyLayer()
        context.restoreGState()

        if selected {
            for p in handles(for: guide) {
                let circle = NSBezierPath(ovalIn: NSRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                guide.color.nsColor.setFill(); circle.fill()
                NSColor.white.setStroke(); circle.lineWidth = 1.5; circle.stroke()
            }
        }
        if model.showLabels {
            let safeTop = display.screen.frame.maxY - display.screen.visibleFrame.maxY + 54
            let anchor: CGPoint
            switch guide.kind {
            case .vertical: anchor = CGPoint(x: x + 8, y: safeTop)
            case .horizontal: anchor = CGPoint(x: 12, y: y + 8)
            case .segment: anchor = CGPoint(x: (x + guide.end.x) / 2 + 8, y: (y + guide.end.y) / 2 + 8)
            }
            drawBadge(model.valueLabel(for: guide), at: anchor)
        }
    }

    private func drawBadge(_ text: String, at point: CGPoint, maximumWidth: Double = 260) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let width = min(size.width + 16, maximumWidth)
        let rect = NSRect(x: max(4, min(point.x, bounds.width - width - 4)),
                          y: max(4, min(point.y, bounds.height - 28)), width: width, height: 24)
        paintBadge(text, in: rect)
    }

    private func paintBadge(_ text: String, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white
        ]
        NSColor(white: 0.10, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        (text as NSString).draw(in: rect.insetBy(dx: 8, dy: 5), withAttributes: attributes)
    }

    func distanceAnnotations() -> [GapAnnotation] {
        guard model.showDistances && model.isVisible else { return [] }
        let gaps = GuideGap.adjacent(in: model.drawableGuides, displayID: display.id)
        let anchor = model.distanceAnchor(for: display)
        let safeTop = display.screen.frame.maxY - display.screen.visibleFrame.maxY + 48
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)]
        var annotations: [GapAnnotation] = []
        for kind in [GuideKind.horizontal, .vertical] {
            let group = gaps.filter { $0.kind == kind }
            guard !group.isEmpty else { continue }
            let texts: [String] = group.map { "\(kind == .horizontal ? "↕" : "↔") \(model.distanceLabel(for: $0, scale: display.geometry.scale))" }
            let widths: [Double] = texts.map { Double(ceil(($0 as NSString).size(withAttributes: attributes).width)) + 16 }
            let lengths: [Double] = kind == .horizontal ? group.map { _ in 24.0 } : widths
            let placements = GapLabelLayout.arrange(centers: group.map(\.midpoint), lengths: lengths,
                                                    lower: kind == .horizontal ? safeTop : 12,
                                                    upper: kind == .horizontal ? bounds.height - 12 : bounds.width - 12)
            let lanes = (placements.map(\.lane).max() ?? 0) + 1
            let laneWidth = (widths.max() ?? 70) + 10
            let bracketX = min(max(anchor.x, 16), max(16, bounds.width - Double(lanes) * laneWidth - 20))
            let bracketY = min(max(anchor.y, safeTop), max(safeTop, bounds.height - Double(lanes) * 32 - 20))
            for i in group.indices {
                let gap = group[i], placement = placements[i]
                if kind == .horizontal {
                    annotations.append(GapAnnotation(gap: gap, start: CGPoint(x: bracketX, y: gap.lower), end: CGPoint(x: bracketX, y: gap.upper),
                                         badge: CGRect(x: bracketX + 12 + Double(placement.lane) * laneWidth,
                                                       y: placement.center - 12, width: widths[i], height: 24), text: texts[i]))
                    continue
                }
                annotations.append(GapAnnotation(gap: gap, start: CGPoint(x: gap.lower, y: bracketY), end: CGPoint(x: gap.upper, y: bracketY),
                                     badge: CGRect(x: placement.center - widths[i] / 2,
                                                   y: bracketY + 12 + Double(placement.lane) * 32, width: widths[i], height: 24), text: texts[i]))
            }
        }
        return annotations
    }

    private func drawDistance(_ annotation: GapAnnotation) {
        let path = NSBezierPath()
        path.move(to: annotation.start); path.line(to: annotation.end)
        let horizontalGuides = annotation.gap.kind == .horizontal
        for point in [annotation.start, annotation.end] {
            path.move(to: CGPoint(x: point.x - (horizontalGuides ? 4 : 0), y: point.y - (horizontalGuides ? 0 : 4)))
            path.line(to: CGPoint(x: point.x + (horizontalGuides ? 4 : 0), y: point.y + (horizontalGuides ? 0 : 4)))
        }
        let middle = CGPoint(x: (annotation.start.x + annotation.end.x) / 2, y: (annotation.start.y + annotation.end.y) / 2)
        // A leader keeps tightly spaced labels connected to the precise gap they measure.
        path.move(to: middle)
        if horizontalGuides {
            path.line(to: CGPoint(x: annotation.badge.minX - 5, y: middle.y))
            path.line(to: CGPoint(x: annotation.badge.minX - 5, y: annotation.badge.midY))
            path.line(to: CGPoint(x: annotation.badge.minX, y: annotation.badge.midY))
        } else {
            path.line(to: CGPoint(x: middle.x, y: annotation.badge.minY - 5))
            path.line(to: CGPoint(x: annotation.badge.midX, y: annotation.badge.minY - 5))
            path.line(to: CGPoint(x: annotation.badge.midX, y: annotation.badge.minY))
        }
        NSColor.black.withAlphaComponent(0.65).setStroke(); path.lineWidth = 2.5; path.stroke()
        NSColor.white.withAlphaComponent(0.95).setStroke(); path.lineWidth = 0.75; path.stroke()
        paintBadge(annotation.text, in: annotation.badge)
    }

    private func distanceHit(at position: Position) -> GapAnnotation? {
        distanceAnnotations().reversed().first { $0.badge.contains(CGPoint(x: position.x, y: position.y)) }
    }

    private func handles(for guide: Guide) -> [Position] {
        switch guide.kind {
        case .vertical: return [Position(guide.start.x, bounds.midY)]
        case .horizontal: return [Position(bounds.midX, guide.start.y)]
        case .segment: return [guide.start, guide.end]
        }
    }

    private func position(_ event: NSEvent) -> Position {
        let p = convert(event.locationInWindow, from: nil)
        let unit: MeasurementUnit = event.modifierFlags.contains(.option) ? .pixels : model.unit
        return display.geometry.snapped(Position(p.x, p.y), unit: unit)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseMoved(with event: NSEvent) {
        hover = position(event)
        model.loupeFocus = nil
        if model.tool != nil || model.isPickingWindow { NSCursor.crosshair.set() }
        else if distanceHit(at: hover!) != nil { NSCursor.openHand.set() }
        else if let guide = nearest(to: hover!) {
            switch guide.kind {
            case .vertical: NSCursor.resizeLeftRight.set()
            case .horizontal: NSCursor.resizeUpDown.set()
            case .segment: NSCursor.openHand.set()
            }
        } else { NSCursor.arrow.set() }
        if model.tool != nil { needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) { hover = nil; needsDisplay = true; NSCursor.arrow.set() }

    private func nearest(to point: Position) -> Guide? {
        // Prefer the selected guide when several lines overlap.
        if let selected = model.selected, !model.hiddenGuideIDs.contains(selected.id), selected.displayID == display.id, selected.distance(to: point) <= 6 { return selected }
        return model.drawableGuides.reversed().filter { $0.displayID == display.id && $0.distance(to: point) <= 6 }
            .min { $0.distance(to: point) < $1.distance(to: point) }
    }

    override func mouseDown(with event: NSEvent) {
        guard model.isEditing else { return }
        window?.makeKey(); window?.makeFirstResponder(self)
        let p = position(event)
        if model.isPickingWindow { model.pickWindow?(display.global(p)); return }
        origin = p; movingEndpoint = nil
        model.loupeFocus = nil
        model.activeDisplayID = display.id
        if model.tool == nil, let annotation = distanceHit(at: p) {
            draggingDistances = annotation.gap.kind
            var anchor = model.distanceAnchor(for: display)
            if annotation.gap.kind == .horizontal { anchor.x = annotation.start.x }
            else { anchor.y = annotation.start.y }
            distanceDragAnchor = anchor; originalGuide = nil; NSCursor.closedHand.set()
            return
        }
        if let tool = model.tool {
            model.beginTransaction()
            newGuideID = model.add(kind: tool, at: p, displayID: display.id)
            originalGuide = model.selected
        } else if let hit = nearest(to: p) {
            model.select(hit.id, extending: event.modifierFlags.contains(.shift), preserving: true)
            guard model.selectedIDs.contains(hit.id) else { origin = nil; return }
            model.beginTransaction(); originalGuide = hit; originalSelection = model.selectedGuides
            if hit.kind == .segment && originalSelection.count == 1 {
                if hypot(p.x - hit.start.x, p.y - hit.start.y) <= 8 { movingEndpoint = 0 }
                else if hypot(p.x - hit.end.x, p.y - hit.end.y) <= 8 { movingEndpoint = 1 }
            }
        } else {
            marqueeBase = event.modifierFlags.contains(.shift) ? model.selectedIDs : []
            model.select(ids: marqueeBase!, displayID: display.id); originalGuide = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard model.isEditing, let origin else { return }
        let p = position(event)
        model.loupeFocus = nil
        if let marqueeBase {
            let rect = CGRect(x: min(origin.x, p.x), y: min(origin.y, p.y), width: abs(p.x - origin.x), height: abs(p.y - origin.y))
            if rect.width > 3 || rect.height > 3 {
                marquee = rect
                let hits = model.drawableGuides.filter { $0.displayID == display.id && GuideSelection.intersects($0, rect: rect) }
                model.select(ids: marqueeBase.union(hits.map(\.id)), displayID: display.id)
                needsDisplay = true
            }
            return
        }
        if let draggingDistances, var anchor = distanceDragAnchor, model.showDistances {
            if draggingDistances == .horizontal { anchor.x += p.x - origin.x }
            else { anchor.y += p.y - origin.y }
            model.distanceAnchors[display.id] = display.geometry.clamped(anchor)
            return
        }
        guard let originalGuide else { return }
        if newGuideID == nil && movingEndpoint == nil {
            model.moveSelection(from: originalSelection, dx: p.x - origin.x, dy: p.y - origin.y, display: display)
            return
        }
        model.changeSelected { guide in
            guide = originalGuide
            if newGuideID != nil {
                if guide.kind == .segment {
                    let end = event.modifierFlags.contains(.shift) ? Guide.constrainedEndpoint(from: origin, to: p) : p
                    guide.end = display.geometry.snapped(end, unit: event.modifierFlags.contains(.option) ? .pixels : model.unit)
                } else { guide.start = p; guide.end = p }
            } else if let endpoint = movingEndpoint {
                let anchor = endpoint == 0 ? guide.end : guide.start
                let end = event.modifierFlags.contains(.shift) ? Guide.constrainedEndpoint(from: anchor, to: p) : p
                let clamped = display.geometry.snapped(end, unit: model.unit)
                if endpoint == 0 { guide.start = clamped } else { guide.end = clamped }
            } else { guide.translate(dx: p.x - origin.x, dy: p.y - origin.y, in: display.geometry) }
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let id = newGuideID {
            if let guide = model.selected, guide.kind == .segment, guide.length < 1 / display.geometry.scale {
                model.guides.removeAll { $0.id == id }; model.selectedID = nil
            }
            model.tool = nil
        }
        model.commitTransaction(); resetGesture(); NSCursor.arrow.set(); needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if !handleKey(event, model: model) { super.keyDown(with: event) }
    }
}

@MainActor func handleKey(_ event: NSEvent, model: RullerModel) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags.contains(.command) {
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z": flags.contains(.shift) ? model.redo() : model.undo(); return true
        case "d": model.duplicate(); return true
        case "a": if model.isEditing { model.selectAll(); return true }; return false
        default: return false
        }
    }
    if event.keyCode == 53 {
        if model.isPickingWindow { model.isPickingWindow = false } else { model.setEditing(false) }
        return true
    }
    guard model.isEditing else { return false }
    let large = flags.contains(.shift), fine = flags.contains(.option)
    switch event.keyCode {
    case 123: model.nudge(dx: -1, dy: 0, fine: fine, large: large)
    case 124: model.nudge(dx: 1, dy: 0, fine: fine, large: large)
    case 125: model.nudge(dx: 0, dy: 1, fine: fine, large: large)
    case 126: model.nudge(dx: 0, dy: -1, fine: fine, large: large)
    case 51, 117: model.deleteSelected()
    default:
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "v": model.arm(.vertical)
        case "h": model.arm(.horizontal)
        case "l": model.arm(.segment)
        default: return false
        }
    }
    return true
}
