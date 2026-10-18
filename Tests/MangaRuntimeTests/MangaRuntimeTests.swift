import XCTest
import AnimeCore
@testable import AnimeCompanion

final class MangaRuntimeTests: XCTestCase {
    func testModernExtensionCatalogRunsOnIOSWithoutAService() async throws {
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Fixtures", withExtension: nil))
        let data = try Data(contentsOf: root.appendingPathComponent("tachiyomi-all.commitstrip-v1.6.0.apk"))
        let inspection = try await MangaRuntime.inspect(data, modern: true)
        let source = try XCTUnwrap(inspection.sources.first { $0.language == "en" })
        let page = try await MangaRuntime.browse(data, source: source, modern: true, mode: "popular", query: "", page: 1)
        XCTAssertGreaterThan(page.mangas.count, 5)
        let first = try XCTUnwrap(page.mangas.first)
        let details = try await MangaRuntime.details(data, source: source, modern: true, manga: first)
        XCTAssertEqual(details.url, first.url)
        XCTAssertFalse(details.title.isEmpty)
    }
    func testRealAPKsLoadThroughTheSwiftCBridgeOnIOS() async throws {
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Fixtures", withExtension: nil))
        for (filename, modern, language) in [
            ("tachiyomi-en.mangapill-v1.4.9.apk", false, "en"),
            ("tachiyomi-vi.cuutruyenmoe-v1.6.3.apk", true, "vi")
        ] {
            let data = try Data(contentsOf: root.appendingPathComponent(filename))
            let inspection = try await MangaRuntime.inspect(data, modern: modern)
            XCTAssertTrue(inspection.packageName.hasPrefix("eu.kanade.tachiyomi.extension."))
            XCTAssertFalse(inspection.sources.isEmpty)
            XCTAssertEqual(inspection.sources[0].language, language)
            XCTAssertFalse(inspection.sources[0].name.isEmpty)
        }
    }
    func testMalformedAPKReturnsAnErrorAcrossTheCBridge() async throws {
        do { _ = try await MangaRuntime.inspect(Data("invalid apk".utf8), modern: true); XCTFail("Malformed APK executed") }
        catch { XCTAssertEqual(error as? MangaExtensionError, .runtimeFailure) }
    }
}
