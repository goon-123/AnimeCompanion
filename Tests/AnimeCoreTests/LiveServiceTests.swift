import XCTest
@testable import AnimeCore

/// Opt-in checks against the same public clients used by the app. Ordinary unit tests stay offline.
final class LiveServiceTests: XCTestCase {
    func testLiveChartIDMatchingSource() async throws {
        try requireLiveServices()
        let client = LiveChartClient()
        let liveChartID = try await client.liveChartID(aniListID: 1)
        XCTAssertEqual(liveChartID, 3418)
        let aniListID = try await client.aniListID(liveChartID: 3418)
        XCTAssertEqual(aniListID, 1)
    }
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
        XCTAssertEqual(details.startDate?.year, 1998)
        XCTAssertGreaterThan(details.popularity ?? 0, 0)
        XCTAssertFalse((details.staff?.edges ?? []).isEmpty)
        XCTAssertFalse((details.recommendations?.nodes ?? []).isEmpty)
        XCTAssertFalse((details.externalLinks ?? []).isEmpty)
        let browse = try await client.browse(DiscoveryFilters(category: .trending))
        XCTAssertFalse((browse.media ?? []).isEmpty)
        XCTAssertTrue((browse.media ?? []).allSatisfy { $0.isAdult != true })
        var ecchi = DiscoveryFilters(category: .trending)
        ecchi.genre = "Ecchi"
        let genreResults = try await client.browse(ecchi)
        XCTAssertFalse((genreResults.media ?? []).isEmpty)
        XCTAssertTrue((genreResults.media ?? []).allSatisfy { ($0.genres ?? []).contains("Ecchi") })
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
        XCTAssertEqual(snapshot.scheduleProvider, .current)
        XCTAssertEqual(snapshot.historyProvider, .current)
        let historyUpdated = try XCTUnwrap(snapshot.historyUpdatedAt)
        XCTAssertLessThan(Date().timeIntervalSince(historyUpdated), 3 * 86400, "Detect a stalled release feed instead of passing on old data.")
        let index = try await client.index(refresh: true)
        XCTAssertFalse(index.partial.isEmpty)
        let availability = index.availability(malId: 1)
        XCTAssertEqual(availability, .dubbed)
        XCTAssertGreaterThan(index.agreeingSources(malId: 1) ?? 0, 0)
        // Probe an anime from the missing-count report using live metadata, not a hardcoded count.
        let title = try await AniListClient().details(id: 169581)
        let progress = LibraryDubProgress(anime: title, snapshot: snapshot, index: index)
        XCTAssertGreaterThan(progress.released ?? 0, 0)
        XCTAssertEqual(progress.confidence, .reported)
        XCTAssertTrue(snapshot.events(knownMedia: [title.id: title]).contains { $0.anime.id == title.id })
    }

    func testAnimeNewsNetworkFeed() async throws {
        try requireLiveServices()
        let client = NewsClient()
        let snapshot = try await client.snapshot(refresh: true)
        let articles = snapshot.articles
        XCTAssertEqual(Set(articles.map(\.source)), Set(NewsSource.allCases))
        XCTAssertTrue(articles.contains { $0.imageURL != nil })
        if let ann = articles.first(where: { $0.source == .animeNewsNetwork }) {
            let image = await client.thumbnail(for: ann)
            XCTAssertNotNil(image)
        }
        XCTAssertFalse(articles.isEmpty)
        XCTAssertTrue(articles.allSatisfy { !$0.title.isEmpty && $0.url.scheme == "https" })
    }
}
