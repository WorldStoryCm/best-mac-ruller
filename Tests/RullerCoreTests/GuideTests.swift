import XCTest
@testable import RullerCore

final class GuideTests: XCTestCase {
    let retina = DisplayGeometry(width: 1000, height: 800, scale: 2)

    func testRetinaPixelSnapping() {
        XCTAssertEqual(retina.snapped(Position(12.26, 30.76), unit: .pixels), Position(12.5, 31))
        XCTAssertEqual(retina.snapped(Position(12.26, 30.76), unit: .points), Position(12, 31))
        XCTAssertEqual(MeasurementUnit.pixels.step(scale: 2), 0.5)
        XCTAssertEqual(MeasurementUnit.points.step(scale: 2), 1)
    }
    func testCoordinatesCannotFallBeyondLastPhysicalPixel() {
        XCTAssertEqual(retina.snapped(Position(1000, 800), unit: .points), Position(999.5, 799.5))
        XCTAssertEqual(retina.clamped(Position(-100, -20)), Position(0, 0))
    }
    func testAxisGuidesOnlyMoveAlongTheirAxis() {
        var vertical = Guide(displayID: "a", kind: .vertical, start: Position(10, 20))
        vertical.translate(dx: 1, dy: 50, in: retina)
        XCTAssertEqual(vertical.start, Position(11, 20))
        var horizontal = Guide(displayID: "a", kind: .horizontal, start: Position(10, 20))
        horizontal.translate(dx: 50, dy: -1, in: retina)
        XCTAssertEqual(horizontal.start, Position(10, 19))
    }
    func testSegmentLengthPreservedAtBothScreenEdges() {
        var line = Guide(displayID: "a", kind: .segment, start: Position(900, 700), end: Position(980, 760))
        let length = line.length
        line.translate(dx: 50, dy: 60, in: retina)
        XCTAssertEqual(line.end, Position(999.5, 799.5))
        XCTAssertEqual(line.length, length, accuracy: 0.00001)
        line.translate(dx: -2000, dy: -2000, in: retina)
        XCTAssertEqual(line.start, Position(0, 0))
        XCTAssertEqual(line.length, length, accuracy: 0.00001)
    }
    func testReversedSegmentTranslation() {
        var line = Guide(displayID: "a", kind: .segment, start: Position(400, 400), end: Position(20, 30))
        line.translate(dx: -100, dy: -100, in: retina)
        XCTAssertEqual(line.end, Position(0, 0))
        XCTAssertEqual(line.start, Position(380, 370))
    }
    func testHitTestingUsesSegmentAndNotInfiniteLine() {
        let line = Guide(displayID: "a", kind: .segment, start: Position(10, 10), end: Position(30, 10))
        XCTAssertEqual(line.distance(to: Position(20, 13)), 3)
        XCTAssertEqual(line.distance(to: Position(40, 10)), 10)
        let vertical = Guide(displayID: "a", kind: .vertical, start: Position(17, 0))
        XCTAssertEqual(vertical.distance(to: Position(19, 600)), 2)
    }
    func testZeroLengthSegmentIsHittableWithoutNaN() {
        let line = Guide(displayID: "a", kind: .segment, start: Position(3, 4))
        XCTAssertEqual(line.distance(to: Position(0, 0)), 5)
    }
    func testShiftAngleConstraint() {
        let end = Guide.constrainedEndpoint(from: Position(0, 0), to: Position(100, 8))
        XCTAssertEqual(end.y, 0, accuracy: 0.00001)
        let diagonal = Guide.constrainedEndpoint(from: Position(0, 0), to: Position(80, 90))
        XCTAssertEqual(diagonal.x, diagonal.y, accuracy: 0.00001)
    }
    func testSaveRoundTripPreservesExactPositionsAndStyle() throws {
        let guides = [Guide(displayID: "display-uuid", kind: .segment, start: Position(0.5, 14), end: Position(90.5, 42), color: .cyan, opacity: 0.3, widthPixels: 2)]
        let state = SavedState(guides: guides, unit: .pixels, showLabels: false, defaultColor: .lime, defaultOpacity: 0.8, defaultWidth: 1)
        let decoded = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.guides, guides)
        XCTAssertEqual(decoded.unit, .pixels)
        XCTAssertFalse(decoded.showLabels)
        XCTAssertEqual(decoded.version, 1)
    }
}
