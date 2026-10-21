import XCTest
import AnimeCore
@testable import AnimeCompanion

final class DateCompatibilityRuntimeTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "OwnedFixtures", withExtension: nil))
        return try Data(contentsOf: root.appendingPathComponent(name))
    }

    func testFoolSlideCalendarDefaultsAndOrderedReaderThroughTheNativeBridge() throws {
        let bytes = Data([0, 255, 23, 128])
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-en.deathtollscans-v1.6.6.apk", responses: [
            "https://reader.deathtollscans.net/directory/1/": try fixture("foolslide-catalog.html"),
            "https://reader.deathtollscans.net/series/owned": try fixture("foolslide-book.html"),
            "https://reader.deathtollscans.net/read/owned/2": try fixture("foolslide-pages.html"),
            "https://images.example/owned-page-2.webp": bytes
        ])
        let catalog: SourceMangaPage = try host.execute(["op": "popular"])
        let manga = try XCTUnwrap(catalog.mangas.first)
        XCTAssertEqual(manga.title, "Owned story")
        let book: MangaBook = try host.execute(["op": "book", "timeZoneID": "UTC", "manga": ["url": manga.url, "title": manga.title]])
        XCTAssertEqual(book.manga.author, "Owned author")
        XCTAssertEqual(book.manga.description, "Owned description")
        XCTAssertEqual(book.chapters.count, 2)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let year = calendar.component(.year, from: Date())
        let expected = try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: 10, day: 20)))
        let chapter = try XCTUnwrap(book.chapters.first)
        XCTAssertEqual(chapter.uploadedAt, Int64(expected.timeIntervalSince1970 * 1_000))
        XCTAssertEqual(book.chapters.last?.uploadedAt, 1_709_164_800_000)
        let localBook: MangaBook = try host.execute(["op": "book", "timeZoneID": "America/Los_Angeles", "manga": ["url": manga.url, "title": manga.title]])
        XCTAssertEqual(localBook.chapters.last?.uploadedAt, 1_709_193_600_000)
        let pages: [SourceMangaImage] = try host.execute(["op": "pages", "chapter": MangaRuntime.chapterInput(chapter)])
        XCTAssertEqual(pages.map(\.imageURL), ["https://images.example/owned-page-2.webp", "https://images.example/owned-page-1.webp"])
        try assertImage(try XCTUnwrap(pages.first), bytes: bytes, host: host)
    }

    func testDynastyFormatterKeepsItsUTCZoneThroughTheNativeBridge() throws {
        let bytes = Data([0, 255, 23, 128])
        let home = try fixture("dynasty-catalog.html")
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-en.dynasty-v1.6.1.apk", responses: [
            "https://dynasty-scans.com": home,
            "https://dynasty-scans.com/": home,
            "https://dynasty-scans.com/chapters/owned_story.json": try fixture("dynasty-chapter.json"),
            "https://dynasty-scans.com/owned-page-2.webp": bytes
        ])
        let catalog: SourceMangaPage = try host.execute(["op": "popular"])
        let manga = try XCTUnwrap(catalog.mangas.first)
        let book: MangaBook = try host.execute(["op": "book", "timeZoneID": "America/Los_Angeles", "manga": ["url": manga.url, "title": manga.title]])
        XCTAssertEqual(book.manga.title, "Owned story")
        let chapter = try XCTUnwrap(book.chapters.first)
        XCTAssertEqual(chapter.uploadedAt, 1_709_164_800_000)
        let pages: [SourceMangaImage] = try host.execute(["op": "pages", "chapter": MangaRuntime.chapterInput(chapter)])
        XCTAssertEqual(pages.map(\.imageURL), ["https://dynasty-scans.com/owned-page-2.webp", "https://dynasty-scans.com/owned-page-1.webp"])
        try assertImage(try XCTUnwrap(pages.first), bytes: bytes, host: host)
    }

    func testHiveworksLatestUsesCalendarWeekdayThroughTheNativeBridge() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        formatter.dateFormat = "EEEE"
        let url = "https://hiveworkscomics.com/home/update-day/\(formatter.string(from: Date()).lowercased())"
        let host = try OwnedExtensionFixtureHTTP(apkName: "tachiyomi-en.hiveworks-v1.6.2.apk", responses: [url: try fixture("hiveworks-latest.html")])
        let catalog: SourceMangaPage = try host.execute(["op": "latest", "timeZoneID": "UTC"])
        XCTAssertEqual(catalog.mangas.map(\.title), ["Owned story"])
        XCTAssertEqual(host.urls, [url])
    }

    private func assertImage(_ page: SourceMangaImage, bytes: Data, host: OwnedExtensionFixtureHTTP) throws {
        let image: ImageBytes = try host.execute(["op": "image", "image": ["index": page.index, "url": page.url, "imageURL": page.imageURL]])
        XCTAssertEqual(Data(base64Encoded: image.bodyBase64), bytes)
    }
    private struct ImageBytes: Decodable { let bodyBase64: String }
}
