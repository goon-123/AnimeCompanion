import XCTest
@testable import AnimeCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class AnimeEpisodesTests: XCTestCase {
    private func anime(_ count: Int = 12, mal: Bool = true) throws -> Anime {
        try JSONDecoder().decode(Anime.self, from: Data("{\"id\":1,\"idMal\":\(mal ? "7" : "null"),\"episodes\":\(count),\"status\":\"FINISHED\"}".utf8))
    }
    func testCanonicalEpisodesExcludeSpecialsAndConflictingTVDBStills() throws {
        let raw = Data(#"{"mappings":{"anilist_id":1,"mal_id":7},"episodes":{"1":{"episode":"1","episodeNumber":1,"title":{"en":null,"x-jat":"Owned first episode"},"image":"https://art.example/1.jpg","summary":null,"overview":"Canonical synopsis","airdate":null,"airDateUtc":"2026-01-02T12:00:00Z","runtime":null,"length":24,"rating":"8.2"},"2":{"episode":"2","episodeNumber":40,"absoluteEpisodeNumber":30,"title":{"en":"Owned second episode"},"summary":"AniDB summary","overview":"Wrong TVDB plot","image":"https://art.example/wrong.jpg"},"S1":{"episode":"1","title":{"en":"Special"}},"3":{"episode":"9","title":{"en":"Wrong number"}},"99":{"episode":"99","title":{"en":"Other season"}}}}"#.utf8)
        let rows = try AnimeEpisodeDecoding.mapping(raw, anime: anime())
        XCTAssertEqual(rows.map(\.number), [1, 2])
        XCTAssertEqual(rows[0].imageURL?.lastPathComponent, "1.jpg")
        XCTAssertEqual(rows[0].title, "Owned first episode"); XCTAssertEqual(rows[0].overview, "Canonical synopsis")
        XCTAssertEqual(rows[0].airDate, "2026-01-02T12:00:00Z")
        XCTAssertEqual(rows[0].rating, 8.2); XCTAssertEqual(rows[0].runtime, 24)
        XCTAssertEqual(rows[1].overview, "AniDB summary"); XCTAssertNil(rows[1].imageURL)
        let wrong = Data(#"{"mappings":{"anilist_id":2,"mal_id":7},"episodes":{}}"#.utf8)
        XCTAssertThrowsError(try AnimeEpisodeDecoding.mapping(wrong, anime: anime()))
        let wrongMAL = Data(#"{"mappings":{"anilist_id":1,"mal_id":8},"episodes":{}}"#.utf8)
        XCTAssertThrowsError(try AnimeEpisodeDecoding.mapping(wrongMAL, anime: anime()))
    }
    func testFallbackListKeepsFillerRecapDatesAndRejectsPrivateImageURLs() throws {
        let raw = Data(#"{"pagination":{"has_next_page":true},"data":[{"mal_id":1,"title":null,"title_romanji":"Owned title","aired":"2026-01-02T10:00:00+00:00","score":7.2,"filler":true},{"mal_id":2,"title":"Owned recap","recap":true},{"mal_id":2,"title":"Duplicate"}]}"#.utf8)
        let (rows, more) = try AnimeEpisodeDecoding.jikan(raw)
        XCTAssertEqual(rows.map(\.number), [1, 2]); XCTAssertTrue(more)
        XCTAssertEqual(rows[0].title, "Owned title"); XCTAssertTrue(rows[0].filler); XCTAssertTrue(rows[1].recap); XCTAssertNotNil(rows[0].dateLabel)
        XCTAssertNil(AnimeEpisodeMetadata(number: 1, image: "https://user:secret@images.example/1.jpg").imageURL)
        XCTAssertNil(AnimeEpisodeMetadata(number: 1, image: "http://localhost/a.jpg").imageURL)
        XCTAssertTrue(AnimeEpisodeMetadata(number: 1, airDate: "2027-01-02T10:00:00Z").isFuture(at: Date(timeIntervalSince1970: 1_700_000_000)))
    }
    func testMappingRequestsCoalesceAndLaterPagesUseSavedMapping() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var rows: [String: Any] = [:]
        for number in 1...101 { rows[String(number)] = ["episode": String(number), "episodeNumber": number, "title": ["en": "Episode \(number)"]] }
        let data = try JSONSerialization.data(withJSONObject: ["mappings": ["anilist_id": 1, "mal_id": 7], "episodes": rows])
        let transport = EpisodeTransport(mapping: data)
        let client = AnimeEpisodesClient(transport: transport, cache: HomeContentCache(directory: folder), minimumRequestInterval: 0)
        let series = try anime(101)
        async let first = client.page(for: series)
        async let same = client.page(for: series)
        let values = try await [first, same]
        XCTAssertEqual(values[0].episodes.count, 100); XCTAssertTrue(values[0].hasMore)
        let next = try await client.page(for: series, page: 2)
        XCTAssertEqual(next.episodes.map(\.number), [101]); XCTAssertFalse(next.hasMore)
        let count = await transport.count; XCTAssertEqual(count, 1)
        let restored = await AnimeEpisodesClient(transport: transport, cache: HomeContentCache(directory: folder), minimumRequestInterval: 0).cached(for: series)
        XCTAssertEqual(restored?.episodes.first?.title, "Episode 1")
    }
    func testUnavailableMappingFallsBackToExactMALIDWithoutCredentials() async throws {
        let transport = EpisodeTransport(mapping: Data("{}".utf8), jikan: Data(#"{"data":[{"mal_id":1,"title":"Fallback episode"}],"pagination":{"has_next_page":false}}"#.utf8))
        let client = AnimeEpisodesClient(transport: transport, cache: HomeContentCache(directory: nil), minimumRequestInterval: 0)
        let result = try await client.page(for: anime())
        XCTAssertEqual(result.episodes.first?.title, "Fallback episode")
        let requests = await transport.requests
        XCTAssertEqual(requests.last?.url?.path, "/v4/anime/7/episodes")
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    }
    func testFailedRefreshRetainsPreviousEpisodeMetadata() async throws {
        let cache = HomeContentCache(directory: nil)
        await cache.save(HomeContentSnapshot([AnimeEpisodeMetadata(number: 1, title: "Saved episode")], savedAt: Date().addingTimeInterval(-7200)), key: "episode-map-v1-1-0")
        let client = AnimeEpisodesClient(transport: EpisodeTransport(mapping: Data("{}".utf8)), cache: cache, minimumRequestInterval: 0)
        let result = try await client.page(for: anime(mal: false), refresh: true)
        XCTAssertEqual(result.episodes.first?.title, "Saved episode"); XCTAssertNotNil(result.notice)
    }
}

private actor EpisodeTransport: HTTPTransport {
    let mapping: Data
    let jikan: Data
    private(set) var requests: [URLRequest] = []
    var count: Int { requests.count }
    init(mapping: Data, jikan: Data = Data("{}".utf8)) { self.mapping = mapping; self.jikan = jikan }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (request.url?.host == "api.ani.zip" ? mapping : jikan,
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
