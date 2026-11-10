import XCTest
@testable import AnimeCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class SeriesArtworkTests: XCTestCase {
    func testLogoDoesNotWaitForBackdropFallbackAndFullDetailsStillResolveIt() async throws {
        let transport = LogoFirstTransport()
        let client = SeriesArtworkClient(transport: transport, cache: HomeContentCache(directory: nil))
        let item = try anime()
        let logo = await client.logoArtwork(for: item)
        XCTAssertNotNil(logo.logo); XCTAssertNil(logo.backdrop)
        let before = await transport.fallbacks
        XCTAssertEqual(before, 0)
        let full = await client.artwork(for: item)
        XCTAssertNotNil(full.logo); XCTAssertNotNil(full.backdrop)
        let after = await transport.fallbacks
        XCTAssertEqual(after, 1)
        let primaries = await transport.primaries
        XCTAssertEqual(primaries, 1)
    }
    func testCachedArtworkLookupDoesNotContactProviders() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let transport = LogoFirstTransport()
        let first = SeriesArtworkClient(transport: transport, cache: HomeContentCache(directory: folder))
        _ = await first.logoArtwork(for: try anime())
        let second = SeriesArtworkClient(transport: transport, cache: HomeContentCache(directory: folder))
        let cached = await second.cachedArtwork(for: try anime())
        XCTAssertNotNil(cached?.logo)
        let count = await transport.primaries
        XCTAssertEqual(count, 1)
    }
    func testConcurrentLogoAndDetailRequestsShareProviderLookup() async throws {
        let transport = LogoFirstTransport()
        let client = SeriesArtworkClient(transport: transport, cache: HomeContentCache(directory: nil))
        let item = try anime()
        async let logo = client.logoArtwork(for: item)
        async let full = client.artwork(for: item)
        let (a, b) = await (logo, full)
        XCTAssertNotNil(a.logo); XCTAssertNotNil(b.backdrop)
        let count = await transport.primaries
        XCTAssertEqual(count, 1)
    }
    private func anime(_ json: String = #"{"id":20458,"idMal":20785,"format":"TV"}"#) throws -> Anime {
        try JSONDecoder().decode(Anime.self, from: Data(json.utf8))
    }
    func testExactIdentityRejectsConflictingMoviesMALAndAmbiguousIMDbMatches() throws {
        let data = Data(#"[{"anilist_id":20458,"mal_id":20785,"type":"TV","imdb_id":["tt3874528"]},{"anilist_id":2,"type":"MOVIE","imdb_id":["tt1234567","tt2345678"]}]"#.utf8)
        let rows = try SeriesArtworkDecoding.identities(data)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(SeriesArtworkDecoding.identity(for: try anime(), in: rows)?.imdb, "tt3874528")
        XCTAssertNil(SeriesArtworkDecoding.identity(for: try anime(#"{"id":20458,"idMal":99,"format":"TV"}"#), in: rows))
        XCTAssertNil(SeriesArtworkDecoding.identity(for: try anime(#"{"id":20458,"idMal":20785,"format":"MOVIE"}"#), in: rows))
        let conflict = try SeriesArtworkDecoding.identities(Data(#"[{"anilist_id":20458,"type":"TV","imdb_id":["tt1234567"]}]"#.utf8))
        XCTAssertNil(SeriesArtworkDecoding.identity(for: try anime(), in: rows + conflict))
    }
    func testCinemetaUsesItsRealLogoContractAndRejectsWrongIdentityAndUnsafeURLs() throws {
        let data = Data(#"{"meta":{"id":"tt3874528","type":"series","logo":"https://images.metahub.space/logo/medium/tt3874528/img","background":"https://images.metahub.space/background/medium/tt3874528/img","poster":"http://localhost/image.png"}}"#.utf8)
        let art = try SeriesArtworkDecoding.cinemeta(data, imdb: "tt3874528", movie: false)
        XCTAssertEqual(art.logo?.host, "images.metahub.space")
        XCTAssertNotNil(art.backdrop); XCTAssertNil(art.poster)
        XCTAssertThrowsError(try SeriesArtworkDecoding.cinemeta(data, imdb: "tt1234567", movie: false))
        XCTAssertThrowsError(try SeriesArtworkDecoding.cinemeta(data, imdb: "tt3874528", movie: true))
    }
    func testAniZipPrefersFanartAndClearlogoAndKeepsMovieArtworkSeparate() throws {
        let data = Data(#"{"mappings":{"anilist_id":20458,"mal_id":20785,"type":"TV"},"images":[{"coverType":"Banner","url":"https://artworks.thetvdb.com/banner.jpg"},{"coverType":"Fanart","url":"https://artworks.thetvdb.com/fanart.jpg"},{"coverType":"Clearlogo","url":"https://artworks.thetvdb.com/logo.png"}]}"#.utf8)
        let art = try SeriesArtworkDecoding.aniZip(data, anime: anime())
        XCTAssertEqual(art.logo?.lastPathComponent, "logo.png")
        XCTAssertEqual(art.backdrop?.lastPathComponent, "fanart.jpg")
        XCTAssertThrowsError(try SeriesArtworkDecoding.aniZip(data, anime: anime(#"{"id":999}"#)))
        XCTAssertTrue(try SeriesArtworkDecoding.aniZip(data, anime: anime(#"{"id":20458,"format":"MOVIE"}"#)).isEmpty)
    }
    func testCacheAndFailedRefreshKeepPreviouslyResolvedArtwork() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let transport = SeriesArtworkTestTransport()
        let client = SeriesArtworkClient(transport: transport, cache: HomeContentCache(directory: folder))
        let first = await client.artwork(for: try anime())
        XCTAssertNotNil(first.logo)
        let initialRequests = await transport.count()
        XCTAssertEqual(initialRequests, 2)
        let cached = await client.artwork(for: try anime())
        XCTAssertEqual(cached, first)
        let cachedRequests = await transport.count(); XCTAssertEqual(cachedRequests, 2)
        await transport.fail()
        let restored = await client.artwork(for: try anime(), refresh: true)
        XCTAssertEqual(restored, first)
    }
    func testNewExploreCollectionsKeepIndependentHiddenStatesAfterUpgrade() {
        var home = HomePreferences()
        XCTAssertFalse(home.visible.contains(.trendingAnime))
        home.setVisible(.trendingAnime, true)
        XCTAssertTrue(HomePreferences(saved: home.saved).visible.contains(.trendingAnime))
        let old = #"{"order":["catalog.trending","catalog.spotlight"],"hidden":["catalog.trending"]}"#
        var value = ExplorePreferences(surface: .anime, saved: old)
        XCTAssertEqual(value.order.first, .catalog(.trending))
        XCTAssertFalse(value.visible.contains(.catalog(.trending)))
        XCTAssertTrue(value.visible.contains(.catalog(.studios)))
        XCTAssertTrue(value.visible.contains(.catalog(.animeGenres)))
        value.setVisible(.catalog(.studios), false)
        let reopened = ExplorePreferences(surface: .anime, saved: value.saved)
        XCTAssertFalse(reopened.visible.contains(.catalog(.studios)))
        XCTAssertTrue(reopened.visible.contains(.catalog(.animeGenres)))
    }
    func testCountdownRequiresAFutureOriginalEpisodeWithinTheSeason() throws {
        let now = Date(timeIntervalSince1970: 100)
        let current = try anime(#"{"id":1,"status":"RELEASING","episodes":12,"nextAiringEpisode":{"episode":8,"airingAt":200}}"#)
        XCTAssertEqual(AnimeSeriesContent.nextBroadcast(for: current, now: now)?.episode, 8)
        XCTAssertNil(AnimeSeriesContent.nextBroadcast(for: current, now: Date(timeIntervalSince1970: 200)))
        let finished = try anime(#"{"id":1,"status":"FINISHED","nextAiringEpisode":{"episode":8,"airingAt":200}}"#)
        XCTAssertNil(AnimeSeriesContent.nextBroadcast(for: finished, now: now))
        let outsideSeason = try anime(#"{"id":1,"status":"RELEASING","episodes":12,"nextAiringEpisode":{"episode":13,"airingAt":200}}"#)
        XCTAssertNil(AnimeSeriesContent.nextBroadcast(for: outsideSeason, now: now))
    }
}

private actor LogoFirstTransport: HTTPTransport {
    private(set) var primaries = 0
    private(set) var fallbacks = 0
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let json: String
        if request.url == SeriesArtworkClient.mappingURL {
            json = #"[{"anilist_id":20458,"mal_id":20785,"type":"TV","imdb_id":["tt3874528"]}]"#
        } else if request.url?.host == "v3-cinemeta.strem.io" {
            primaries += 1
            json = #"{"meta":{"id":"tt3874528","type":"series","logo":"https://art.example/logo.png"}}"#
        } else {
            fallbacks += 1
            json = #"{"mappings":{"anilist_id":20458,"mal_id":20785,"type":"TV"},"images":[{"coverType":"Fanart","url":"https://art.example/backdrop.jpg"}]}"#
        }
        return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private actor SeriesArtworkTestTransport: HTTPTransport {
    private var requests = 0
    private var failing = false
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests += 1
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        if failing { throw ServiceError.invalidResponse }
        let json: String
        if request.url == SeriesArtworkClient.mappingURL {
            json = #"[{"anilist_id":20458,"mal_id":20785,"type":"TV","imdb_id":["tt3874528"]}]"#
        } else {
            XCTAssertEqual(request.url?.host, "v3-cinemeta.strem.io")
            json = #"{"meta":{"id":"tt3874528","type":"series","logo":"https://art.example/logo.png","background":"https://art.example/backdrop.jpg"}}"#
        }
        return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func count() -> Int { requests }
    func fail() { failing = true }
}
