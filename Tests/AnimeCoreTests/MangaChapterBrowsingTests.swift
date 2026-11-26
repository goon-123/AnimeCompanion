import XCTest
@testable import AnimeCore

final class MangaChapterBrowsingTests: XCTestCase {
    private let source = MangaSourceReference(extensionID: "owned", sourceID: "en", name: "Owned", language: "en", homeURL: "https://source.example")
    private var title: MangaTitleReference { .init(source: source, manga: .init(url: "/story", title: "Owned story")) }
    private let chapters: [SourceMangaChapter] = [
        .init(url: "/one", name: "The beginning", chapterNumber: 1),
        .init(url: "/special", name: "Extra story", chapterNumber: 1.5),
        .init(url: "/two", name: "Chapter 2", chapterNumber: 2)
    ]
    func testChapterSearchAndStatusComposeWithoutLosingSourceOrderOrSpecials() {
        var state = MangaReadingState()
        state.mark(title, chapter: chapters[0], read: true)
        let record = state.record(title.id)
        XCTAssertEqual(MangaChapterBrowsing.chapters(chapters, record: record, query: "  1.5  ", filter: .unread), [chapters[1]])
        XCTAssertTrue(MangaChapterBrowsing.chapters(chapters, record: record, query: "beginning", filter: .unread).isEmpty)
        XCTAssertEqual(MangaChapterBrowsing.chapters(chapters, record: record, query: "", filter: .read), [chapters[0]])
        XCTAssertEqual(MangaChapterBrowsing.chapters(chapters, record: record, query: "", filter: .unread, newestFirst: true), [chapters[2], chapters[1]])
    }
    func testConfirmedBatchPreservesSavedSeriesHistoryAndUnselectedPosition() throws {
        var state = MangaReadingState()
        state.save(title, saved: true)
        let date = Date(timeIntervalSince1970: 100)
        let point = MangaReadingPosition(chapterURL: chapters[2].url, chapterName: chapters[2].name, pageIndex: 4, pageCount: 10, fraction: 0.7, updatedAt: date)
        state.record(title, position: point)
        let old = try XCTUnwrap(state.record(title.id))
        state.mark(title, chapters: [chapters[0], chapters[1], chapters[0]], read: true, now: date.addingTimeInterval(1))
        let result = try XCTUnwrap(state.record(title.id))
        XCTAssertTrue(result.saved)
        XCTAssertEqual(result.lastReadAt, old.lastReadAt)
        XCTAssertEqual(result.lastChapterURL, old.lastChapterURL)
        XCTAssertEqual(result.positions.count, 3)
        XCTAssertEqual(result.position(for: chapters[2].url), point)
        XCTAssertEqual(result.position(for: chapters[1].url)?.completed, true)
        XCTAssertEqual(try JSONDecoder().decode(MangaReadingState.self, from: JSONEncoder().encode(state)).record(title.id)?.positions, result.positions)
    }
    func testEmptyOrOversizedBatchLeavesStateUntouched() {
        var state = MangaReadingState()
        state.mark(title, chapters: [], read: true)
        XCTAssertTrue(state.records.isEmpty)
        state.mark(title, chapters: (0...10000).map { .init(url: "/\($0)", name: "Chapter \($0)") }, read: true)
        XCTAssertTrue(state.records.isEmpty)
    }
    func testWebSharingResolvesPathsAndExcludesOpaqueIDsAndNonWebSchemes() {
        XCTAssertEqual(source.webURL(for: "/reader/7")?.absoluteString, "https://source.example/reader/7")
        XCTAssertEqual(source.webURL(for: "reader/7")?.absoluteString, "https://source.example/reader/7")
        XCTAssertEqual(source.webURL(for: "https://other.example/story")?.host, "other.example")
        for value in ["123", "", #"{"id":"7"}"#, "file:///private/page", "javascript:alert(1)", "https://user:password@source.example/story"] {
            XCTAssertNil(source.webURL(for: value))
        }
    }
    func testPlaceholderScanlatorsAreOmittedButRealGroupsRemain() {
        for value in ["unknown", " Unknown ", "N/A", "", "none", "?"] { XCTAssertNil(MangaChapterBrowsing.scanlator(value)) }
        XCTAssertEqual(MangaChapterBrowsing.scanlator(" Owned scans "), "Owned scans")
    }
    func testOldReaderLayoutsKeepOptionalDetailsButCannotBuryPrimaryActions() {
        let old = SeriesDetailLayout(page: .reader, saved: #"{"order":["chapters","reading","genres","sourceLink","synopsis"],"hidden":["reading","sourceLink","genres"]}"#)
        XCTAssertEqual(old.order, [.chapters, .genres, .synopsis])
        XCTAssertEqual(old.hidden, [.genres])
        XCTAssertFalse(old.order.contains(.reading))
        XCTAssertFalse(old.order.contains(.sourceLink))
        XCTAssertEqual(SeriesDetailLayout(page: .reader, saved: old.saved), old)
    }
}
