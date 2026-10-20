import XCTest
import AnimeCore
@testable import AnimeCompanion

final class HentaiNexusRuntimeTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let folder = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "OwnedFixtures", withExtension: nil))
        return try Data(contentsOf: folder.appendingPathComponent(name))
    }
    private func host(reader: String = "hentainexus-pages.html") throws -> OwnedExtensionFixtureHTTP {
        try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-en.hentainexus-v1.6.20.apk", responses: [
            "https://hentainexus.com/explore/hot": try fixture("hentainexus-catalog.html"),
            "https://hentainexus.com/page/2": try fixture("hentainexus-catalog.html"),
            "https://hentainexus.com/view/42": try fixture("hentainexus-details.html"),
            "https://hentainexus.com/read/42": try fixture(reader),
            "https://images.example/owned-page-2.webp": Data([0, 255, 23, 128])
        ])
    }
    func testCatalogDatedChapterDecoderAndImageThroughTheNativeBridge() throws {
        let host = try host()
        let catalog: SourceMangaPage = try host.execute(["op": "popular"])
        XCTAssertEqual(catalog.mangas.count, 2)
        XCTAssertEqual(catalog.mangas.first?.title, "Owned story")
        XCTAssertEqual(catalog.mangas.first?.thumbnailURL, "https://images.example/owned-cover.png")
        let commands: [[String: Any]] = [
            ["op": "latest", "page": 2],
            ["op": "search", "page": 2, "query": "Owned"]
        ]
        for command in commands {
            let page: SourceMangaPage = try host.execute(command)
            XCTAssertEqual(page.mangas.map(\.title), ["Owned story", "Owned second story"])
        }
        let manga = try XCTUnwrap(catalog.mangas.first)
        let book: MangaBook = try host.execute(["op": "book", "manga": ["url": manga.url, "title": manga.title]])
        XCTAssertEqual(book.manga.author, "Owned author, Owned artist")
        let chapter = try XCTUnwrap(book.chapters.first)
        XCTAssertEqual(chapter.url, "/read/42")
        XCTAssertEqual(chapter.uploadedAt, 1_792_454_400_000)
        let saved = try JSONDecoder().decode(SourceMangaChapter.self, from: JSONEncoder().encode(chapter))
        let pages: [SourceMangaImage] = try host.execute(["op": "pages", "chapter": MangaRuntime.chapterInput(saved)])
        XCTAssertEqual(pages.map(\.imageURL), ["https://images.example/owned-page-2.webp", "https://images.example/owned-page-1.webp"])
        let page = try XCTUnwrap(pages.first)
        let image: ImageResponse = try host.execute(["op": "image", "image": [
            "index": page.index, "url": page.url, "imageURL": page.imageURL
        ]])
        XCTAssertEqual(Data(base64Encoded: image.bodyBase64), Data([0, 255, 23, 128]))
    }
    func testQualityPreferencesAndUnavailableQuality() throws {
        let host = try host()
        let inspection: MangaExtensionInspection = try host.execute(["op": "inspect"])
        let source = try XCTUnwrap(inspection.sources.first)
        for (quality, suffix) in [("webp", "webp"), ("source", "png"), ("avif", "avif")] {
            let pages: [SourceMangaImage] = try host.execute([
                "op": "pages", "chapter": ["url": "/read/42"], "settingsSourceID": source.id,
                "settings": ["pref_image_format": ["type": "string", "value": quality]]
            ])
            XCTAssertEqual(pages.first?.imageURL, "https://images.example/owned-page-2.\(suffix)")
        }
        let fallback = try self.host(reader: "hentainexus-fallback.html")
        let command: [String: Any] = [
            "op": "pages", "chapter": ["url": "/read/42"], "settingsSourceID": source.id,
            "settings": ["pref_image_format": ["type": "string", "value": "source"]]
        ]
        XCTAssertThrowsError(try fallback.execute(command) as [SourceMangaImage]) { error in
            XCTAssertTrue(error.localizedDescription.contains("Selected quality"))
        }
    }
    private struct ImageResponse: Decodable { let bodyBase64: String }
}
