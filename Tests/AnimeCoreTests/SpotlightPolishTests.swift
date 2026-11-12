import XCTest
@testable import AnimeCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class SpotlightPolishTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "spotlight-\(name)-textless", withExtension: "html")))
    }
    func testCapturedTextlessCollectionsForAllThreeReportedTitles() throws {
        let cases = [("one-piece", 37854, 49), ("mage", 313346, 6), ("returner", 230050, 2)]
        for (name, id, count) in cases {
            let urls = try SpotlightArtworkParser.images(fixture(name), target: .init(id: id), kind: .posters)
            XCTAssertEqual(urls.count, count); XCTAssertEqual(Set(urls).count, count)
            XCTAssertTrue(urls.allSatisfy { $0.host == "image.tmdb.org" && $0.path.contains("/original/") })
            if name == "mage" { XCTAssertEqual(urls.first?.lastPathComponent, "iRkFny4BWIw5nNkAbfph5UMxw18.jpg") }
            if name == "returner" { XCTAssertEqual(urls.first?.lastPathComponent, "2vI6llYWyA2wa5QgvDAq63BxNdI.jpg", "Prefer the 900-pixel clean key visual over the 550-pixel upload") }
        }
    }
    func testWrongSeriesLanguageAndUnverifiedCardsCannotBecomeCleanArtwork() throws {
        let data = try fixture("mage")
        XCTAssertThrowsError(try SpotlightArtworkParser.images(data, target: .init(id: 37854), kind: .posters))
        let html = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertThrowsError(try SpotlightArtworkParser.images(Data(html.replacingOccurrences(of: "class=\"active\"", with: "class=\"inactive\"").utf8), target: .init(id: 313346), kind: .posters))
        let branded = Data(html.replacingOccurrences(of: "data-language=\"xx\"", with: "data-language=\"en\"").utf8)
        XCTAssertTrue(try SpotlightArtworkParser.images(branded, target: .init(id: 313346), kind: .posters).isEmpty)
        let unsafe = Data(html.replacingOccurrences(of: "https://image.tmdb.org/t/p/original/", with: "https://image.tmdb.org.example/").utf8)
        XCTAssertTrue(try SpotlightArtworkParser.images(unsafe, target: .init(id: 313346), kind: .posters).isEmpty)
    }
    func testExactMappedSeasonAndMovieURLsRejectOtherCollections() throws {
        let season = SpotlightArtworkTarget(id: 230050, season: 2)
        XCTAssertEqual(season.pageURL(kind: .posters)?.absoluteString, "https://www.themoviedb.org/tv/230050/season/2/images/posters?image_language=xx")
        XCTAssertFalse(season.accepts(URL(string: "https://www.themoviedb.org/tv/230050/images/posters?image_language=xx")!, kind: .posters))
        XCTAssertFalse(season.accepts(URL(string: "https://www.themoviedb.org/tv/230050/season/2/images/posters?image_language=en")!, kind: .posters))
        XCTAssertEqual(SpotlightArtworkTarget(id: 42, movie: true, season: 2).pageURL(kind: .posters)?.path, "/movie/42/images/posters")
        XCTAssertNil(SpotlightArtworkTarget(id: -1).pageURL(kind: .posters))
    }
    func testUpgradeFetchesCleanImagesWithoutReplacingSeriesPostersOrTransparentLogos() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = HomeContentCache(directory: directory)
        let old = SeriesArtwork(logo: URL(string: "https://art.example/original-logo.png"),
            backdrop: URL(string: "https://art.example/background.jpg"), poster: URL(string: "https://images.metahub.space/poster/large/tt0388629/img"))
        let key = "series-art-v1-21-21-false"
        await cache.save(HomeContentSnapshot(old), key: key)
        await cache.save(HomeContentSnapshot(old), key: "spotlight-" + key)
        let oldIdentity = try SeriesArtworkDecoding.identities(Data(#"[{"anilist_id":21,"mal_id":21,"imdb_id":["tt0388629"],"type":"TV"}]"#.utf8))
        await cache.save(HomeContentSnapshot(oldIdentity), key: "series-art-identities-v1")
        let transport = CapturedSpotlightTransport(poster: try fixture("one-piece"))
        let client = SeriesArtworkClient(transport: transport, cache: cache)
        let anime = try JSONDecoder().decode(Anime.self, from: Data(#"{"id":21,"idMal":21,"format":"TV"}"#.utf8))
        let result = await client.spotlightArtwork(for: anime)
        XCTAssertEqual(result.spotlightPoster?.lastPathComponent, "b8cFEdlarCrpOLOjwd7aSw4uRQA.jpg")
        XCTAssertEqual(result.poster, old.poster); XCTAssertEqual(result.logo, old.logo)
        let regular = await client.artwork(for: anime)
        XCTAssertEqual(regular.poster, old.poster)
        let restored = SeriesArtworkClient(transport: transport, cache: cache)
        let before = await transport.calls.count
        let saved = await restored.spotlightArtwork(for: anime)
        XCTAssertEqual(saved.spotlightPoster, result.spotlightPoster)
        let after = await transport.calls.count; XCTAssertEqual(after, before)
        let calls = await transport.calls
        XCTAssertTrue(calls.contains(SeriesArtworkClient.mappingURL), "The old mapping cache lacks TMDB IDs and must refresh")
    }
    func testLoopBoundaryCopiesKeepLogicalSelectionAcrossRepeatedWraps() {
        let loop = SpotlightLoop(count: 5)
        XCTAssertEqual(loop.slots, [-1, 0, 1, 2, 3, 4, 5])
        for _ in 0..<100 {
            XCTAssertEqual(loop.index(for: -1), 4); XCTAssertEqual(loop.rebase(-1), 4)
            XCTAssertEqual(loop.index(for: 5), 0); XCTAssertEqual(loop.rebase(5), 0)
            for i in 0..<5 { XCTAssertNil(loop.rebase(i)); XCTAssertEqual(loop.index(for: i), i) }
        }
        XCTAssertEqual(loop.neighbors(of: 0), [0, 1, 4])
        XCTAssertEqual(loop.neighbors(of: 4), [4, 0, 3])
        XCTAssertEqual(SpotlightLoop(count: 1).slots, [0]); XCTAssertNil(SpotlightLoop(count: 1).rebase(0))
        XCTAssertTrue(SpotlightLoop(count: 0).slots.isEmpty); XCTAssertNil(SpotlightLoop(count: 0).index(for: 0))
    }
    func testReadyLogoCanCommitWithItsDecodedBackgroundAfterSwipeSettles() {
        var state = SpotlightTitlePresentation()
        state.checkedCache(for: 1, hasLogo: false)
        state.preparedLogo(for: 1, protected: [1])
        XCTAssertEqual(state.title(for: 1), .text)
        state.presentPrepared(); XCTAssertEqual(state.title(for: 1), .logo)
    }
}

private actor CapturedSpotlightTransport: HTTPTransport {
    let poster: Data
    private(set) var calls: [URL] = []
    init(poster: Data) { self.poster = poster }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = try XCTUnwrap(request.url); calls.append(url)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        let data: Data
        if url == SeriesArtworkClient.mappingURL {
            data = Data(#"[{"anilist_id":21,"mal_id":21,"imdb_id":["tt0388629"],"type":"TV","themoviedb_id":{"tv":37854}}]"#.utf8)
        } else if url.path == "/tv/37854/images/posters" { data = poster }
        else if url.path == "/tv/37854/images/backdrops" {
            data = Data(#"<link rel="canonical" href="https://www.themoviedb.org/tv/37854/images/backdrops"><a id="image_language_xx" class="active">No Language</a>"#.utf8)
        } else { throw ServiceError.invalidResponse }
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
