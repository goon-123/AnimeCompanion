import XCTest
@testable import AnimeCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class AnimeVisualGalleryTests: XCTestCase {
    private let page = URL(string: "https://www.livechart.me/anime/12735/visuals")!
    private func anime() throws -> Anime {
        try JSONDecoder().decode(Anime.self, from: Data(#"{"id":178789,"idMal":59193,"title":{"english":"Mushoku Tensei Season 3"},"coverImage":{"large":"https://s4.anilist.co/file/poster.jpg"},"bannerImage":"https://s4.anilist.co/file/banner.jpg"}"#.utf8))
    }
    private func data(_ text: String) -> Data { Data(text.utf8) }

    func testGalleryReadsAllFourCharacterVisualsAndPreservesCaptionsCreditsAndFullSizeURLs() throws {
        let html = "<html><body>" + ["Roxy", "Sylphiette", "Rudeus", "Eris"].map { name in
            """
            <article data-anime-visual-url-value='https://u.livechart.me/visuals/\(name).jpg?size=large&amp;x=1'>
            <img src='https://u.livechart.me/visuals/\(name)-thumb.jpg' alt='Character Visual - \(name)'>
            <b>Character Visual - \(name)</b><p>© Owned &amp; Test</article>
            """
        }.joined()
        let result = try AnimeVisualParser.liveChart(data(html), pageURL: page, liveChartID: 12735)
        XCTAssertEqual(result.images.map(\.title), ["Roxy", "Sylphiette", "Rudeus", "Eris"].map { "Character Visual - \($0)" })
        XCTAssertTrue(result.images.allSatisfy { $0.copyright == "© Owned & Test" && $0.source == .liveChart })
        XCTAssertEqual(result.images.first?.imageURL.query, "size=large&x=1")
        XCTAssertTrue(result.images.first!.thumbnailURL.path.hasSuffix("Roxy-thumb.jpg"))
    }
    func testParserDeduplicatesAndRejectsUntrustedImageURLs() throws {
        let urls = ["https://u.livechart.me/a.jpg", "https://u.livechart.me/a.jpg#same", "http://u.livechart.me/b.jpg",
                    "https://u.livechart.me.evil.example/c.jpg", "https://user:pass@u.livechart.me/d.jpg", "javascript:alert(1)"]
        let html = urls.map { "<div data-anime-visual-url-value='\($0)'><img alt='Visual'></div>" }.joined()
        let result = try AnimeVisualParser.liveChart(data(html), pageURL: page, liveChartID: 12735)
        XCTAssertEqual(result.images.count, 1)
        XCTAssertEqual(result.images[0].imageURL.absoluteString, "https://u.livechart.me/a.jpg")
    }
    func testPaginationKeepsTheSameAnimeAndCannotPointToAnotherHostOrSeason() throws {
        let card = "<div data-anime-visual-url-value='https://u.livechart.me/a.jpg'></div>"
        let result = try AnimeVisualParser.liveChart(data(card + "<a rel='next' href='?page=2'>Next</a>"), pageURL: page, liveChartID: 12735)
        XCTAssertEqual(result.nextPage?.absoluteString, page.absoluteString + "?page=2")
        for next in ["https://evil.example/?page=2", "/anime/13827/visuals?page=2", "?page=0", "?page=999"] {
            XCTAssertThrowsError(try AnimeVisualParser.liveChart(data(card + "<a rel='next' href='\(next)'>Next</a>"), pageURL: page, liveChartID: 12735))
        }
    }
    func testChallengeAndChangedMarkupAreErrorsWhileConfirmedEmptyGalleryIsEmpty() throws {
        for html in ["<h1>Just a moment</h1>", "<html>Log in</html>", "<div data-anime-visual-url-value='https://evil.example/a.jpg'></div>"] {
            XCTAssertThrowsError(try AnimeVisualParser.liveChart(data(html), pageURL: page, liveChartID: 12735))
        }
        let html = "<link rel='canonical' href='\(page.absoluteString)'><h1>Visuals</h1>"
        XCTAssertTrue(try AnimeVisualParser.liveChart(data(html), pageURL: page, liveChartID: 12735).images.isEmpty)
        XCTAssertThrowsError(try AnimeVisualParser.liveChart(Data(repeating: 32, count: 2_000_001), pageURL: page, liveChartID: 12735))
    }
    func testMALPicturesPreferLargeImagesAndDeduplicateVariantsWithoutInventingCaptions() throws {
        let json = #"{"data":[{"jpg":{"image_url":"https://cdn.myanimelist.net/thumb.jpg","large_image_url":"https://cdn.myanimelist.net/full.jpg"},"webp":{"image_url":"https://cdn.myanimelist.net/same.webp"}},{"jpg":{"image_url":"https://cdn.myanimelist.net/full.jpg"}},{"jpg":{"image_url":"https://evil.example/a.jpg"}}]}"#
        let result = try AnimeVisualParser.myAnimeList(data(json))
        XCTAssertEqual(result.count, 1); XCTAssertEqual(result[0].title, "Artwork 1")
        XCTAssertNil(result[0].copyright); XCTAssertEqual(result[0].imageURL.path, "/full.jpg")
        XCTAssertEqual(result[0].thumbnailURL.path, "/thumb.jpg")
        XCTAssertThrowsError(try AnimeVisualParser.myAnimeList(data(#"{"data":[{"jpg":{"image_url":"javascript:bad"}}]}"#)))
        XCTAssertTrue(try AnimeVisualParser.myAnimeList(data(#"{"data":[]}"#)).isEmpty)
    }
    func testIDMappingSeparatesSeasonsAndRejectsAmbiguousOrContradictoryIDs() throws {
        let tsv = "anilist\tlivechart\tmyanimelist\n178789\t12735\t59193\n217434\t13827\t65077\n1\t8\t1\n1\t9\t1\n2\t10\t2\n3\t10\t3\n4\t11\t4\n4\t11\t44\n"
        let index = try VisualsMappingIndex(tsv: data(tsv))
        XCTAssertEqual(index.liveChartID(aniListID: 178789, malID: 59193), 12735)
        XCTAssertEqual(index.liveChartID(aniListID: 217434, malID: 65077), 13827)
        XCTAssertNil(index.liveChartID(aniListID: 178789, malID: 65077))
        for id in [1, 2, 3, 4, 999] { XCTAssertNil(index.liveChartID(aniListID: id, malID: nil)) }
        XCTAssertThrowsError(try VisualsMappingIndex(tsv: data("title\tlivechart\nOne\t2")))
    }
    func testClientFollowsPagesCoalescesConcurrentViewsCachesAndNeverSendsCredentials() async throws {
        let fixture = GalleryTransport(mode: .live)
        let client = AnimeVisualsClient(transport: fixture, directory: nil, minimumRequestInterval: 0)
        let anime = try anime()
        async let a = client.gallery(for: anime)
        async let b = client.gallery(for: anime)
        let results = await [a, b]
        XCTAssertEqual(results[0].images.count, 8)
        XCTAssertEqual(results[0].images, results[1].images)
        XCTAssertNil(results[0].notice)
        _ = await client.gallery(for: anime)
        let requests = await fixture.requests
        XCTAssertEqual(requests.count, 3) // one mapping and two gallery pages
        XCTAssertFalse(requests.contains { $0.url?.host == "api.jikan.moe" })
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil && $0.value(forHTTPHeaderField: "Cookie") == nil })
    }
    func testDeniedLiveChartUsesMALAndRefreshHonorsHostCooldown() async throws {
        let fixture = GalleryTransport(mode: .denied)
        let client = AnimeVisualsClient(transport: fixture, directory: nil, minimumRequestInterval: 0)
        let anime = try anime()
        let first = await client.gallery(for: anime)
        XCTAssertEqual(first.images.map(\.source), [.myAnimeList, .aniList, .aniList])
        XCTAssertTrue(first.notice?.contains("LiveChart could not load") == true)
        _ = await client.gallery(for: anime, refresh: true)
        let requests = await fixture.requests
        XCTAssertEqual(requests.filter { $0.url?.host == "www.livechart.me" }.count, 1)
        XCTAssertEqual(requests.filter { $0.url?.host == "api.jikan.moe" }.count, 2)
    }
    func testConflictingMappingNeverRequestsWrongLiveChartTitle() async throws {
        let fixture = GalleryTransport(mode: .conflict)
        let client = AnimeVisualsClient(transport: fixture, directory: nil, minimumRequestInterval: 0)
        let result = await client.gallery(for: try anime())
        XCTAssertTrue(result.notice?.contains("No matching LiveChart gallery") == true)
        let requests = await fixture.requests
        XCTAssertFalse(requests.contains { $0.url?.host == "www.livechart.me" })
    }
    func testSavedGallerySurvivesClientRestartWithoutNetworkAndFailedRefreshPreservesIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VisualGalleryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = AnimeVisualsClient(transport: GalleryTransport(mode: .live), directory: directory, minimumRequestInterval: 0)
        let anime = try anime()
        let original = await first.gallery(for: anime)
        let offline = GalleryTransport(mode: .offline)
        let second = AnimeVisualsClient(transport: offline, directory: directory, minimumRequestInterval: 0)
        let cached = await second.gallery(for: anime)
        XCTAssertEqual(original.images, cached.images)
        let count = await offline.requests.count
        XCTAssertEqual(count, 0)
        async let a = second.gallery(for: anime, refresh: true)
        async let b = second.gallery(for: anime, refresh: true)
        let refreshed = await [a, b]
        XCTAssertTrue(refreshed.allSatisfy { $0.isStale && $0.images == original.images })
    }
    func testSecondPageFailureKeepsAlreadyLoadedImagesAndExplainsPartialCollection() async throws {
        let client = AnimeVisualsClient(transport: GalleryTransport(mode: .secondPageFails), directory: nil, minimumRequestInterval: 0)
        let result = await client.gallery(for: try anime())
        XCTAssertEqual(result.images.count, 6)
        XCTAssertTrue(result.notice?.contains("Some LiveChart visuals could not load") == true)
    }
    func testEveryProviderFailingKeepsAniListArtworkAndExplainsTheFailure() async throws {
        let client = AnimeVisualsClient(transport: GalleryTransport(mode: .offline), directory: nil, minimumRequestInterval: 0)
        let result = await client.gallery(for: try anime())
        XCTAssertEqual(result.images.map(\.source), [.aniList, .aniList])
        XCTAssertNotNil(result.notice)
    }
    func testDefaultPublicSessionDoesNotUseBrowserCookies() {
        let configuration = AnimeVisualsClient.publicTransport().session.configuration
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.httpCookieStorage)
    }
}

private actor GalleryTransport: HTTPTransport {
    enum Mode { case live, denied, conflict, offline, secondPageFails }
    let mode: Mode
    private(set) var requests: [URLRequest] = []
    init(mode: Mode) { self.mode = mode }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        try await Task.sleep(nanoseconds: 15_000_000)
        let url = request.url!
        if mode == .offline { throw URLError(.notConnectedToInternet) }
        var status = 200, body = ""
        switch url.host {
        case "raw.githubusercontent.com":
            body = "anilist\tlivechart\tmyanimelist\n178789\t12735\t\(mode == .conflict ? 65077 : 59193)\n"
        case "www.livechart.me":
            if mode == .denied || (mode == .secondPageFails && url.query != nil) { status = 403; body = "Denied" }
            else {
                let names = url.query == nil ? ["Roxy", "Sylphiette", "Rudeus", "Eris"] : ["Key", "Teaser"]
                body = names.map { "<div data-anime-visual-url-value='https://u.livechart.me/\($0).jpg'><img alt='\($0)'></div>" }.joined()
                if url.query == nil { body += "<a rel='next' href='?page=2'>Next</a>" }
            }
        case "api.jikan.moe": body = #"{"data":[{"jpg":{"image_url":"https://cdn.myanimelist.net/additional.jpg"}}]}"#
        default: throw URLError(.unsupportedURL)
        }
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": "900"])!)
    }
}
