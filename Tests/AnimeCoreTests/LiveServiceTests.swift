import XCTest
@testable import AnimeCore

/// Opt-in checks against the same public clients used by the app. Ordinary unit tests stay offline.
final class LiveServiceTests: XCTestCase {
    func testMangaBakaDiscoveryDetails() async throws {
        try requireLiveServices()
        let api = MangaBakaClient(directory: nil)
        let genres = try await api.genres(), tags = try await api.tags()
        XCTAssertFalse(genres.isEmpty); XCTAssertFalse(tags.isEmpty)
        XCTAssertTrue(tags.contains { $0.path.contains(" > ") })
        let details = try await api.details(id: 1)
        XCTAssertFalse(details.tags.isEmpty)
        print("Checking MangaBaka cover pagination")
        let covers = try await api.covers(id: 1)
        XCTAssertFalse(covers.items.isEmpty)
        XCTAssertTrue(covers.items.contains { $0.fullURL != nil })
        for kind in MangaBakaRelatedKind.allCases {
            print("Checking MangaBaka " + kind.rawValue)
            _ = try await api.related(id: 1, kind: kind, includeAdult: false)
        }
        if let genre = genres.first {
            print("Checking MangaBaka genre query")
            let result = try await api.browse(.init(genres: [genre], contentRatings: [.safe]), limit: 2, includeAdult: false)
            XCTAssertTrue(result.items.allSatisfy { $0.contentRating == "safe" && $0.genres.contains { $0.name == genre.value } })
        }
        if let tag = tags.first {
            print("Checking MangaBaka tag query")
            _ = try await api.browse(.init(tags: [tag]), limit: 2, includeAdult: false)
        }
        print("Checking MangaBaka excluded tag and single content rating")
        if let tag = tags.first { _ = try await api.browse(.init(excludedTags: [tag]), limit: 2, includeAdult: false) }
        let safe = try await api.browse(.init(contentRatings: [.safe]), limit: 2, includeAdult: false)
        XCTAssertTrue(safe.items.allSatisfy { $0.contentRating == "safe" })
    }
    func testMangaBakaPublicCatalog() async throws {
        try requireLiveServices()
        let api = MangaBakaClient(directory: nil)
        let trending = try await api.browse(.init(shelf: .trending), limit: 3, includeAdult: false)
        XCTAssertFalse(trending.items.isEmpty)
        XCTAssertTrue(trending.items.allSatisfy { $0.isVisible(includeAdult: false) })
        let details = try await api.details(id: 1)
        XCTAssertEqual(details.id, 1); XCTAssertEqual(details.type, "manhwa")
        XCTAssertFalse(details.displayTitle.isEmpty); XCTAssertNotNil(details.coverURL)
        XCTAssertFalse(details.genres.isEmpty)
        for shelf in [MangaBakaShelf.rising, .hiddenGems, .recentlyAdded, .newReleases] {
            let page = try await api.browse(.init(shelf: shelf), limit: 2, includeAdult: false)
            XCTAssertFalse(page.items.isEmpty, shelf.label)
        }
        let novels = try await api.browse(.init(format: .novel), page: 2, limit: 2, includeAdult: false)
        XCTAssertFalse(novels.items.isEmpty); XCTAssertTrue(novels.items.allSatisfy { $0.type == "novel" })
        let search = try await api.browse(.init(text: "DICE"), limit: 10, includeAdult: false)
        XCTAssertFalse(search.items.isEmpty)
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
