import XCTest
@testable import AnimeCore

final class TabletLayoutTests: XCTestCase {
    func testFullWidthIsTheDefaultWithoutOptingExistingInstallationsIntoSplitView() {
        XCTAssertEqual(TabletLayout(preference: nil), .fullWidth)
        XCTAssertEqual(TabletLayout(preference: "old-or-invalid"), .fullWidth)
        for layout in TabletLayout.allCases { XCTAssertEqual(TabletLayout(preference: layout.rawValue), layout) }
    }
    func testSplitBrowsingGetsMostOfTheWindowWithSensibleBounds() {
        XCTAssertEqual(TabletLayout.browseWidth(windowWidth: 1194), 716.4, accuracy: 0.01)
        XCTAssertEqual(TabletLayout.browseWidth(windowWidth: 1366), 819.6, accuracy: 0.01)
        XCTAssertEqual(TabletLayout.browseWidth(windowWidth: 834), 500.4, accuracy: 0.01)
        XCTAssertEqual(TabletLayout.browseWidth(windowWidth: 320), 480)
        XCTAssertEqual(TabletLayout.browseWidth(windowWidth: 10000), 820)
        for invalid in [Double.nan, .infinity, -.infinity, 0, -100] {
            XCTAssertEqual(TabletLayout.browseWidth(windowWidth: invalid), 560)
        }
    }
    func testSplitPosterDoesNotStretchThroughTheEntireTallWindow() {
        XCTAssertEqual(PosterLayout.featuredHeight(preferred: 680, viewportHeight: 1300, fillScreen: true, splitColumnWidth: 480), 720)
        XCTAssertEqual(PosterLayout.featuredHeight(preferred: 680, viewportHeight: 1300, fillScreen: false, splitColumnWidth: 400), 600)
        XCTAssertEqual(PosterLayout.featuredHeight(preferred: 680, viewportHeight: 1300, fillScreen: true), 1100)
        XCTAssertEqual(PosterLayout.featuredHeight(preferred: 680, viewportHeight: 800, fillScreen: true, splitColumnWidth: .nan), 752)
    }
    func testSplitDensityLeavesRoomForTitlesDubBadgesAndPosterActions() {
        XCTAssertEqual(PosterLayout.columns(requested: 4, availableWidth: 448, minimumWidth: 160), 2)
        XCTAssertEqual(PosterLayout.columns(requested: 4, availableWidth: 680, minimumWidth: 160), 4)
        XCTAssertEqual(PosterLayout.columns(requested: 4, availableWidth: 800), 4)
    }
}
