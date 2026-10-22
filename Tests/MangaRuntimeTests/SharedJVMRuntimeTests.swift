import XCTest
import AnimeCore
@testable import AnimeCompanion

final class SharedJVMRuntimeTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "OwnedFixtures", withExtension: nil))
        return try Data(contentsOf: root.appendingPathComponent(name))
    }
    private struct ImagePayload: Decodable { let bodyBase64: String }
    private let bytes = Data([0, 255, 23, 128])

    func testSenkuroAndSenkognitoISODatesAndCompleteReaderThroughNativeBridge() throws {
        for apk in ["tachiyomi-ru.senkuro-v1.6.0.apk", "tachiyomi-ru.senkognito-v1.6.0.apk"] {
            let host = try OwnedExtensionFixtureHTTP(apkName: apk, responses: ["https://images.example/owned-page-2.webp": bytes], graphQLResponses: [
                "searchTachiyomiManga": try fixture("senkuro-catalog.json"),
                "fetchTachiyomiManga": try fixture("senkuro-book.json"),
                "fetchTachiyomiChapters": try fixture("senkuro-chapters.json"),
                "fetchTachiyomiChapterPages": try fixture("senkuro-pages.json")
            ])
            let catalog: SourceMangaPage = try host.execute(["op": "popular"])
            let manga = try XCTUnwrap(catalog.mangas.first)
            XCTAssertEqual(manga.title, "Owned story")
            let book: MangaBook = try host.execute(["op": "book", "timeZoneID": "UTC", "manga": ["url": manga.url, "title": manga.title]])
            XCTAssertEqual(book.manga.description, "Owned description")
            XCTAssertEqual(book.chapters.map(\.uploadedAt), [1_709_201_096_123, 1_709_210_096_123, 0])
            XCTAssertEqual(book.chapters.first?.scanlator, "Owned team")
            let chapter = try XCTUnwrap(book.chapters.first)
            let pages: [SourceMangaImage] = try host.execute(["op": "pages", "chapter": MangaRuntime.chapterInput(chapter)])
            XCTAssertEqual(pages.map(\.imageURL), ["https://images.example/owned-page-2.webp", "https://images.example/owned-page-1.webp"])
            try assertImage(try XCTUnwrap(pages.first), host: host)
            XCTAssertEqual(host.methodsByURL.filter { $0.key.hasSuffix("/graphql") }.values.first, "POST")
        }
    }

    func testWaMangaLazyLinesAndCompleteReaderThroughNativeBridge() throws {
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-ru.wamanga-v1.6.2.apk", responses: [
            "https://wamanga.ru/catalog/__data.json": try fixture("wamanga-catalog.jsonl"),
            "https://wamanga.ru/manga/owned/__data.json": try fixture("wamanga-book.jsonl"),
            "https://wamanga.ru/manga/owned/glava-2/__data.json": try fixture("wamanga-pages.jsonl"),
            "https://wamanga.ru/owned-page-1.webp": bytes
        ])
        let catalog: SourceMangaPage = try host.execute(["op": "popular"])
        let manga = try XCTUnwrap(catalog.mangas.first)
        XCTAssertEqual(manga.title, "Owned story")
        let book: MangaBook = try host.execute(["op": "book", "timeZoneID": "UTC", "manga": ["url": manga.url, "title": manga.title]])
        XCTAssertEqual(book.chapters.map(\.uploadedAt), [1_709_210_096_123, -1])
        let chapter = try XCTUnwrap(book.chapters.first)
        let pages: [SourceMangaImage] = try host.execute(["op": "pages", "chapter": MangaRuntime.chapterInput(chapter)])
        XCTAssertEqual(pages.map(\.imageURL), ["https://wamanga.ru/owned-page-1.webp", "https://wamanga.ru/owned-page-2.webp"])
        try assertImage(try XCTUnwrap(pages.first), host: host)
    }

    func testCharacterRangeFiltersAndCompleteReaderThroughNativeBridge() throws {
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-en.hentaihere-v1.6.1.apk", responses: [
            "https://hentaihere.com/category/34/most-viewed": try fixture("hentaihere-catalog.html"),
            "https://hentaihere.com/original/owned": try fixture("hentaihere-book.html"),
            "https://hentaihere.com/read/owned-2": try fixture("hentaihere-pages.html"),
            "https://images.example/owned-page-2.webp": bytes
        ])
        let catalog: SourceMangaPage = try host.execute(["op": "popular"])
        let manga = try XCTUnwrap(catalog.mangas.first)
        XCTAssertEqual(manga.title, "Owned story")
        let book: MangaBook = try host.execute(["op": "book", "manga": ["url": manga.url, "title": manga.title]])
        XCTAssertEqual(book.chapters.map(\.name), ["Chapter 2", "Chapter 1"])
        let chapter = try XCTUnwrap(book.chapters.first)
        let pages: [SourceMangaImage] = try host.execute(["op": "pages", "chapter": MangaRuntime.chapterInput(chapter)])
        XCTAssertEqual(pages.map(\.imageURL), ["https://images.example/owned-page-2.webp", "https://images.example/owned-page-1.webp"])
        try assertImage(try XCTUnwrap(pages.first), host: host)
    }

    func testInMangaAsyncDetailsFractionalDatesAndCompleteReaderThroughNativeBridge() throws {
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-es.inmanga-v1.6.1.apk", responses: [
            "https://inmanga.com/manga/getMangasConsultResult": try fixture("inmanga-catalog.html"),
            "https://inmanga.com/ver/manga/owned/1": try fixture("inmanga-book.html"),
            "https://inmanga.com/chapter/getall?mangaIdentification=1": try fixture("inmanga-chapters.json"),
            "https://inmanga.com/chapter/chapterIndexControls?identification=owned-3": try fixture("inmanga-pages.html"),
            "https://cdn1.intomanga.com/i/m/1/c/owned-chapter/o/2.jpg": bytes
        ])
        let catalog: SourceMangaPage = try host.execute(["op": "popular"])
        let manga = try XCTUnwrap(catalog.mangas.first)
        XCTAssertEqual(manga.title, "Owned story")
        let book: MangaBook = try host.execute(["op": "book", "timeZoneID": "UTC", "manga": ["url": manga.url, "title": manga.title]])
        XCTAssertEqual(book.manga.description, "Owned description")
        XCTAssertEqual(book.chapters.map(\.uploadedAt), [1_709_251_200_000, 1_709_210_096_123, -1])
        let chapter = try XCTUnwrap(book.chapters.first)
        let pages: [SourceMangaImage] = try host.execute(["op": "pages", "chapter": MangaRuntime.chapterInput(chapter)])
        XCTAssertEqual(pages.map(\.imageURL), ["https://cdn1.intomanga.com/i/m/1/c/owned-chapter/o/2.jpg", "https://cdn1.intomanga.com/i/m/1/c/owned-chapter/o/1.jpg"])
        try assertImage(try XCTUnwrap(pages.first), host: host)
        XCTAssertEqual(host.methodsByURL["https://inmanga.com/manga/getMangasConsultResult"], "POST")
    }

    func testArabManhwaJavaDurationsAndCompleteReaderThroughNativeBridge() throws {
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-ar.arabmanhwa-v1.6.57.apk", responses: [
            "https://arabmanhwa.com/manga/": try fixture("arabmanhwa-catalog.html"),
            "https://arabmanhwa.com/manga/owned/": try fixture("arabmanhwa-book.html"),
            "https://arabmanhwa.com/chapter/owned-2/": try fixture("arabmanhwa-pages.html"),
            "https://images.example/owned-page-2.webp": bytes
        ])
        let catalog: SourceMangaPage = try host.execute(["op": "popular"])
        let manga = try XCTUnwrap(catalog.mangas.first)
        let before = Int64(Date().timeIntervalSince1970 * 1_000)
        let book: MangaBook = try host.execute(["op": "book", "manga": ["url": manga.url, "title": manga.title]])
        let after = Int64(Date().timeIntervalSince1970 * 1_000)
        let chapter = try XCTUnwrap(book.chapters.first)
        XCTAssertTrue((before - 120_000...after - 120_000).contains(chapter.uploadedAt))
        let pages: [SourceMangaImage] = try host.execute(["op": "pages", "chapter": MangaRuntime.chapterInput(chapter)])
        XCTAssertEqual(pages.map(\.imageURL), ["https://images.example/owned-page-2.webp", "https://images.example/owned-page-1.webp"])
        try assertImage(try XCTUnwrap(pages.first), host: host)
    }

    func testProComicMutablePropertyCursorSkipsUnreadablePageThroughNativeBridge() throws {
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-ar.procomic-v1.6.0.apk", responses: [
            "https://procomic.pro/api/public/content?sort=popular&limit=50&page=1": try fixture("procomic-catalog-1.json"),
            "https://procomic.pro/api/public/content?sort=popular&limit=50&page=2": try fixture("procomic-catalog-2.json")
        ])
        let catalog: SourceMangaPage = try host.execute(["op": "popular"])
        XCTAssertEqual(catalog.mangas.map(\.title), ["Owned story"])
        XCTAssertEqual(host.urls.count, 2)
    }

    func testCodeArcBoundPropertyReferencesRefreshAnExpiredImageThroughNativeBridge() throws {
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-es.codearc-v1.6.2.apk", responses: [
            "https://mangas.codearctraducciones.com/api/mangas/reader-access": try fixture("codearc-reader-access.json"),
            "https://mangas.codearctraducciones.com/api/mangas/reader-pages": try fixture("codearc-reader-pages.json"),
            "https://images.example/owned-refreshed.webp": bytes
        ])
        let url = "https://images.example/owned.webp?reader_slug=owned&reader_chapter=chapter&reader_page=1&access=eyJleHAiOjB9.owned"
        let value: ImagePayload = try host.execute(["op": "image", "image": ["index": 0, "url": "", "imageURL": url]])
        XCTAssertEqual(Data(base64Encoded: value.bodyBase64), bytes)
        XCTAssertTrue(host.urls.contains("https://images.example/owned-refreshed.webp"))
        XCTAssertEqual(host.methodsByURL["https://mangas.codearctraducciones.com/api/mangas/reader-access"], "POST")
    }

    private func assertImage(_ page: SourceMangaImage, host: OwnedExtensionFixtureHTTP) throws {
        let value: ImagePayload = try host.execute(["op": "image", "image": ["index": page.index, "url": page.url, "imageURL": page.imageURL]])
        XCTAssertEqual(Data(base64Encoded: value.bodyBase64), bytes)
    }
}
