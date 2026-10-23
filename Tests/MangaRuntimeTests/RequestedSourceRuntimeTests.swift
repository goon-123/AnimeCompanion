import XCTest
import AnimeCore
@testable import AnimeCompanion

final class RequestedSourceRuntimeTests: XCTestCase {
    private struct ImagePayload: Decodable { let bodyBase64: String }
    private func fixture(_ name: String) throws -> Data {
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "OwnedFixtures", withExtension: nil))
        return try Data(contentsOf: root.appendingPathComponent(name))
    }
    func testOmegaToonilyAndMangaBallKeepTitleMetadataAcrossFreshNativeCalls() throws {
        let cases: [(String, String, Int, [String], Int64)] = [
            ("tachiyomi-en.omegascans-v1.6.52.apk", "omega", 0,
             ["https://api.omegascans.org/query", "https://api.omegascans.org/series/owned", "https://api.omegascans.org/chapter/query", "https://api.omegascans.org/chapter/owned/chapter-3"], 1_709_210_096_123),
            ("tachiyomi-en.toonily-v1.6.72.apk", "toonily", 0,
             ["https://toonily.com/wp-admin/admin-ajax.php", "https://toonily.com/serie/owned", "https://toonily.com/serie/owned/ajax/chapters/", "https://toonily.com/serie/owned/chapter-3/"], 1_709_164_800_000),
            ("tachiyomi-all.mangaball-v1.6.5.apk", "mangaball", 8,
             ["https://mangaball.com/api/v1/title/search-advanced", "https://mangaball.com/api/v1/title/detail/owned-id", "https://mangaball.com/api/v1/chapter/chapter-listing-by-title-id", "https://mangaball.com/api/v1/chapter-detail"], 1_709_210_096_123)
        ]
        let imageBytes = Data([0, 255, 23, 128])
        for (apk, prefix, source, urls, uploadedAt) in cases {
            var responses = ["https://images.example/owned-page-2.webp": imageBytes,
                             "https://mangaball.com/api/v1/views/update": Data("{}".utf8)]
            for (index, stage) in ["catalog", "book", "chapters", "pages"].enumerated() {
                responses[urls[index]] = try fixture("\(prefix)-\(stage).\(prefix == "toonily" ? "html" : "json")")
            }
            let host = try OwnedExtensionFixtureHTTP(apkName: apk, responses: responses)
            let catalog: SourceMangaPage = try host.execute(["op": "popular", "source": source])
            let title = try XCTUnwrap(catalog.mangas.first)
            XCTAssertEqual(title.title, "Owned story")
            XCTAssertNotNil(title.memo)
            // Exercise the persisted Swift model and the actual app command builder.
            let restored = try JSONDecoder().decode(SourceManga.self, from: JSONEncoder().encode(title))
            let book: MangaBook = try host.execute(["op": "book", "source": source, "timeZoneID": "UTC", "manga": MangaRuntime.mangaInput(restored)])
            XCTAssertEqual(book.manga.description, "Owned description")
            XCTAssertEqual(book.chapters.count, 2)
            XCTAssertEqual(book.chapters.first?.uploadedAt, uploadedAt)
            let chapter = try XCTUnwrap(book.chapters.first)
            let pages: [SourceMangaImage] = try host.execute(["op": "pages", "source": source, "chapter": MangaRuntime.chapterInput(chapter)])
            XCTAssertEqual(pages.map(\.imageURL), ["https://images.example/owned-page-2.webp", "https://images.example/owned-page-1.webp"])
            let image = try XCTUnwrap(pages.first)
            let payload: ImagePayload = try host.execute(["op": "image", "source": source,
                "image": ["index": image.index, "url": image.url, "imageURL": image.imageURL]])
            XCTAssertEqual(Data(base64Encoded: payload.bodyBase64), imageBytes)
            if prefix == "toonily" { XCTAssertFalse(host.urls.contains("https://toonily.com/?p=7")) }
            if prefix == "mangaball" {
                XCTAssertEqual(host.bodiesByURL[urls[2]], Data(#"{"title_id":"owned-id"}"#.utf8))
                XCTAssertTrue(host.headersByURL[urls[2], default: []].contains { $0[0].lowercased() == "content-type" && $0[1] == "application/json" })
            }
        }
    }
}
