import XCTest
import AnimeCore
@testable import AnimeCompanion

final class NetworkCompatibilityRuntimeTests: XCTestCase {
    private let bytes = Data([0, 255, 23, 128])
    private func fixture(_ name: String) throws -> Data {
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "OwnedFixtures", withExtension: nil))
        return try Data(contentsOf: root.appendingPathComponent(name))
    }

    func testDigitalComicMuseumMultipartBytesAndLazyReaderThroughTheNativeBridge() throws {
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-en.digitalcomicmuseum-v1.6.0.apk", responses: [
            "https://digitalcomicmuseum.com/stats.php": try fixture("dcm-catalog.html"),
            "https://digitalcomicmuseum.com/index.php": try fixture("dcm-catalog.html"),
            "https://digitalcomicmuseum.com/owned-book": try fixture("dcm-book.html"),
            "https://digitalcomicmuseum.com/read/owned": try fixture("dcm-pages.html"),
            "https://digitalcomicmuseum.com/read/owned/2": try fixture("dcm-image.html"),
            "https://images.example/owned-page-2.webp": bytes
        ])
        let search: SourceMangaPage = try host.execute(["op": "search", "query": "Owned café + story"])
        XCTAssertEqual(search.mangas.first?.title, "Owned story")
        let requestURL = "https://digitalcomicmuseum.com/index.php?ACT=dosearch"
        XCTAssertEqual(host.methodsByURL[requestURL], "POST")
        let body = try XCTUnwrap(host.bodiesByURL[requestURL])
        let headers = try XCTUnwrap(host.headersByURL[requestURL])
        let media = try XCTUnwrap(headers.first(where: { $0.count == 2 && $0[0].lowercased() == "content-type" })?.last)
        let boundary = try XCTUnwrap(media.components(separatedBy: "boundary=").last)
        let expected = "--\(boundary)\r\nContent-Disposition: form-data; name=\"terms\"\r\nContent-Length: \("Owned café + story".utf8.count)\r\n\r\nOwned café + story\r\n--\(boundary)--\r\n"
        XCTAssertEqual(body, Data(expected.utf8))
        let catalog: SourceMangaPage = try host.execute(["op": "popular"])
        let manga = try XCTUnwrap(catalog.mangas.first)
        let book: MangaBook = try host.execute(["op": "book", "manga": ["url": manga.url, "title": manga.title]])
        XCTAssertEqual(book.manga.description, "Owned description")
        let chapter = try XCTUnwrap(book.chapters.first)
        let pages: [SourceMangaImage] = try host.execute(["op": "pages", "chapter": MangaRuntime.chapterInput(chapter)])
        XCTAssertEqual(pages.map(\.url), ["https://digitalcomicmuseum.com/read/owned/2", "https://digitalcomicmuseum.com/read/owned/1"])
        XCTAssertEqual(pages.first?.imageURL, "")
        try assertImage(try XCTUnwrap(pages.first), host: host)
    }

    func testRawkumaNonceMultipartDTOsAndReaderThroughTheNativeBridge() throws {
        let book = try fixture("natsuid-book.json")
        let listing = Data("[".utf8) + book + Data("]".utf8)
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-ja.rawkuma-v1.6.41.apk", responses: [
            "https://rawkuma.net/wp-admin/admin-ajax.php?type=search_form&action=get_nonce": try fixture("natsuid-nonce.html"),
            "https://rawkuma.net/wp-admin/admin-ajax.php?action=advanced_search": try fixture("natsuid-catalog.html"),
            "https://rawkuma.net/wp-json/wp/v2/manga": listing,
            "https://rawkuma.net/wp-json/wp/v2/manga/42": book,
            "https://rawkuma.net/wp-admin/admin-ajax.php": try fixture("natsuid-chapters.html"),
            "https://rawkuma.net/read/owned/2": try fixture("natsuid-pages.html"),
            "https://images.example/owned-page-2.webp": bytes
        ])
        let catalog: SourceMangaPage = try host.execute(["op": "popular"])
        let manga = try XCTUnwrap(catalog.mangas.first)
        XCTAssertEqual(manga.title, "Owned story")
        let result: MangaBook = try host.execute(["op": "book", "manga": ["url": manga.url, "title": manga.title]])
        XCTAssertEqual(result.manga.author, "Owned author")
        XCTAssertEqual(result.chapters.first?.uploadedAt, 1_725_062_400_000)
        try assertReader(try XCTUnwrap(result.chapters.first), host: host)
    }

    func testManhuawuHeaderFactoriesAndImageRequestThroughTheNativeBridge() throws {
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-zh.manhuawu-v1.6.0.apk", responses: [
            "https://www.mhua5.com/category/order/hits/page/1": try fixture("mccms-catalog.html"),
            "https://www.mhua5.com/comic/owned": try fixture("mccms-book.html"),
            "https://www.mhua5.com/read/owned/2": try fixture("mccms-pages.html"),
            "https://images.example/owned-page-2.webp": bytes
        ])
        let catalog: SourceMangaPage = try host.execute(["op": "popular"])
        let manga = try XCTUnwrap(catalog.mangas.first)
        let book: MangaBook = try host.execute(["op": "book", "manga": ["url": manga.url, "title": manga.title]])
        XCTAssertEqual(book.manga.author, "Owned author")
        XCTAssertEqual(book.chapters.first?.name, "Chapter 2")
        try assertReader(try XCTUnwrap(book.chapters.first), host: host)
    }

    private func assertReader(_ chapter: SourceMangaChapter, host: OwnedExtensionFixtureHTTP) throws {
        let pages: [SourceMangaImage] = try host.execute(["op": "pages", "chapter": MangaRuntime.chapterInput(chapter)])
        XCTAssertEqual(pages.map(\.imageURL), ["https://images.example/owned-page-2.webp", "https://images.example/owned-page-1.webp"])
        try assertImage(try XCTUnwrap(pages.first), host: host)
    }
    private func assertImage(_ page: SourceMangaImage, host: OwnedExtensionFixtureHTTP) throws {
        let result: ImageBytes = try host.execute(["op": "image", "httpUserAgent": "Owned native agent", "image": ["index": page.index, "url": page.url, "imageURL": page.imageURL]])
        XCTAssertEqual(Data(base64Encoded: result.bodyBase64), bytes)
    }
    private struct ImageBytes: Decodable { let bodyBase64: String }
}
