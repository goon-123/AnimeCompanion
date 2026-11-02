import XCTest
@testable import AnimeCore

final class CompactSeriesTests: XCTestCase {
    private func entry(_ progress: Int, status: String = "CURRENT", repeats: Int = 2) throws -> LibraryEntry {
        try JSONDecoder().decode(LibraryEntry.self, from: Data("{\"id\":11,\"mediaId\":1,\"progress\":\(progress),\"status\":\"\(status)\",\"repeat\":\(repeats),\"score\":85,\"notes\":\"Keep my notes\"}".utf8))
    }
    func testMarkingThroughAnEpisodeDoesNotOverwriteRatingOrNotes() throws {
        let edit = try TrackingEdit.watched(through: 11, entry: entry(8), total: 12, automaticallyComplete: true)
        XCTAssertEqual(edit.progress, 11); XCTAssertEqual(edit.status, .watching)
        XCTAssertNil(edit.scoreRaw); XCTAssertNil(edit.notes); XCTAssertNil(edit.repeatCount)
        XCTAssertEqual(try edit.validated(total: 12), edit)
    }
    func testWatchedRowsNeverRewindProgressOrChangeExistingStatus() throws {
        let existing = try entry(8, status: "PAUSED")
        for number in [3, 8] {
            let edit = try TrackingEdit.watched(through: number, entry: existing, total: 12, automaticallyComplete: true)
            XCTAssertEqual(edit.progress, 8); XCTAssertEqual(edit.status, .paused); XCTAssertNil(edit.repeatCount)
        }
    }
    func testCompletionAndRewatchCountFollowTheExistingPreference() throws {
        let existing = try entry(11, status: "REPEATING", repeats: 3)
        let completed = try TrackingEdit.watched(through: 12, entry: existing, total: 12, automaticallyComplete: true)
        XCTAssertEqual(completed.status, .completed); XCTAssertEqual(completed.repeatCount, 4)
        let manual = try TrackingEdit.watched(through: 12, entry: existing, total: 12, automaticallyComplete: false)
        XCTAssertEqual(manual.status, .rewatching); XCTAssertNil(manual.repeatCount)
        let duplicate = try TrackingEdit.watched(through: 12, entry: entry(12, status: "COMPLETED", repeats: 4), total: 12, automaticallyComplete: true)
        XCTAssertNil(duplicate.repeatCount)
    }
    func testUnknownTotalsAndInvalidEpisodeSelections() throws {
        let edit = try TrackingEdit.watched(through: 140, entry: nil, total: nil, automaticallyComplete: true)
        XCTAssertEqual(edit.progress, 140); XCTAssertEqual(edit.status, .watching)
        for number in [0, -1, 13, 100_001] { XCTAssertThrowsError(try TrackingEdit.watched(through: number, entry: nil, total: 12, automaticallyComplete: true)) }
    }
    func testReadChoicesUseWrittenIDsSourcePriorityAndContentFiltering() throws {
        let anime = try JSONDecoder().decode(Anime.self, from: Data(#"{"id":1,"relations":{"edges":[{"relationType":"ADAPTATION","node":{"id":30,"type":"MANGA"}},{"relationType":"SEQUEL","node":{"id":40,"type":"ANIME"}},{"relationType":"SOURCE","node":{"id":20,"type":"MANGA"}},{"relationType":"OTHER","node":{"id":20,"type":"MANGA"}},{"relationType":"SOURCE","node":{"id":50,"type":"MANGA","isAdult":true}}]}}"#.utf8))
        XCTAssertEqual(AnimeSeriesContent.writtenMedia(for: anime, includeAdult: false).map(\.id), [20, 30])
        XCTAssertEqual(AnimeSeriesContent.writtenMedia(for: anime, includeAdult: true).map(\.id), [20, 50, 30])
        XCTAssertFalse(AnimeSeriesContent.writtenMedia(for: anime, includeAdult: true).contains { $0.id == anime.id })
    }
}
