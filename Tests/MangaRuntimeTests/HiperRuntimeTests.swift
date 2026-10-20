import XCTest
import AnimeCore
import AnimeMangaRuntime
@testable import AnimeCompanion

final class HiperRuntimeTests: XCTestCase {
    func testFractionalChapterRPCDoesNotExpandFloatRoundingError() throws {
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "OwnedFixtures", withExtension: nil))
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-en.hiperdex-v1.6.89.apk", responses: [
            "https://hiperdex.tv/api/trpc/auth.me,series.bySlug,reader.chapterPages": Data(contentsOf: root.appendingPathComponent("hiper-pages.json"))
        ])
        let chapter = SourceMangaChapter(url: "/manga/owned/1.1", name: "Chapter 1.1", chapterNumber: 1.1)
        let pages: [SourceMangaImage] = try host.execute(["op": "pages", "chapter": MangaRuntime.chapterInput(chapter)])
        XCTAssertEqual(pages.count, 2)
        let request = try XCTUnwrap(host.urls.last.flatMap { URLComponents(string: $0) })
        let input = try XCTUnwrap(request.queryItems?.first { $0.name == "input" }?.value)
        let rpc = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: [String: Any]])
        let json = try XCTUnwrap(rpc["2"]?["json"] as? [String: Any])
        XCTAssertEqual(json["chapterNumber"] as? Double, 1.1)
    }
    func testHiperCatalogBookAndDuplicateChapterSurviveTheNativeBridge() throws {
        let bundle = Bundle(for: Self.self)
        let root = try XCTUnwrap(bundle.url(forResource: "OwnedFixtures", withExtension: nil))
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-en.hiperdex-v1.6.89.apk", responses: [
            "https://hiperdex.tv/api/trpc/search.query": Data(contentsOf: root.appendingPathComponent("hiper-catalog.json")),
            "https://hiperdex.tv/api/trpc/auth.me,series.bySlugWithGenres": Data(contentsOf: root.appendingPathComponent("hiper-details.json")),
            "https://hiperdex.tv/api/trpc/auth.me,series.chapters": Data(contentsOf: root.appendingPathComponent("hiper-chapters.json")),
            "https://hiperdex.tv/api/trpc/auth.me,series.bySlug,reader.chapterPages": Data(contentsOf: root.appendingPathComponent("hiper-pages.json"))
        ])
        let page: SourceMangaPage = try host.execute(["op": "popular"])
        XCTAssertEqual(page.mangas.first?.title, "Owned story")
        XCTAssertEqual(page.mangas.first?.thumbnailURL, "https://images.example/owned-cover.webp")
        let book: MangaBook = try host.execute(["op": "book", "manga": ["url": "manga/owned", "title": "Owned story"]])
        XCTAssertEqual(book.chapters.count, 2)
        let chapter = try XCTUnwrap(book.chapters.last)
        XCTAssertEqual(chapter.chapterNumber, 2.5)
        XCTAssertEqual(chapter.uploadedAt, 1_790_942_400_000)
        let saved = try JSONDecoder().decode(SourceMangaChapter.self, from: JSONEncoder().encode(chapter))
        let pages: [SourceMangaImage] = try host.execute(["op": "pages", "chapter": MangaRuntime.chapterInput(saved)])
        XCTAssertEqual(pages.map(\.imageURL), ["https://images.example/owned-1.webp", "https://images.example/owned-2.avif"])
        let request = try XCTUnwrap(host.urls.last.flatMap { URLComponents(string: $0) })
        let input = try XCTUnwrap(request.queryItems?.first { $0.name == "input" }?.value)
        let rpc = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: [String: Any]])
        let json = try XCTUnwrap(rpc["2"]?["json"] as? [String: Any])
        XCTAssertEqual(json["chapterNumber"] as? Double, 2.5)
        XCTAssertEqual(json["chapterId"] as? Int64, 9_000_000_000_002)
    }

    func testHiperRecoversPageHeadersThroughRealWebKitAndRetriesItsOwnRequest() async throws {
        let key = "owned-hiper-" + UUID().uuidString
        let host = try HiperBrowserFixtureHTTP(sourceKey: key)
        let pages = try await host.pages()
        XCTAssertEqual(pages.count, 2)
        XCTAssertGreaterThan(host.browserCalls, 0)
        XCTAssertEqual(host.pageCalls, 2)
        XCTAssertEqual(host.htmlCalls, 1)
        XCTAssertTrue(host.retriedWithCapturedHeader)
        host.browser.finish()
        await MainActor.run { MangaWebsiteProfiles.stores[key] = nil }
    }

    func testNamiComiConfiguredAndSealedSerializersReturnCoversAndAuthors() throws {
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "OwnedFixtures", withExtension: nil))
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-all.namicomi-v1.6.0.apk", responses: [
            "https://api.namicomi.com/title/search": Data(contentsOf: root.appendingPathComponent("namicomi-catalog.json"))
        ])
        let page: SourceMangaPage = try host.execute(["op": "popular"])
        XCTAssertEqual(page.mangas.first?.title, "Owned story")
        XCTAssertEqual(page.mangas.first?.author, "Owned author")
        XCTAssertTrue(page.mangas.first?.thumbnailURL.contains("owned.webp") == true)
        XCTAssertFalse(page.hasNext)
    }
}

