import XCTest
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
}
