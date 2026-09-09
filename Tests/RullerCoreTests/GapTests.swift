import XCTest
@testable import RullerCore

final class GapTests: XCTestCase {
    private func guide(_ kind: GuideKind, _ coordinate: Double, display: String = "main") -> Guide {
        Guide(displayID: display, kind: kind, start: Position(coordinate, coordinate))
    }

    func testGapsFollowSpatialOrderAndUpdateWhenLinesCross() {
        var guides = [guide(.horizontal, 140), guide(.horizontal, 100), guide(.horizontal, 122)]
        var gaps = GuideGap.adjacent(in: guides, displayID: "main")
        XCTAssertEqual(gaps.map(\.distance), [22, 18])
        XCTAssertEqual(gaps[0].firstID, guides[1].id)
        guides[2].start.y = 150
        gaps = GuideGap.adjacent(in: guides, displayID: "main")
        XCTAssertEqual(gaps.map(\.distance), [40, 10])
        XCTAssertEqual(gaps[1].secondID, guides[2].id)
    }

    func testAxesAndDisplaysAreNeverMixed() {
        let guides = [guide(.horizontal, 20), guide(.vertical, 10), guide(.horizontal, 33), guide(.vertical, 60),
                      guide(.horizontal, 25, display: "other"), guide(.segment, 23)]
        let gaps = GuideGap.adjacent(in: guides, displayID: "main")
        XCTAssertEqual(gaps.map(\.kind), [.horizontal, .vertical])
        XCTAssertEqual(gaps.map(\.distance), [13, 50])
        XCTAssertTrue(GuideGap.adjacent(in: guides, displayID: "other").isEmpty)
    }

    func testRetinaSubpixelAndZeroGapsIgnoreStrokeThickness() {
        var guides = [guide(.vertical, 42), guide(.vertical, 42.5), guide(.vertical, 42.5)]
        guides[0].widthPixels = 8
        let gaps = GuideGap.adjacent(in: guides, displayID: "main")
        XCTAssertEqual(gaps.map(\.distance), [0.5, 0])
        XCTAssertEqual(gaps[0].value(unit: .pixels, scale: 2), 1)
        XCTAssertEqual(gaps[0].value(unit: .points, scale: 2), 0.5)
        XCTAssertEqual(gaps[1].firstID, guides[1].id)
    }

    func testDeletingMiddleGuideProducesCombinedGap() {
        let guides = [guide(.horizontal, 12), guide(.horizontal, 24), guide(.horizontal, 48)]
        XCTAssertEqual(GuideGap.adjacent(in: [guides[0], guides[2]], displayID: "main").map(\.distance), [36])
        XCTAssertTrue(GuideGap.adjacent(in: [], displayID: "main").isEmpty)
    }

    func testTightlySpacedLabelsRemainSeparateAndOnscreen() {
        let layout = GapLabelLayout.arrange(centers: [90, 91, 92], lengths: [24, 24, 24], lower: 10, upper: 110)
        XCTAssertTrue(layout.allSatisfy { $0.lane == 0 && $0.center - 12 >= 10 && $0.center + 12 <= 110 })
        XCTAssertGreaterThanOrEqual(layout[1].center - layout[0].center, 30)
        XCTAssertGreaterThanOrEqual(layout[2].center - layout[1].center, 30)
    }

    func testDenseMeasurementsUseAdditionalLanes() {
        let layout = GapLabelLayout.arrange(centers: [11, 12, 13, 14], lengths: [50, 50, 50, 50], lower: 0, upper: 120)
        XCTAssertEqual(layout.map(\.lane), [0, 0, 1, 1])
        XCTAssertTrue(layout.allSatisfy { $0.center - 25 >= 0 && $0.center + 25 <= 120 })
    }

    func testOldSavedGuidesLoadWithoutNewMeasurementFields() throws {
        let oldJSON = """
        {"version":1,"guides":[],"unit":"points","showLabels":false,"defaultColor":"coral","defaultOpacity":0.85,"defaultWidth":1}
        """
        let saved = try JSONDecoder().decode(SavedState.self, from: Data(oldJSON.utf8))
        XCTAssertNil(saved.showDistances)
        XCTAssertNil(saved.distanceAnchors)
        XCTAssertFalse(saved.showLabels)
    }

    func testDistancePreferencesRoundTrip() throws {
        let saved = SavedState(guides: [], unit: .pixels, showLabels: false, defaultColor: .coral, defaultOpacity: 1,
                               defaultWidth: 1, showDistances: false, distanceAnchors: ["main": Position(700, 220)])
        let restored = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(restored.showDistances, false)
        XCTAssertEqual(restored.distanceAnchors?["main"], Position(700, 220))
    }
}
