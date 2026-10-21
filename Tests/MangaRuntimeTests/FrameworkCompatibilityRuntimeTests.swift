import XCTest
import UIKit
import AnimeCore
@testable import AnimeCompanion

final class FrameworkCompatibilityRuntimeTests: XCTestCase {
    private let bytes = Data([0, 255, 23, 128])
    private func fixture(_ name: String) throws -> Data {
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "OwnedFixtures", withExtension: nil))
        return try Data(contentsOf: root.appendingPathComponent(name))
    }
    private func execute<T: Decodable>(_ host: OwnedExtensionFixtureHTTP, id: String, settings: [String: String], _ input: [String: Any]) throws -> T {
        var command = input
        command["settingsSourceID"] = id
        command["settings"] = settings.mapValues { ["type": "string", "value": $0] }
        return try host.execute(command)
    }
    private struct ImagePayload: Decodable { let bodyBase64: String }
    private func flow(catalogHost: OwnedExtensionFixtureHTTP, bookHost: OwnedExtensionFixtureHTTP, readerHost: OwnedExtensionFixtureHTTP, id: String, settings: [String: String], expectedImages: [String]) throws {
        let catalog: SourceMangaPage = try execute(catalogHost, id: id, settings: settings, ["op": "popular"])
        let manga = try XCTUnwrap(catalog.mangas.first)
        XCTAssertEqual(manga.title, "Owned story")
        let book: MangaBook = try execute(bookHost, id: id, settings: settings, ["op": "book", "manga": ["url": manga.url, "title": manga.title]])
        let chapter = try XCTUnwrap(book.chapters.first)
        XCTAssertEqual(chapter.uploadedAt, 1_709_164_800_000)
        let pages: [SourceMangaImage] = try execute(readerHost, id: id, settings: settings, ["op": "pages", "chapter": MangaRuntime.chapterInput(chapter)])
        XCTAssertEqual(pages.map(\.imageURL), expectedImages)
        let page = try XCTUnwrap(pages.first)
        let image: ImagePayload = try execute(readerHost, id: id, settings: settings, ["op": "image", "image": ["index": page.index, "url": page.url, "imageURL": page.imageURL]])
        XCTAssertEqual(Data(base64Encoded: image.bodyBase64), bytes)
    }
    func testLANraragiConfiguredServerAndCompleteReaderThroughTheNativeBridge() throws {
        let archive = "1111111111111111111111111111111111111111"
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-all.lanraragi-v1.6.1.apk", responses: [
            "https://library.example/api/search": try fixture("lanraragi-catalog.json"),
            "https://library.example/api/archives/\(archive)/metadata": try fixture("lanraragi-book.json"),
            "https://library.example/api/archives/\(archive)/files": try fixture("lanraragi-pages.json"),
            "https://library.example/owned-page-2.webp": bytes
        ])
        try flow(catalogHost: host, bookHost: host, readerHost: host, id: "4482480338677079857",
                 settings: ["hostname": "https://library.example", "apiKey": "owned-key"],
                 expectedImages: ["https://library.example/owned-page-2.webp", "https://library.example/owned-page-1.webp"])
    }
    func testMangoKeepsTheSavedURLAndAuthenticatesEachFreshRuntime() throws {
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-all.mango-v1.6.0.apk", responses: [
            "https://library.example/login": Data(),
            "https://library.example/api/library": try fixture("mango-catalog.json"),
            "https://library.example/api/book/owned": try fixture("mango-book.json"),
            "https://library.example/api/page/owned/chapter2/1": bytes
        ], responseHeaders: [["Set-Cookie", "mango-sessid-9000=owned"]])
        try flow(catalogHost: host, bookHost: host, readerHost: host, id: "2882993841250976719",
                 settings: ["overrideBaseUrl": "https://library.example", "Username": "owned-user", "Password": "owned-password"],
                 expectedImages: ["https://library.example/api/page/owned/chapter2/1", "https://library.example/api/page/owned/chapter2/2"])
        XCTAssertEqual(host.urls.filter { $0 == "https://library.example/login" }.count, 3)
        XCTAssertEqual(host.bodiesByURL["https://library.example/login"], Data("username=owned-user&password=owned-password".utf8))
        XCTAssertTrue(host.urls.allSatisfy { $0.hasPrefix("https://library.example/") })
    }
    func testStashAppEnumGraphQLAndCompleteReaderThroughTheNativeBridge() throws {
        let apk = "tachiyomi-all.stashapp-v1.6.0.apk", api = "https://library.example/graphql"
        let catalogHost = try OwnedExtensionFixtureHTTP(apkName: apk, responses: [api: try fixture("stash-catalog.json")])
        let bookHost = try OwnedExtensionFixtureHTTP(apkName: apk, responses: [api: try fixture("stash-book.json")])
        let readerHost = try OwnedExtensionFixtureHTTP(apkName: apk, responses: [
            api: try fixture("stash-pages.json"), "https://library.example/image/2/image": bytes
        ])
        try flow(catalogHost: catalogHost, bookHost: bookHost, readerHost: readerHost, id: "4332882684116196542",
                 settings: ["overrideBaseUrl": "https://library.example", "api_key": "owned-key"],
                 expectedImages: ["https://library.example/image/2/image", "https://library.example/image/1/image"])
        let body = try XCTUnwrap(catalogHost.bodiesByURL[api])
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let variables = try XCTUnwrap(request["variables"] as? [String: Any])
        let filter = try XCTUnwrap(variables["filter"] as? [String: Any])
        XCTAssertEqual(filter["direction"] as? String, "DESC")
    }
    func testKomgaCoroutineContextTypedSetsReflectionAndCompleteReader() throws {
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-all.komga-v1.6.74.apk", responses: [
            "https://library.example/api/v1/series": try fixture("komga-catalog.json"),
            "https://library.example/api/v1/series/owned": try fixture("komga-series.json"),
            "https://library.example/api/v1/series/owned/books": try fixture("komga-books.json"),
            "https://library.example/api/v1/books/chapter2/pages": try fixture("komga-pages.json"),
            "https://library.example/api/v1/books/chapter2/pages/2": bytes
        ])
        let settings = ["Address": "https://library.example", "API key": "owned-key"]
        let id = "4508733312114627536"
        try flow(catalogHost: host, bookHost: host, readerHost: host, id: id, settings: settings,
                 expectedImages: ["https://library.example/api/v1/books/chapter2/pages/2", "https://library.example/api/v1/books/chapter2/pages/1?convert=png"])
        let book: MangaBook = try execute(host, id: id, settings: settings, ["op": "book", "timeZoneID": "UTC", "manga": ["url": "https://library.example/api/v1/series/owned", "title": "Owned story"]])
        XCTAssertEqual(book.chapters.last?.uploadedAt, -86_400_000)
        XCTAssertTrue(host.headersByURL.values.allSatisfy { headers in
            headers.contains { $0.count == 2 && $0[0].lowercased() == "x-api-key" && $0[1] == "owned-key" }
        })
    }
    func testJinmanTypedArraySettingsAndUnscrambledReadingFlow() throws {
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-zh.jinmantiantang-v1.6.59.apk", responses: [
            "https://18comic.vip/albums": try fixture("jinman-catalog.html"),
            "https://18comic.vip/album/1/": try fixture("jinman-book.html"),
            "https://18comic.vip/photo/1/": try fixture("jinman-pages.html"),
            "https://images.example/media/photos/1/owned-page-2.webp": bytes
        ])
        let schema: SettingsSchema = try host.execute(["op": "settings"])
        let mirror = try XCTUnwrap(schema.settings.first { $0.key == "useMirrorWebsitePreference" })
        XCTAssertEqual(mirror.control, "choice")
        XCTAssertEqual(mirror.choices.count, 7)
        XCTAssertTrue(host.urls.isEmpty)
        try flow(catalogHost: host, bookHost: host, readerHost: host, id: "6286738698187452081", settings: [:],
                 expectedImages: ["https://images.example/media/photos/1/owned-page-2.webp", "https://images.example/media/photos/1/owned-page-1.webp"])
    }
    private func pixel(_ image: CGImage, y: Int) throws -> [UInt8] {
        let sample = try XCTUnwrap(image.cropping(to: CGRect(x: 16, y: y, width: 1, height: 1)))
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { storage in
            let context = try XCTUnwrap(CGContext(data: storage.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return rgba
    }
    func testJinmanScrambledCodecsAndGzipRestoreStripPixelsThroughNativeBridge() throws {
        let url = "https://images.example/media/photos/260000/owned.webp"
        for name in ["owned-bands.png", "owned-bands.jpg", "owned-bands.webp", "owned-bands.webp.gz"] {
            let compressed = name.hasSuffix(".gz")
            let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-zh.jinmantiantang-v1.6.59.apk",
                responses: [url: try fixture(name)], responseHeaders: compressed ? [["Content-Encoding", "gzip"]] : [])
            let payload: ImagePayload = try host.execute(["op": "image", "image": ["index": 0, "url": "", "imageURL": url]])
            let data = try XCTUnwrap(Data(base64Encoded: payload.bodyBase64))
            XCTAssertEqual(Array(data.prefix(2)), [255, 216], name)
            let output = try XCTUnwrap(UIImage(data: data)?.cgImage)
            let originalName = compressed ? "owned-bands.webp" : name
            let original = try XCTUnwrap(UIImage(data: fixture(originalName))?.cgImage)
            XCTAssertEqual(output.width, 32)
            XCTAssertEqual(output.height, 163)
            var outputY = 0
            for (index, sourceY) in [144, 128, 112, 96, 80, 64, 48, 32, 16, 0].enumerated() {
                let height = index == 0 ? 19 : 16
                let expected = try pixel(original, y: sourceY + height / 2)
                let actual = try pixel(output, y: outputY + height / 2)
                for channel in 0..<3 {
                    XCTAssertLessThanOrEqual(abs(Int(expected[channel]) - Int(actual[channel])), 25, "\(name), strip \(index)")
                }
                outputY += height
            }
        }
    }
    func testJinmanModernGifAndGzippedGifPreserveEveryAnimationByte() throws {
        let url = "https://images.example/media/photos/300000/owned.webp"
        let expected = try fixture("owned-animation.gif")
        for name in ["owned-animation.gif", "owned-animation.gif.gz"] {
            let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-zh.jinmantiantang-v1.6.59.apk",
                responses: [url: try fixture(name)], responseHeaders: name.hasSuffix(".gz") ? [["Content-Encoding", "gzip"]] : [])
            let payload: ImagePayload = try host.execute(["op": "image", "image": ["index": 0, "url": "", "imageURL": url]])
            XCTAssertEqual(Data(base64Encoded: payload.bodyBase64), expected, name)
        }
    }
    private struct SettingsSchema: Decodable { let settings: [Setting] }
    private struct Setting: Decodable { let key: String; let control: String; let choices: [Choice] }
    private struct Choice: Decodable { let value: String }
}