// Actual APK + WKWebView; only HTTP responses and the document are owned data.
private final class HiperBrowserFixtureHTTP: @unchecked Sendable {
    let apk: Data
    let response: Data
    let document: Data
    let browser: MangaRuntimeBrowser
    var browserCalls = 0, pageCalls = 0, htmlCalls = 0
    var retriedWithCapturedHeader = false
    init(sourceKey: String) throws {
        let bundle = Bundle(for: HiperRuntimeTests.self)
        let apks = try XCTUnwrap(bundle.url(forResource: "Fixtures", withExtension: nil))
        let fixtures = try XCTUnwrap(bundle.url(forResource: "OwnedFixtures", withExtension: nil))
        apk = try Data(contentsOf: apks.appendingPathComponent("tachiyomi-en.hiperdex-v1.6.89.apk"))
        response = try Data(contentsOf: fixtures.appendingPathComponent("hiper-pages.json"))
        document = try Data(contentsOf: fixtures.appendingPathComponent("hiper-session.html"))
        browser = MangaRuntimeBrowser(sourceKey: sourceKey)
    }
    func pages() async throws -> [SourceMangaImage] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                defer { self.browser.finish() }
                do {
                    let input = "{\"op\":\"pages\",\"modern\":true,\"chapter\":{\"url\":\"/manga/owned/2.5\",\"name\":\"Chapter 2.5\",\"chapterNumber\":2.5}}"
                    let data = try self.apk.withUnsafeBytes { bytes in
                        try input.withCString { command -> Data in
                            let pointer = try XCTUnwrap(ac_manga_execute(bytes.bindMemory(to: UInt8.self).baseAddress, self.apk.count, command, hiperFixtureRequest, hiperFixtureRelease, Unmanaged.passUnretained(self).toOpaque()))
                            defer { ac_manga_free_string(pointer) }
                            return Data(bytes: pointer, count: strlen(pointer))
                        }
                    }
                    let envelope = try JSONDecoder().decode(Envelope.self, from: data)
                    guard envelope.ok, let pages = envelope.data else { throw NSError(domain: "OwnedHiper", code: 1, userInfo: [NSLocalizedDescriptionKey: envelope.error ?? "Missing pages"]) }
                    continuation.resume(returning: pages)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func request(_ input: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>? {
        do {
            let request = try JSONDecoder().decode(Request.self, from: Data(bytes: input, count: strlen(input)))
            let body: Data
            if request.method == "AC_BROWSER", let payload = request.body {
                browserCalls += 1; body = try browser.request(Data(payload.utf8), remaining: 20)
            } else if request.url.contains("reader.chapterPages?") {
                pageCalls += 1
                if pageCalls == 1 { body = Data("[{\"error\":{\"message\":\"Owned session refresh required\"}}]".utf8) }
                else {
                    retriedWithCapturedHeader = request.headers.contains { $0.count == 2 && $0[0].lowercased() == "x-owned-session" && $0[1] == "owned-session" }
                    body = response
                }
            } else if request.url == "https://hiperdex.tv/manga/owned/2.5" {
                htmlCalls += 1
                body = document
            } else { throw URLError(.badURL) }
            let result: [String: Any] = ["code": 200, "headers": [], "bodyBase64": body.base64EncodedString()]
            let encoded = try JSONSerialization.data(withJSONObject: result)
            return String(decoding: encoded, as: UTF8.self).withCString { strdup($0) }
        } catch { return strdup("{\"code\":599,\"headers\":[],\"bodyBase64\":\"\"}") }
    }
    private struct Request: Decodable { let url: String; let method: String; let headers: [[String]]; let body: String? }
    private struct Envelope: Decodable { let ok: Bool; let data: [SourceMangaImage]?; let error: String? }
}
private let hiperFixtureRequest: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? = { context, input in
    guard let context, let input else { return nil }
    return Unmanaged<HiperBrowserFixtureHTTP>.fromOpaque(context).takeUnretainedValue().request(input)
}
private let hiperFixtureRelease: @convention(c) (UnsafeMutablePointer<CChar>?) -> Void = { free($0) }
