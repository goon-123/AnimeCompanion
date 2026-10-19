import XCTest
import AnimeCore

final class BroadCatalogRuntimeTests: XCTestCase {
    func testCurrentIndependentFamiliesReturnRealEntriesThroughTheNativeBridge() throws {
        let bundle = Bundle(for: Self.self)
        let folder = try XCTUnwrap(bundle.url(forResource: "OwnedFixtures", withExtension: nil))
        let fixtures: [(String, Int, String, String)] = [
            ("tachiyomi-en.manhuaus-v1.6.60.apk", 0, "https://manhuaus.com/wp-admin/admin-ajax.php", "madara-catalog.html"),
            ("tachiyomi-all.mangafire-v1.6.34.apk", 0, "https://mangafire.to/api/titles", "mangafire-catalog.json"),
            ("tachiyomi-all.mangadex-v1.6.0.apk", 17, "https://api.mangadex.org/manga", "mangadex-catalog.json")
        ]
        for (apk, source, url, fixture) in fixtures {
            let host = try OwnedExtensionFixtureHTTP(apkName: apk, responses: [url: Data(contentsOf: folder.appendingPathComponent(fixture))])
            let page: SourceMangaPage = try host.execute(["op": "popular", "source": source])
            XCTAssertEqual(page.mangas.count, 1, apk)
            XCTAssertEqual(page.mangas.first?.title, "Owned story", apk)
            XCTAssertFalse(page.mangas.first?.thumbnailURL.isEmpty ?? true, apk)
            XCTAssertEqual(host.urls.count, 1, apk)
        }
    }
}
