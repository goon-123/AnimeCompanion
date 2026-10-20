import XCTest
import AnimeCore
@testable import AnimeCompanion

final class AdditionalReaderRuntimeTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let folder = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "OwnedFixtures", withExtension: nil))
        return try Data(contentsOf: folder.appendingPathComponent(name))
    }
    func testComicFuryChapterAndPageParsersThroughTheNativeBridge() throws {
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-all.comicfury-v1.6.0.apk", responses: [
            "https://comicfury.com/search.php": try fixture("comicfury-catalog.html"),
            "https://comicfury.com/profile.php": Data("<html><div class=\"username-and-title\"><em>Owned description</em></div><a class=\"authorname\">Owned author</a></html>".utf8),
            "https://comicfury.com/read/owned/archive": try fixture("comicfury-archive.html"),
            "https://comicfury.com/read/owned/2": try fixture("comicfury-pages.html")
        ])
        let catalog: SourceMangaPage = try host.execute(["op": "popular", "source": 1])
        let manga = try XCTUnwrap(catalog.mangas.first)
        XCTAssertEqual(manga.title, "Owned story")
        XCTAssertEqual(manga.thumbnailURL, "https://images.example/owned-cover.png")
        let book: MangaBook = try host.execute(["op": "book", "source": 1, "manga": ["url": manga.url, "title": manga.title]])
        XCTAssertEqual(book.manga.author, "Owned author")
        XCTAssertEqual(book.chapters.count, 2)
        let chapter = try XCTUnwrap(book.chapters.first)
        XCTAssertEqual(chapter.name, "Owned second chapter")
        XCTAssertGreaterThan(chapter.uploadedAt, 0)
        let saved = try JSONDecoder().decode(SourceMangaChapter.self, from: JSONEncoder().encode(chapter))
        let pages: [SourceMangaImage] = try host.execute(["op": "pages", "source": 1, "chapter": MangaRuntime.chapterInput(saved)])
        XCTAssertEqual(pages.map(\.imageURL), ["https://images.example/owned-page-2.png", "https://images.example/owned-page-1.png"])
    }
    func testComicsKingdomCompactReaderRetainsTheSourcePageOrder() throws {
        let manga = try fixture("comicskingdom-manga.json")
        let catalog = Data("[".utf8) + manga + Data("]".utf8)
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-all.comicskingdom-v1.6.0.apk", responses: [
            "https://wp.comicskingdom.com/wp-json/wp/v2/ck_feature": catalog,
            "https://wp.comicskingdom.com/wp-json/wp/v2/ck_feature/42": manga,
            "https://comicskingdom.com/owned": Data("<script>{\"totalItems\":2}</script>".utf8),
            "https://wp.comicskingdom.com/wp-json/wp/v2/ck_comic": try fixture("comicskingdom-chapters.json")
        ])
        let list: SourceMangaPage = try host.execute(["op": "popular"])
        let entry = try XCTUnwrap(list.mangas.first)
        XCTAssertEqual(entry.thumbnailURL, "https://images.example/owned-cover.png")
        let book: MangaBook = try host.execute(["op": "book", "manga": ["url": entry.url, "title": entry.title]])
        XCTAssertEqual(book.chapters.count, 1)
        XCTAssertEqual(book.chapters.first?.name, "1-2")
        let chapter = try XCTUnwrap(book.chapters.first)
        let pages: [SourceMangaImage] = try host.execute(["op": "pages", "chapter": MangaRuntime.chapterInput(chapter)])
        XCTAssertEqual(pages.map(\.imageURL), ["https://images.example/owned-page-2.png", "https://images.example/owned-page-1.png"])
    }
    func testProjectSukiNumericPageSortAndMangaBuddyNextJSReader() throws {
        let suki = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-all.projectsuki-v1.6.0.apk", responses: [
            "https://projectsuki.com/browse/0": try fixture("projectsuki-catalog.html"),
            "https://projectsuki.com/callpage": try fixture("projectsuki-pages.json")
        ])
        let catalog: SourceMangaPage = try suki.execute(["op": "popular"])
        XCTAssertEqual(catalog.mangas.first?.title, "Owned story")
        XCTAssertEqual(catalog.mangas.first?.thumbnailURL, "https://projectsuki.com/images/gallery/42/thumb.png")
        let pages: [SourceMangaImage] = try suki.execute(["op": "pages", "chapter": ["url": "/read/42/7/1", "name": "Owned chapter"]])
        XCTAssertEqual(pages.map(\.imageURL), [1, 2, 10].map { "https://projectsuki.com/images/gallery/42/owned/\($0)" })
        let buddy = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-en.mangabuddy-v1.6.34.apk", responses: [
            "https://api.mangak.io/titles/search": try fixture("mangabuddy-catalog.json"),
            "https://mangak.io/manga/owned/chapter-1": try fixture("mangabuddy-pages.html")
        ], responseHeaders: [["Content-Type", "text/html; charset=utf-8"]])
        let result: SourceMangaPage = try buddy.execute(["op": "popular"])
        XCTAssertEqual(result.mangas.first?.title, "Owned story")
        let chapterPages: [SourceMangaImage] = try buddy.execute(["op": "pages", "chapter": ["url": "/manga/owned/chapter-1", "name": "Owned chapter"]])
        XCTAssertEqual(chapterPages.map(\.imageURL), ["https://images.example/owned-page-2.png", "https://images.example/owned-page-1.png"])
    }
}
