import XCTest
import AnimeCore
@testable import AnimeCompanion

final class KotlinCompatibilityRuntimeTests: XCTestCase {
    private let bytes = Data([0, 255, 23, 128])

    private func fixture(_ name: String) throws -> Data {
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "OwnedFixtures", withExtension: nil))
        return try Data(contentsOf: root.appendingPathComponent(name))
    }

    func testFuryoFrenchChapterDatesAndReaderThroughTheNativeBridge() throws {
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-fr.furyosquad-v1.6.0.apk", responses: [
            "https://www.furyosociety.com/mangas": try fixture("furyo-catalog.html"),
            "https://www.furyosociety.com/series/owned/": try fixture("furyo-book.html"),
            "https://www.furyosociety.com/read/owned/2": try fixture("furyo-pages.html"),
            "https://images.example/owned-page-2.webp": bytes
        ])
        let catalog: SourceMangaPage = try host.execute(["op": "popular"])
        let manga = try XCTUnwrap(catalog.mangas.first)
        XCTAssertEqual(manga.title, "Owned story")
        let book: MangaBook = try host.execute(["op": "book", "timeZoneID": "UTC", "manga": ["url": manga.url, "title": manga.title]])
        XCTAssertEqual(book.manga.author, "Owned author")
        XCTAssertEqual(book.manga.artist, "Owned artist")
        XCTAssertEqual(book.chapters.map(\.uploadedAt), [1_725_062_400_000, 1_709_164_800_000])
        try assertReader(try XCTUnwrap(book.chapters.first), host: host)
    }

    func testMangaHubRandomKeyAndPlainMetadataReaderThroughTheNativeBridge() throws {
        let apk = "tachiyomi-en.mangafoxfun-v1.6.38.apk"
        let api = "https://api.mghcdn.com/graphql"
        let catalogHost = try OwnedExtensionFixtureHTTP(apkName: apk, responses: [api: try fixture("mangahub-catalog.json")])
        let catalog: SourceMangaPage = try catalogHost.execute(["op": "popular"])
        let manga = try XCTUnwrap(catalog.mangas.first)
        XCTAssertEqual(manga.title, "Owned story")
        let headers = try XCTUnwrap(catalogHost.headersByURL[api])
        let key = try XCTUnwrap(headers.first(where: { $0.count == 2 && $0[0].lowercased() == "x-mhub-access" })?.last)
        XCTAssertEqual(key.count, 32)
        XCTAssertTrue(key.allSatisfy(\.isHexDigit))
        let bookHost = try OwnedExtensionFixtureHTTP(apkName: apk, responses: [api: try fixture("mangahub-book.json")])
        let book: MangaBook = try bookHost.execute(["op": "book", "manga": ["url": manga.url, "title": manga.title]])
        XCTAssertEqual(book.manga.author, "Owned author")
        let chapter = try XCTUnwrap(book.chapters.first)
        XCTAssertEqual(chapter.chapterNumber, 1.5)
        XCTAssertEqual(chapter.uploadedAt, 1_709_164_800_000)
        let readerHost = try OwnedExtensionFixtureHTTP(apkName: apk, responses: [
            api: try fixture("mangahub-pages.json"),
            "https://images.example/owned-page-2.webp": bytes
        ])
        try assertReader(chapter, host: readerHost)
    }

    func testMangAdventureIterableAndNullableBooleanDTOThroughTheNativeBridge() throws {
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-en.assortedscans-v1.6.0.apk", responses: [
            "https://assortedscans.com/api/v2/series": try fixture("mangadventure-catalog.json"),
            "https://assortedscans.com/api/v2/series/owned": try fixture("mangadventure-book.json"),
            "https://assortedscans.com/api/v2/series/owned/chapters": try fixture("mangadventure-chapters.json"),
            "https://assortedscans.com/api/v2/chapters/22/pages": try fixture("mangadventure-pages.json"),
            "https://images.example/owned-page-2.webp": bytes
        ])
        let catalog: SourceMangaPage = try host.execute(["op": "popular"])
        let manga = try XCTUnwrap(catalog.mangas.first)
        XCTAssertEqual(manga.title, "Owned story")
        let book: MangaBook = try host.execute(["op": "book", "manga": ["url": manga.url, "title": manga.title]])
        XCTAssertEqual(book.manga.author, "Owned author")
        let chapter = try XCTUnwrap(book.chapters.first)
        XCTAssertEqual(chapter.chapterNumber, 1.5)
        XCTAssertEqual(chapter.uploadedAt, 1_709_164_800_000)
        try assertReader(chapter, host: host)
    }

    private func assertReader(_ chapter: SourceMangaChapter, host: OwnedExtensionFixtureHTTP) throws {
        let saved = try JSONDecoder().decode(SourceMangaChapter.self, from: JSONEncoder().encode(chapter))
        let pages: [SourceMangaImage] = try host.execute(["op": "pages", "chapter": MangaRuntime.chapterInput(saved)])
        XCTAssertEqual(pages.map(\.imageURL), ["https://images.example/owned-page-2.webp", "https://images.example/owned-page-1.webp"])
        let first = try XCTUnwrap(pages.first)
        let image: ImageBytes = try host.execute(["op": "image", "image": ["index": first.index, "url": first.url, "imageURL": first.imageURL]])
        XCTAssertEqual(Data(base64Encoded: image.bodyBase64), bytes)
    }

    private struct ImageBytes: Decodable { let bodyBase64: String }
}
