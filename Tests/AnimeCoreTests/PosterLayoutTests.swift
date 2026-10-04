import XCTest
@testable import AnimeCore

final class PosterLayoutTests: XCTestCase {
    func testChosenDensityFitsPhoneAndBothIPadOrientations() {
        XCTAssertEqual(PosterLayout.columns(requested: 4, availableWidth: 390), 4)
        XCTAssertEqual(PosterLayout.columns(requested: 8, availableWidth: 810), 8)
        XCTAssertEqual(PosterLayout.columns(requested: 8, availableWidth: 1186), 8)
        XCTAssertEqual(PosterLayout.columns(requested: 2, availableWidth: 1186), 2)
    }
    func testNarrowWindowsAndAccessibilityTextConstrainWithoutChangingPreference() {
        let saved = 8
        XCTAssertEqual(PosterLayout.columns(requested: saved, availableWidth: 296), 3)
        XCTAssertEqual(PosterLayout.columns(requested: saved, availableWidth: 296, minimumWidth: 160), 1)
        XCTAssertEqual(PosterLayout.columns(requested: saved, availableWidth: 1186), 8)
        XCTAssertEqual(saved, 8)
    }
    func testListPosterGrowthLeavesRoomForMetadata() {
        XCTAssertEqual(PosterLayout.listWidth(preferred: 220, availableWidth: 810), 220)
        XCTAssertEqual(PosterLayout.listWidth(preferred: 220, availableWidth: 296), 112.48, accuracy: 0.01)
        XCTAssertLessThan(PosterLayout.listWidth(preferred: 240, availableWidth: 320), 320 / 2)
    }
    func testInvalidAndExtremeStoredValuesHaveSafeBounds() {
        XCTAssertEqual(PosterLayout.columns(requested: 0, availableWidth: 810), 1)
        XCTAssertEqual(PosterLayout.columns(requested: Int.max, availableWidth: 1186), 8)
        XCTAssertEqual(PosterLayout.columns(requested: 4, availableWidth: -.infinity), 1)
        XCTAssertEqual(PosterLayout.columns(requested: 4, availableWidth: 0), 1)
        XCTAssertEqual(PosterLayout.listWidth(preferred: .nan, availableWidth: 810), 100)
        XCTAssertEqual(PosterLayout.listWidth(preferred: 10000, availableWidth: 810), 240)
    }
}
