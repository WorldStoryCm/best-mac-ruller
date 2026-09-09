import XCTest
import CoreGraphics
@testable import RullerCore

final class SelectionTests: XCTestCase {
    let display = DisplayGeometry(width: 100, height: 80, scale: 2)

    func testGroupClampsAsOneWithoutChangingDistances() {
        let a = Guide(displayID: "a", kind: .vertical, start: Position(10, 20))
        let b = Guide(displayID: "a", kind: .vertical, start: Position(90, 20))
        let right = GuideSelection.translated([a, b], dx: 50, dy: 20, in: display)
        XCTAssertEqual(right[1].start.x, 99.5)
        XCTAssertEqual(right[1].start.x - right[0].start.x, 80)
        XCTAssertEqual(right[0].start.y, 20)
        let left = GuideSelection.translated([a, b], dx: -50, dy: 0, in: display)
        XCTAssertEqual(left[0].start.x, 0)
        XCTAssertEqual(left[1].start.x, 80)
    }

    func testMixedAxesAndReversedSegmentShareTranslation() {
        let v = Guide(displayID: "a", kind: .vertical, start: Position(20, 0))
        let h = Guide(displayID: "a", kind: .horizontal, start: Position(0, 30))
        let line = Guide(displayID: "a", kind: .segment, start: Position(90, 70), end: Position(80, 60))
        let moved = GuideSelection.translated([v, h, line], dx: 50, dy: 50, in: display)
        XCTAssertEqual(moved[0].start, Position(29.5, 0))
        XCTAssertEqual(moved[1].start, Position(0, 39.5))
        XCTAssertEqual(moved[2].start, Position(99.5, 79.5))
        XCTAssertEqual(moved[2].length, line.length, accuracy: 0.00001)
    }

    func testMarqueeUsesFiniteSegmentsAndCrossingLines() {
        let rect = CGRect(x: 10, y: 10, width: 20, height: 20)
        XCTAssertTrue(GuideSelection.intersects(Guide(displayID: "a", kind: .vertical, start: Position(10, 70)), rect: rect))
        XCTAssertFalse(GuideSelection.intersects(Guide(displayID: "a", kind: .vertical, start: Position(31, 20)), rect: rect))
        XCTAssertTrue(GuideSelection.intersects(Guide(displayID: "a", kind: .segment, start: Position(0, 20), end: Position(50, 20)), rect: rect))
        XCTAssertFalse(GuideSelection.intersects(Guide(displayID: "a", kind: .segment, start: Position(0, 0), end: Position(5, 5)), rect: rect))
        XCTAssertFalse(GuideSelection.intersects(Guide(displayID: "a", kind: .segment, start: Position(0, 31), end: Position(50, 31)), rect: rect))
        XCTAssertTrue(GuideSelection.intersects(Guide(displayID: "a", kind: .segment, start: Position(20, 20)), rect: rect))
    }

    func testSubpixelGroupMovementPreservesCoincidentGuides() {
        let guide = Guide(displayID: "a", kind: .horizontal, start: Position(0, 4))
        let moved = GuideSelection.translated([guide, guide], dx: 0, dy: 0.5, in: display)
        XCTAssertEqual(moved[0].start.y, 4.5)
        XCTAssertEqual(moved[0].start, moved[1].start)
        XCTAssertTrue(GuideSelection.translated([], dx: 5, dy: 5, in: display).isEmpty)
    }

    func testLoupeUsesBackingPixelAndClipsAtAllEdges() {
        let center = LoupeSample(point: Position(10.9, 20.75), display: display, radius: 2)
        XCTAssertEqual(center.pixelRect, CGRect(x: 19, y: 39, width: 5, height: 5))
        XCTAssertEqual(center.cursorPixel, Position(2, 2))
        let topLeft = LoupeSample(point: Position(-1, -1), display: display, radius: 2)
        XCTAssertEqual(topLeft.pixelRect, CGRect(x: 0, y: 0, width: 5, height: 5))
        XCTAssertEqual(topLeft.cursorPixel, Position(0, 0))
        let bottomRight = LoupeSample(point: Position(100, 80), display: display, radius: 2)
        XCTAssertEqual(bottomRight.pixelRect, CGRect(x: 195, y: 155, width: 5, height: 5))
        XCTAssertEqual(bottomRight.cursorPixel, Position(4, 4))
        let tiny = LoupeSample(point: Position(1, 1), display: DisplayGeometry(width: 2, height: 2, scale: 1), radius: 20)
        XCTAssertEqual(tiny.pixelRect, CGRect(x: 0, y: 0, width: 2, height: 2))
    }

    func testShortcutIdentityIgnoresKeyboardLayoutLabel() {
        let a = KeyBinding(keyCode: 35, modifiers: 3, label: "P")
        let b = KeyBinding(keyCode: 35, modifiers: 3, label: "З")
        XCTAssertTrue(a.hasSameKeys(as: b))
        XCTAssertTrue(a.isValid)
        XCTAssertFalse(KeyBinding(keyCode: 35, modifiers: 8, label: "P").isValid)
        XCTAssertFalse(KeyBinding(keyCode: 300, modifiers: 3, label: "P").isValid)
        XCTAssertEqual(a.display, "⌃⌥P")
        XCTAssertEqual(Set(ShortcutAction.allCases.map(\.defaultShortcut)).count, 4)
    }

    func testNewPreferencesRoundTrip() throws {
        let state = SavedState(guides: [], unit: .pixels, showLabels: true, defaultColor: .coral,
                               defaultOpacity: 0.5, defaultWidth: 1, highContrast: true,
                               shortcuts: ["controls": KeyBinding(keyCode: 0, modifiers: 7, label: "A")], loupeZoom: 16)
        let decoded = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.highContrast, true)
        XCTAssertEqual(decoded.loupeZoom, 16)
        XCTAssertEqual(decoded.shortcuts?["controls"]?.display, "⌃⌥⌘A")
    }
}
