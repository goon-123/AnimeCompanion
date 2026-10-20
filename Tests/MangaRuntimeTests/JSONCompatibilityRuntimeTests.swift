import XCTest
import AnimeCore
@testable import AnimeCompanion

final class JSONCompatibilityRuntimeTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "OwnedFixtures", withExtension: nil))
        return try Data(contentsOf: root.appendingPathComponent(name))
    }

    func testFlameGenericDTOsAndOrderedReaderPagesThroughTheNativeBridge() throws {
        let bytes = Data([0, 255, 23, 128])
        let home = try fixture("flame-home.html")
        let pageURL = "https://cdn.flamecomics.xyz/uploads/images/series/42/owned-token/owned-page-2.webp?1792300000"
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-en.flamecomics-v1.6.1.apk", responses: [
            "https://flamecomics.xyz": home,
            "https://flamecomics.xyz/": home,
            "https://flamecomics.xyz/_next/data/owned-build/browse.json": try fixture("flame-catalog.json"),
            "https://flamecomics.xyz/_next/data/owned-build/series/42.json": try fixture("flame-book.json"),
            "https://flamecomics.xyz/_next/data/owned-build/series/42/owned-token.json": try fixture("flame-pages.json"),
            pageURL: bytes
        ])
        let catalog: SourceMangaPage = try host.execute(["op": "popular"])
        let manga = try XCTUnwrap(catalog.mangas.first)
        XCTAssertEqual(manga.title, "Owned story")
        XCTAssertEqual(manga.url, "/series/42")
        let book: MangaBook = try host.execute(["op": "book", "manga": ["url": manga.url, "title": manga.title]])
        XCTAssertEqual(book.manga.author, "Owned author")
        let chapter = try XCTUnwrap(book.chapters.first)
        XCTAssertEqual(chapter.chapterNumber, 1.5)
        XCTAssertEqual(chapter.uploadedAt, 1_792_300_000_000)
        let saved = try JSONDecoder().decode(SourceMangaChapter.self, from: JSONEncoder().encode(chapter))
        let pages: [SourceMangaImage] = try host.execute(["op": "pages", "chapter": MangaRuntime.chapterInput(saved)])
        XCTAssertEqual(pages.map(\.imageURL), [pageURL, pageURL.replacingOccurrences(of: "page-2", with: "page-1")])
        let first = try XCTUnwrap(pages.first)
        let image: ImageBytes = try host.execute(["op": "image", "image": ["index": first.index, "url": first.url, "imageURL": first.imageURL]])
        XCTAssertEqual(Data(base64Encoded: image.bodyBase64), bytes)
    }

    func testAllMangaJSONElementAndNestedBooleanMapEncodingThroughTheNativeBridge() throws {
        let catalogHost = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-en.allanime-v1.6.29.apk", responses: [
            "https://api.mkissa.net/api": try fixture("allmanga-catalog.json")
        ])
        let catalog: SourceMangaPage = try catalogHost.execute(["op": "popular"])
        let manga = try XCTUnwrap(catalog.mangas.first)
        XCTAssertEqual(manga.title, "Owned story")
        let bookHost = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-en.allanime-v1.6.29.apk", responses: [
            "https://api.mkissa.net/api": try fixture("allmanga-book.json")
        ])
        let book: MangaBook = try bookHost.execute(["op": "book", "manga": ["url": manga.url, "title": manga.title]])
        XCTAssertEqual(book.manga.author, "Owned author")
        let chapter = try XCTUnwrap(book.chapters.first)
        XCTAssertEqual(chapter.url, "1.5")
        XCTAssertEqual(chapter.uploadedAt, 1_792_281_600_000)
        let memo = try XCTUnwrap(chapter.memo)
        let value = try JSONSerialization.jsonObject(with: Data(memo.utf8)) as? [String: String]
        XCTAssertEqual(value?["mangaId"], "owned")
    }

    private struct ImageBytes: Decodable { let bodyBase64: String }
}
