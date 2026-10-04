import XCTest
@testable import AnimeCore

/// Opt-in checks against the same public clients used by the app. Ordinary unit tests stay offline.
final class LiveServiceTests: XCTestCase {
    private func requireLiveServices() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ANIMECOMPANION_LIVE_SERVICES"] == "1",
                          "Set ANIMECOMPANION_LIVE_SERVICES=1 to check public providers.")
    }

    func testAniListPublicBrowsing() async throws {
        try requireLiveServices()
        let client = AniListClient()
        let season = SeasonSelection.current()
        let explore = try await client.explore(season)
        XCTAssertFalse((explore.trending.media ?? []).isEmpty)
        _ = try await client.seasonal(season, page: 2)
        let search = try await client.search("Cowboy Bebop")
        XCTAssertTrue((search.media ?? []).contains { $0.id == 1 })
        let details = try await client.details(id: 1)
        XCTAssertEqual(details.id, 1)
        XCTAssertEqual(details.episodes, 26)
        let lookup = try await client.media(ids: [1, 5])
        XCTAssertEqual(Set(lookup.map(\.id)), Set([1, 5]))
        let week = try XCTUnwrap(Calendar.current.dateInterval(of: .weekOfYear, for: Date()))
        let airings = try await client.airings(in: week)
        XCTAssertTrue(airings.allSatisfy { event in
            event.date.map { $0 >= week.start && $0 < week.end } ?? false
        })
    }

    func testEnglishDubProviders() async throws {
        try requireLiveServices()
        let client = DubClient()
        let snapshot = try await client.snapshot(refresh: true)
        XCTAssertFalse(snapshot.events().isEmpty)
        let availability = try await client.availability(malId: 1)
        XCTAssertEqual(availability, .dubbed)
    }

    func testAnimeNewsNetworkFeed() async throws {
        try requireLiveServices()
        let articles = try await NewsClient().articles(refresh: true)
        XCTAssertFalse(articles.isEmpty)
        XCTAssertTrue(articles.allSatisfy { !$0.title.isEmpty && $0.url.scheme == "https" })
    }
}
