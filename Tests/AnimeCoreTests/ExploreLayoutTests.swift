import XCTest
@testable import AnimeCore

final class ExploreLayoutTests: XCTestCase {
    func testPlainAndRankedTrendingKeepIndependentVisibilityOnExploreAndHome() {
        for surface in [ExploreSurface.anime, .discovery, .grid] {
            var value = ExplorePreferences(surface: surface)
            XCTAssertTrue(value.visible.contains(.catalog(.trending)))
            XCTAssertEqual(value.visible.contains(.catalog(.topTen)), surface != .anime)
            value.setVisible(.catalog(.topTen), true)
            value.setVisible(.catalog(.topTen), false)
            let restored = ExplorePreferences(surface: surface, saved: value.saved)
            XCTAssertTrue(restored.visible.contains(.catalog(.trending)))
            XCTAssertFalse(restored.visible.contains(.catalog(.topTen)))
        }
        var home = HomePreferences()
        XCTAssertFalse(home.visible.contains(.trendingAnime))
        XCTAssertFalse(home.visible.contains(.trendingAnimePlain))
        home.setVisible(.trendingAnimePlain, true)
        XCTAssertTrue(HomePreferences(saved: home.saved).visible.contains(.trendingAnimePlain))
        XCTAssertFalse(HomePreferences(saved: home.saved).visible.contains(.trendingAnime))
    }

    func testCollectionSizesPersistIndependentlyAcrossRowsAndExploreDesigns() {
        var value = ExplorePreferences(surface: .anime)
        XCTAssertEqual(value.cardSize(for: .studios), .small)
        XCTAssertEqual(value.cardSize(for: .animeGenres), .small)
        value.setCardSize(.large, for: .studios)
        value.setCardSize(.medium, for: .animeGenres)
        value.setCardSize(.large, for: .trending)
        let restored = ExplorePreferences(surface: .anime, saved: value.saved)
        XCTAssertEqual(restored.cardSize(for: .studios), .large)
        XCTAssertEqual(restored.cardSize(for: .animeGenres), .medium)
        XCTAssertEqual(restored.cardSize(for: .trending), .small)
        XCTAssertEqual(ExplorePreferences(surface: .discovery).cardSize(for: .studios), .small)
        let malformed = #"{"order":[],"hidden":[],"cardSizes":{"studios":"future","animeGenres":"large","trending":"large"}}"#
        let bounded = ExplorePreferences(surface: .anime, saved: malformed)
        XCTAssertEqual(bounded.cardSize(for: .studios), .small)
        XCTAssertEqual(bounded.cardSize(for: .animeGenres), .large)
        XCTAssertEqual(bounded.cardSize(for: .trending), .small)
    }

    func testOldRankedTrendingChoiceMigratesOnceWithoutMovingSavedRows() {
        let legacy = #"{"order":["catalog.topAnime","catalog.trending","catalog.seasonal"],"hidden":["catalog.trending"]}"#
        var value = ExplorePreferences(surface: .anime, saved: legacy)
        XCTAssertEqual(Array(value.order.prefix(4)), [.catalog(.topAnime), .catalog(.trending), .catalog(.topTen), .catalog(.seasonal)])
        XCTAssertFalse(value.visible.contains(.catalog(.topTen)))
        value.setVisible(.catalog(.trending), true)
        let restored = ExplorePreferences(surface: .anime, saved: value.saved)
        XCTAssertEqual(restored.order, value.order)
        XCTAssertFalse(restored.visible.contains(.catalog(.topTen)))
        XCTAssertTrue(restored.visible.contains(.catalog(.trending)))
        XCTAssertEqual(restored.order.filter { $0 == .catalog(.topTen) }.count, 1)
    }

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
            XCTAssertEqual(ExplorePreferences(surface: .anime, saved: value).visible, ExploreSurface.anime.defaultRows)
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
