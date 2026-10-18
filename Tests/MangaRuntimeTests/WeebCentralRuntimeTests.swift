import XCTest
import AnimeCore
import AnimeMangaRuntime

final class WeebCentralRuntimeTests: XCTestCase {
    func testDatedChaptersAndLongStripRequestsThroughTheNativeBridge() throws {
        let host = try WeebCentralFixtureHTTP()
        let book: MangaBook = try host.execute(bookCommand)
        XCTAssertEqual(book.manga.title, "Owned webtoon")
        XCTAssertEqual(book.manga.author, "Owned author")
        XCTAssertEqual(book.manga.status, 1)
        XCTAssertEqual(book.chapters.count, 2)
        let newest = try XCTUnwrap(book.chapters.first)
        XCTAssertEqual(newest.uploadedAt, 1_790_857_800_000)
        XCTAssertEqual(newest.scanlator, "Official")
        let order = MangaChapterSequence.readingOrder(book.chapters)
        XCTAssertEqual(order.map(\.name), ["Chapter 1", "Chapter 2"])

        let pages: [SourceMangaImage] = try host.execute([
            "op": "pages", "chapter": ["url": newest.url, "name": newest.name]
        ])
        XCTAssertEqual(pages.map(\.imageURL), ["https://images.example/owned-1.webp", "https://images.example/owned-2.webp"])
        XCTAssertTrue(host.urls.contains("https://weebcentral.com/chapters/owned-2/images?is_prev=False&reading_style=long_strip"))
        let first = try XCTUnwrap(pages.first)
        let image: ImageResponse = try host.execute([
            "op": "image", "image": ["index": first.index, "url": first.url, "imageURL": first.imageURL]
        ])
        XCTAssertEqual(Data(base64Encoded: image.bodyBase64), Data([0, 255, 23, 128]))
    }

    func testFailedChapterTaskReturnsAnErrorInsteadOfAnEmptyBook() throws {
        let host = try WeebCentralFixtureHTTP()
        host.failChapters = true
        XCTAssertThrowsError(try host.execute(bookCommand) as MangaBook) { error in
            XCTAssertTrue(error.localizedDescription.contains("503"), "The underlying task failure must survive await")
        }
        host.failChapters = false
        let retried: MangaBook = try host.execute(bookCommand)
        XCTAssertEqual(retried.chapters.count, 2)
    }

    private var bookCommand: [String: Any] {
        ["op": "book", "manga": ["url": "/series/owned-id/owned-webtoon", "title": "Owned webtoon"]]
    }
    private struct ImageResponse: Decodable { let bodyBase64: String }
}

/// Test-bundle-only networking: the real APK runs against the same owned HTML
/// as the Rust regressions. No fixture response can reach a production request.
private final class WeebCentralFixtureHTTP {
    let apk: Data
    let responses: [String: Data]
    var failChapters = false
    var urls: [String] = []

    init() throws {
        let bundle = Bundle(for: WeebCentralRuntimeTests.self)
        let apks = try XCTUnwrap(bundle.url(forResource: "Fixtures", withExtension: nil))
        apk = try Data(contentsOf: apks.appendingPathComponent("tachiyomi-en.weebcentral-v1.6.25.apk"))
        let html = try XCTUnwrap(bundle.url(forResource: "OwnedFixtures", withExtension: nil))
        responses = try [
            "https://weebcentral.com/series/owned-id/owned-webtoon": Data(contentsOf: html.appendingPathComponent("weebcentral-details.html")),
            "https://weebcentral.com/series/owned-id/full-chapter-list": Data(contentsOf: html.appendingPathComponent("weebcentral-chapters.html")),
            "https://weebcentral.com/chapters/owned-2/images?is_prev=False&reading_style=long_strip": Data(contentsOf: html.appendingPathComponent("weebcentral-pages.html")),
            "https://images.example/owned-1.webp": Data([0, 255, 23, 128])
        ]
    }

    func execute<T: Decodable>(_ input: [String: Any]) throws -> T {
        var command = input; command["modern"] = true
        let json = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: command), encoding: .utf8))
        let result = try apk.withUnsafeBytes { bytes in
            try json.withCString { command -> Data in
                let pointer = try XCTUnwrap(ac_manga_execute(bytes.bindMemory(to: UInt8.self).baseAddress, apk.count,
                    command, weebCentralFixtureRequest, weebCentralFixtureRelease, Unmanaged.passUnretained(self).toOpaque()))
                defer { ac_manga_free_string(pointer) }
                return Data(bytes: pointer, count: strlen(pointer))
            }
        }
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: result)
        guard envelope.ok, let data = envelope.data else {
            throw NSError(domain: "OwnedMangaFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: envelope.error ?? "Missing result"])
        }
        return data
    }

    func request(_ input: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>? {
        guard let request = try? JSONDecoder().decode(Request.self, from: Data(bytes: input, count: strlen(input))) else { return nil }
        urls.append(request.url)
        let failure = failChapters && request.url.hasSuffix("full-chapter-list")
        let body = failure ? Data("unavailable".utf8) : responses[request.url]
        let code = failure ? 503 : (body == nil ? 404 : 200)
        let response: [String: Any] = ["code": code, "headers": [], "bodyBase64": (body ?? Data()).base64EncodedString()]
        guard let data = try? JSONSerialization.data(withJSONObject: response), let json = String(data: data, encoding: .utf8) else { return nil }
        return strdup(json)
    }
    private struct Request: Decodable { let url: String }
    private struct Envelope<T: Decodable>: Decodable { let ok: Bool; let data: T?; let error: String? }
}

private let weebCentralFixtureRequest: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? = { context, input in
    guard let context, let input else { return nil }
    return Unmanaged<WeebCentralFixtureHTTP>.fromOpaque(context).takeUnretainedValue().request(input)
}
private let weebCentralFixtureRelease: @convention(c) (UnsafeMutablePointer<CChar>?) -> Void = { free($0) }
