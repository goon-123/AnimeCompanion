import XCTest
@testable import AnimeCore

final class ExploreLayoutTests: XCTestCase {
    func testWidgetCanSitBetweenCatalogRowsAndKeepIndependentOptionsAfterRelaunch() {
        var home = HomePreferences()
        home.setSize(.expanded, for: .watching)
        home.setLayout(.compact, for: .news)
        let homeSaved = home.saved
        var explore = ExplorePreferences(surface: .anime)
        explore.addWidget(.watching, copying: home)
        explore.addWidget(.news, copying: home)
        let position = explore.order.firstIndex(of: .widget(.watching))!
        explore.move(fromOffsets: IndexSet(integer: position), toOffset: 2)
        explore.setVisible(.catalog(.trending), false)
        explore.widgetOptions.setSize(.compact, for: .watching)
        let restored = ExplorePreferences(surface: .anime, saved: explore.saved)
        XCTAssertEqual(restored.order[2], .widget(.watching))
        XCTAssertEqual(restored.widgetOptions.size(for: .watching), .compact)
        XCTAssertEqual(restored.widgetOptions.layout(for: .news), .compact)
        XCTAssertFalse(restored.visible.contains(.catalog(.trending)))
        XCTAssertEqual(restored, explore)
        XCTAssertEqual(home.saved, homeSaved)
        XCTAssertFalse(ExplorePreferences(surface: .discovery).hasWidgets)
        XCTAssertEqual(Set(ExploreSurface.allCases.map(\.storageKey)).count, 4)
        XCTAssertFalse(ExploreSurface.allCases.map(\.storageKey).contains(HomePreferences.storageKey))
    }
    func testHideAllRetainsAddedWidgetsAndUnhidingDoesNotMoveThemOrOverwriteOptions() {
        var explore = ExplorePreferences(surface: .discovery)
        explore.addWidget(.weekly, copying: HomePreferences())
        explore.move(.widget(.weekly), by: -1)
        let order = explore.order
        explore.setAllVisible(false)
        var restored = ExplorePreferences(surface: .discovery, saved: explore.saved)
        XCTAssertTrue(restored.visible.isEmpty)
        restored.addWidget(.weekly, copying: HomePreferences())
        XCTAssertEqual(restored.order, order)
        XCTAssertEqual(restored.visible, [.widget(.weekly)])
        restored.setAllVisible(true)
        XCTAssertEqual(restored.visible, order)
        XCTAssertFalse(restored.order.contains(.widget(.community)))
    }
    func testCorruptDuplicateForeignAndFutureRowsDoNotDisplaceValidRows() {
        let saved = #"{"order":["catalog.topAnime","widget.weekly","catalog.topAnime","catalog.genres","catalog.unknown","widget.unknown"],"hidden":["widget.weekly","widget.unknown","catalog.genres"]}"#
        let restored = ExplorePreferences(surface: .anime, saved: saved)
        XCTAssertEqual(Array(restored.order.prefix(2)), [.catalog(.topAnime), .widget(.weekly)])
        XCTAssertEqual(restored.hidden, [.widget(.weekly)])
        XCTAssertEqual(restored.order.count, ExploreSurface.anime.catalog.count + 1)
        for value in ["", "{broken", String(repeating: "a", count: 65_537)] {
            XCTAssertEqual(ExplorePreferences(surface: .anime, saved: value).visible, ExploreSurface.anime.catalog.map(ExploreRow.catalog))
        }
    }
    func testMultipleMovesUseOriginalIndicesAndHiddenNeighborsAreSkipped() {
        var value = ExplorePreferences(surface: .anime)
        let original = value.order
        value.move(fromOffsets: IndexSet([0, 2]), toOffset: original.count)
        XCTAssertEqual(Array(value.order.suffix(2)), [original[0], original[2]])
        value.setVisible(value.order[1], false)
        let nextVisible = value.visible[1]
        value.move(nextVisible, by: -1)
        XCTAssertEqual(value.visible.first, nextVisible)
        let before = value
        value.move(fromOffsets: IndexSet(integer: 999), toOffset: 0)
        value.move(fromOffsets: IndexSet(integer: 0), toOffset: -1)
        XCTAssertEqual(value, before)
    }
    func testHomeShortcutChoicesAreCopiedAndThenStayIndependent() {
        var home = HomePreferences()
        home.setShortcut(.community, at: 0); home.setShortcut(nil, at: 1)
        var explore = ExplorePreferences(surface: .grid)
        explore.addWidget(.featureLinks, copying: home)
        XCTAssertEqual(explore.widgetOptions.shortcuts, home.shortcuts)
        explore.widgetOptions.setShortcut(.library, at: 0)
        explore.setVisible(.widget(.featureLinks), false)
        explore.addWidget(.featureLinks, copying: home)
        XCTAssertEqual(explore.widgetOptions.shortcuts[0], .library)
        XCTAssertEqual(home.shortcuts[0], .community)
    }
}
