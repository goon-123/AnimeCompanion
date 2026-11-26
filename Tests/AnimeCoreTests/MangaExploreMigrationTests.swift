import XCTest
@testable import AnimeCore

final class MangaExploreMigrationTests: XCTestCase {
    func testVisibleMangaMovesIntoExploreWithoutDroppingItsEntryPoint() {
        let old = AppTabPreferences(saved: #"{"order":["home","manga","library","explore"],"hidden":["explore"]}"#)
        XCTAssertEqual(old.visible, [.home, .explore, .library])
        XCTAssertEqual(old.selection(for: .manga), .explore)
        XCTAssertFalse(old.saved.contains("manga"))
        XCTAssertEqual(AppTabPreferences(saved: old.saved), old)
    }
    func testRetiredMangaCannotBeReaddedAndExistingHiddenExploreStaysHidden() {
        var old = AppTabPreferences(saved: #"{"order":["home","library","explore","manga"],"hidden":["explore","manga"]}"#)
        old.setVisible(.manga, true)
        XCTAssertEqual(old.visible, [.home, .library])
        XCTAssertEqual(old.selection(for: .manga), .home)
        XCTAssertFalse(old.order.contains(.manga))
    }
    func testReadingTilesUpgradeAfterBannerAndRetainSavedVisibilityAndOrder() {
        let saved = #"{"version":1,"order":["catalog.genres","catalog.spotlight","catalog.formats"],"hidden":["catalog.spotlight"]}"#
        var layout = ExplorePreferences(surface: .reading, saved: saved)
        XCTAssertEqual(Array(layout.order.prefix(4)), [.catalog(.genres), .catalog(.spotlight), .catalog(.yourReading), .catalog(.formats)])
        XCTAssertTrue(layout.hidden.contains(.catalog(.spotlight)))
        XCTAssertTrue(layout.visible.contains(.catalog(.yourReading)))
        layout.setVisible(.catalog(.yourReading), false)
        let reopened = ExplorePreferences(surface: .reading, saved: layout.saved)
        XCTAssertEqual(reopened, layout)
        XCTAssertFalse(reopened.visible.contains(.catalog(.yourReading)))
    }
    func testReadingAccessRemainsAvailableInAlternateExploreDesignsOnlyOnce() {
        for surface in [ExploreSurface.reading, .discovery, .grid] {
            let layout = ExplorePreferences(surface: surface)
            XCTAssertEqual(layout.visible.filter { $0 == .catalog(.yourReading) }.count, 1)
        }
        XCTAssertFalse(ExplorePreferences(surface: .anime).order.contains(.catalog(.yourReading)))
    }
}
