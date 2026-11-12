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
    func testCanonicalRedirectsStayOnTheSameGalleryAndPage() {
        XCTAssertTrue(VisualURL.sameGallery(URL(string: "https://livechart.me/anime/12735/visuals/")!, as: page))
        for url in ["https://evil.example/anime/12735/visuals", "https://www.livechart.me/anime/12736/visuals",
                    "https://www.livechart.me/anime/12735", "https://www.livechart.me/anime/12735/visuals?page=2",
                    "http://www.livechart.me/anime/12735/visuals"] {
            XCTAssertFalse(VisualURL.sameGallery(URL(string: url)!, as: page))
        }
    }
    func testLazyThumbnailKeepsTheFullSizeVisualAndAvoidsPlaceholderRequests() throws {
        let html = "<div data-anime-visual-url-value='https://u.livechart.me/full.jpg'><img src='data:image/gif;base64,AA' data-src='https://u.livechart.me/thumb.jpg' alt='Key visual'></div>"
        let image = try XCTUnwrap(AnimeVisualParser.liveChart(data(html), pageURL: page, liveChartID: 12735).images.first)
        XCTAssertEqual(image.imageURL.path, "/full.jpg")
        XCTAssertEqual(image.thumbnailURL.path, "/thumb.jpg")
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
        XCTAssertEqual(results[0].images.filter { $0.source == .liveChart }.count, 6)
        XCTAssertEqual(results[0].images.filter { $0.source == .aniList }, AnimeVisualGallery.aniListImages(anime))
        XCTAssertEqual(results[0].images, results[1].images)
        XCTAssertNil(results[0].notice)
        _ = await client.gallery(for: anime)
        let requests = await fixture.requests
        XCTAssertEqual(requests.count, 3) // one mapping and two gallery pages
        XCTAssertFalse(requests.contains { $0.url?.host == "api.jikan.moe" })
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil && $0.value(forHTTPHeaderField: "Cookie") == nil })
    }
    func testDeniedLiveChartKeepsAniListAndRefreshHonorsHostCooldown() async throws {
        let fixture = GalleryTransport(mode: .denied)
        let client = AnimeVisualsClient(transport: fixture, directory: nil, minimumRequestInterval: 0)
        let anime = try anime()
        let first = await client.gallery(for: anime)
        XCTAssertEqual(first.images, AnimeVisualGallery.aniListImages(anime))
        XCTAssertTrue(first.notice?.contains("LiveChart is temporarily limiting") == true)
        _ = await client.gallery(for: anime, refresh: true)
        let requests = await fixture.requests
        XCTAssertEqual(requests.filter { $0.url?.host == "www.livechart.me" }.count, 1)
        XCTAssertFalse(requests.contains { $0.url?.host == "api.jikan.moe" })
    }
    func testPublicMappingAndGalleryCanUseIndependentTransports() async throws {
        let mapping = GalleryTransport(mode: .live), pages = GalleryTransport(mode: .live)
        let client = AnimeVisualsClient(transport: mapping, galleryTransport: pages, directory: nil, minimumRequestInterval: 0)
        let result = await client.gallery(for: try anime())
        XCTAssertEqual(result.images.filter { $0.source == .liveChart }.count, 6)
        let mappingRequests = await mapping.requests, pageRequests = await pages.requests
        XCTAssertEqual(mappingRequests.map { $0.url?.host }, ["raw.githubusercontent.com"])
        XCTAssertEqual(pageRequests.count, 2)
        XCTAssertTrue(pageRequests.allSatisfy { $0.url?.host == "www.livechart.me" })
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
        XCTAssertEqual(result.images.filter { $0.source == .liveChart }.count, 4)
        XCTAssertTrue(result.notice?.contains("Some LiveChart visuals could not load") == true)
    }
    func testUnavailableLiveChartExplainsFailureAndKeepsAniListArtwork() async throws {
        let client = AnimeVisualsClient(transport: GalleryTransport(mode: .offline), directory: nil, minimumRequestInterval: 0)
        let result = await client.gallery(for: try anime())
        XCTAssertEqual(result.images, AnimeVisualGallery.aniListImages(try anime()))
        XCTAssertNotNil(result.notice)
    }
    func testLegacyMixedGalleryCacheCannotLeakOtherSourcesIntoTheLiveChartGallery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VisualCacheMigration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = AnimeVisualsClient(transport: GalleryTransport(mode: .live), directory: directory, minimumRequestInterval: 0)
        _ = await first.gallery(for: try anime())
        let file = directory.appendingPathComponent("livechart-galleries-v2.json")
        var records = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
        records[0]["images"] = [["source": "myAnimeList", "imageURL": "https://cdn.myanimelist.net/old.jpg",
                                  "thumbnailURL": "https://cdn.myanimelist.net/old.jpg", "title": "Legacy artwork"]]
        let old = try JSONSerialization.data(withJSONObject: records)
        try old.write(to: directory.appendingPathComponent("galleries.json"))
        try old.write(to: file)
        let offline = GalleryTransport(mode: .offline)
        let second = AnimeVisualsClient(transport: offline, directory: directory, minimumRequestInterval: 0)
        let result = await second.gallery(for: try anime())
        XCTAssertEqual(result.images, AnimeVisualGallery.aniListImages(try anime()))
        XCTAssertNotNil(result.notice)
        let requests = await offline.requests
        XCTAssertFalse(requests.contains { $0.url?.host == "api.jikan.moe" })
    }
    func testDefaultPublicSessionDoesNotUseBrowserCookies() {
        let configuration = AnimeVisualsClient.publicTransport().session.configuration
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertNil(configuration.urlCredentialStorage)
    }
    func testAniListArtworkIsAvailableImmediatelyWithoutStartingNetworkWork() async throws {
        let transport = GalleryTransport(mode: .offline)
        let client = AnimeVisualsClient(transport: transport, directory: nil)
        let anime = try anime()
        let result = await client.cachedGallery(for: anime)
        XCTAssertEqual(result.images, AnimeVisualGallery.aniListImages(anime))
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }
    func testUpgradeRetriesLegacyEmptyResultsButKeepsCurrentNegativeCaching() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VisualEmptyMigration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let anime = try anime()
        let first = AnimeVisualsClient(transport: GalleryTransport(mode: .denied), directory: directory, minimumRequestInterval: 0)
        _ = await first.gallery(for: anime)
        let offline = GalleryTransport(mode: .offline)
        let current = AnimeVisualsClient(transport: offline, directory: directory, minimumRequestInterval: 0)
        _ = await current.gallery(for: anime)
        let cachedRequests = await offline.requests
        XCTAssertTrue(cachedRequests.isEmpty)
        let file = directory.appendingPathComponent("livechart-galleries-v2.json")
        var records = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
        records[0].removeValue(forKey: "checkedAt")
        records[0]["complete"] = true
        try JSONSerialization.data(withJSONObject: records).write(to: file)
        let repaired = AnimeVisualsClient(transport: GalleryTransport(mode: .live), directory: directory, minimumRequestInterval: 0)
        let result = await repaired.gallery(for: anime)
        XCTAssertEqual(result.images.filter { $0.source == .liveChart }.count, 6)
        XCTAssertNil(result.notice)
    }
    func testInterruptedPageRecoversOnceWithoutLosingPaginationOrAniList() async throws {
        let transport = GalleryTransport(mode: .interrupted)
        let client = AnimeVisualsClient(transport: transport, directory: nil, minimumRequestInterval: 0)
        let result = await client.gallery(for: try anime())
        XCTAssertEqual(result.images.filter { $0.source == .liveChart }.count, 6)
        XCTAssertEqual(result.images.filter { $0.source == .aniList }.count, 2)
        XCTAssertNil(result.notice)
        let pages = await transport.requests.filter { $0.url?.host == "www.livechart.me" }
        XCTAssertEqual(pages.count, 3)
    }
    func testStaleFailureIsRememberedAcrossScrollReturnsAndRestartWithoutExtendingArtworkAge() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VisualRetryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let anime = try anime()
        let first = AnimeVisualsClient(transport: GalleryTransport(mode: .live), directory: directory, minimumRequestInterval: 0)
        let original = await first.gallery(for: anime)
        let file = directory.appendingPathComponent("livechart-galleries-v2.json")
        var records = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
        let savedDate = Date().addingTimeInterval(-7 * 3600).timeIntervalSinceReferenceDate
        records[0]["fetchedAt"] = savedDate
        try JSONSerialization.data(withJSONObject: records).write(to: file)
        let offline = GalleryTransport(mode: .offline)
        let second = AnimeVisualsClient(transport: offline, directory: directory, minimumRequestInterval: 0)
        let failed = await second.gallery(for: anime)
        XCTAssertTrue(failed.isStale)
        XCTAssertEqual(failed.images, original.images)
        let requestsAfterFailure = await offline.requests.count
        _ = await second.gallery(for: anime)
        let third = AnimeVisualsClient(transport: offline, directory: directory, minimumRequestInterval: 0)
        let restored = await third.gallery(for: anime)
        XCTAssertTrue(restored.isStale)
        XCTAssertEqual(restored.images, original.images)
        let requestsAfterReturn = await offline.requests.count
        XCTAssertEqual(requestsAfterReturn, requestsAfterFailure)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
        XCTAssertEqual(saved[0]["fetchedAt"] as? Double, savedDate)
    }
    func testLeavingTheLastGalleryCancelsPageAndDoesNotSaveANegativeResult() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VisualCancelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = SuspendedGalleryTransport()
        let client = AnimeVisualsClient(transport: transport, directory: directory, minimumRequestInterval: 0)
        let anime = try anime()
        let loading = Task { await client.gallery(for: anime) }
        await transport.waitUntilPageStarts()
        loading.cancel()
        _ = await loading.value
        await transport.waitUntilCancelled()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("livechart-galleries-v2.json").path))
        let fresh = AnimeVisualsClient(transport: GalleryTransport(mode: .live), directory: directory, minimumRequestInterval: 0)
        let result = await fresh.gallery(for: anime)
        XCTAssertEqual(result.images.filter { $0.source == .liveChart }.count, 6)
    }
}

private actor GalleryTransport: HTTPTransport {
    enum Mode { case live, denied, conflict, offline, secondPageFails, interrupted }
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
            if mode == .interrupted && requests.filter({ $0.url?.host == "www.livechart.me" }).count == 1 {
                throw URLError(.networkConnectionLost)
            }
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

private actor SuspendedGalleryTransport: HTTPTransport {
    private var page: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var started = false
    private var cancelled = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancelWaiters: [CheckedContinuation<Void, Never>] = []
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        if url.host == "raw.githubusercontent.com" {
            return (Data("anilist\tlivechart\tmyanimelist\n178789\t12735\t59193\n".utf8),
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if cancelled { continuation.resume(throwing: CancellationError()); return }
                page = continuation; started = true
                for waiter in startWaiters { waiter.resume() }; startWaiters = []
            }
        } onCancel: { Task { await self.cancel() } }
    }
    func waitUntilPageStarts() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }
    func waitUntilCancelled() async {
        if cancelled { return }
        await withCheckedContinuation { cancelWaiters.append($0) }
    }
    private func cancel() {
        cancelled = true; page?.resume(throwing: CancellationError()); page = nil
        for waiter in cancelWaiters { waiter.resume() }; cancelWaiters = []
    }
}
