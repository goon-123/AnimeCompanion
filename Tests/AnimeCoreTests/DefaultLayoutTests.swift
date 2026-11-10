import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AnimeCore

final class DefaultLayoutTests: XCTestCase {
    func testHomeShipsWithRequestedSectionsAndCatchUpShortcut() {
        let value = HomePreferences()
        XCTAssertEqual(value.visible, [.greeting, .search, .featureLinks, .welcome, .syncStatus,
            .weekly, .news, .community, .watching, .reading, .airing, .shortcuts])
        XCTAssertEqual(value.shortcuts, [.calendar, .catchUp, .news])
        XCTAssertEqual(HomePreferences(saved: value.saved), value)
    }
    func testOldDefaultShortcutsUpgradeWithoutReplacingCustomizedSlots() {
        let stock = HomePreferences(saved: #"{"version":4,"order":["greeting"],"hidden":[],"shortcuts":["calendar","airing","news"]}"#)
        XCTAssertEqual(stock.shortcuts, [.calendar, .catchUp, .news])
        let custom = HomePreferences(saved: #"{"version":4,"order":["reading","greeting"],"hidden":["search"],"shortcuts":["community","airing","news"]}"#)
        XCTAssertEqual(custom.shortcuts, [.community, .airing, .news])
        var explicitAiring = HomePreferences()
        explicitAiring.setShortcut(.airing, at: 1)
        XCTAssertEqual(HomePreferences(saved: explicitAiring.saved).shortcuts, [.calendar, .airing, .news])
    }
    func testRemovedCinematicSpotlightCannotReturnThroughOldSavedLayouts() {
        let old = HomePreferences(saved: #"{"version":4,"order":["greeting","cinematicSpotlight","search"],"hidden":["news"]}"#)
        XCTAssertFalse(old.saved.contains("cinematicSpotlight"))
        XCTAssertTrue(old.hidden.contains(.news))
        let explore = ExplorePreferences(surface: .anime, saved: #"{"order":["widget.cinematicSpotlight","catalog.trending"],"hidden":[]}"#)
        XCTAssertFalse(explore.saved.contains("cinematicSpotlight"))
    }
    func testAnimeShipsWithSevenRowsAndLargeNextSeasonCountdown() {
        let value = ExplorePreferences(surface: .anime)
        XCTAssertEqual(value.visible, [.catalog(.spotlight), .catalog(.trending), .catalog(.seasonal),
            .catalog(.previousSeason), .catalog(.topAnime), .widget(.seasonCountdown), .catalog(.upcoming)])
        XCTAssertEqual(value.widgetOptions.layout(for: .seasonCountdown), .banner)
        XCTAssertTrue(value.hidden.contains(.catalog(.topTen)))
        XCTAssertTrue(value.hidden.contains(.catalog(.studios)))
        XCTAssertTrue(value.hidden.contains(.catalog(.animeGenres)))
        XCTAssertEqual(ExplorePreferences(surface: .anime, saved: value.saved), value)
    }
    func testUntouchedAnimeStockLayoutUpgradesWhileCustomLayoutsStaySaved() {
        let ids = ExploreSurface.anime.catalog.map { ExploreRow.catalog($0).id }
        let data = try! JSONSerialization.data(withJSONObject: ["order": ids, "hidden": [String]()])
        let stock = ExplorePreferences(surface: .anime, saved: String(decoding: data, as: UTF8.self))
        XCTAssertEqual(stock.visible, ExploreSurface.anime.defaultRows)
        var custom = stock
        custom.setVisible(.catalog(.studios), true)
        custom.setVisible(.catalog(.trending), false)
        custom.setCardSize(.large, for: .studios)
        custom.move(.catalog(.topAnime), by: -1)
        let reopened = ExplorePreferences(surface: .anime, saved: custom.saved)
        XCTAssertEqual(reopened, custom)
        custom.setAllVisible(false)
        XCTAssertTrue(ExplorePreferences(surface: .anime, saved: custom.saved).visible.isEmpty)
    }
    func testCommunityExposesOnlyTwoAniListCategoriesAndOptionalWebsite() {
        XCTAssertEqual(CommunityFilter.feedCases, [.season, .myShows])
        XCTAssertEqual(CommunityFilter.general.feedFilter, .season)
        XCTAssertEqual(CommunityFilter.episodes.feedFilter, .season)
        XCTAssertEqual(CommunityDestination.allCases, [.aniList, .fapservice])
        XCTAssertEqual(CommunityDestination(preference: "reddit"), .aniList)
        XCTAssertEqual(CommunityDestination(preference: "myAnimeList"), .aniList)
        XCTAssertNil(CommunityDestination.aniList.websiteURL)
        XCTAssertEqual(CommunityDestination.fapservice.websiteURL?.absoluteString, "https://fapservice.com/")
    }
    func testCommunityCachesAreScopedByShowsAndAdultPreferences() {
        XCTAssertNotEqual(HomeCommunityClient.cacheKey(mediaIDs: [1], includeAdult: false), HomeCommunityClient.cacheKey(mediaIDs: [2], includeAdult: false))
        XCTAssertNotEqual(HomeCommunityClient.cacheKey(mediaIDs: [1], includeAdult: false), HomeCommunityClient.cacheKey(mediaIDs: [1], includeAdult: true))
        XCTAssertEqual(HomeCommunityClient.cacheKey(mediaIDs: [2, 1, 2], includeAdult: false), HomeCommunityClient.cacheKey(mediaIDs: [1, 2], includeAdult: false))
    }
    func testEmptyCommunityScopeDoesNotRequestGeneralAnime() async throws {
        let client = HomeCommunityClient(api: AniListClient(transport: NeverCommunityTransport(), minimumRequestInterval: 0), cache: HomeContentCache(directory: nil))
        let result = try await client.feed(mediaIDs: [], includeAdult: false)
        XCTAssertTrue(result.value.threads.isEmpty)
        XCTAssertFalse(result.value.hasNextPage)
    }
}

private struct NeverCommunityTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) { XCTFail("Empty scope must not request the general feed"); throw URLError(.badURL) }
}
