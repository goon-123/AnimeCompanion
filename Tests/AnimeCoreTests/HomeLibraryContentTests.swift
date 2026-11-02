import XCTest
@testable import AnimeCore

final class HomeLibraryContentTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000)
    private func entry(id: Int = 1, mediaID: Int = 10, status: String = "CURRENT", progress: Int = 3,
                       mediaStatus: String = "RELEASING", nextEpisode: Int? = 8, updatedAt: Int = 1) throws -> LibraryEntry {
        var media: [String: Any] = ["id": mediaID, "episodes": 12, "status": mediaStatus]
        if let nextEpisode { media["nextAiringEpisode"] = ["episode": nextEpisode, "airingAt": 66_800] }
        let object: [String: Any] = ["id": id, "mediaId": mediaID, "status": status, "progress": progress, "updatedAt": updatedAt, "media": media]
        return try JSONDecoder().decode(LibraryEntry.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testCatchUpUsesConfirmedOriginalBroadcastsAndSkipsMissingAndUnairedData() throws {
        let entries = try [entry(), entry(id: 2, mediaID: 20, mediaStatus: "NOT_YET_RELEASED"),
                           entry(id: 3, mediaID: 30, nextEpisode: nil), entry(id: 4, mediaID: 40, progress: 7),
                           entry(id: 5, mediaID: 50, status: "PLANNING"), entry(id: 6, mediaID: 60, status: "PAUSED")]
        let items = HomeLibraryContent.catchUp(entries, now: now)
        XCTAssertEqual(items.map(\.id), [10])
        XCTAssertEqual(items.first?.aired, 7)
        XCTAssertEqual(items.first?.remaining, 4)
    }
    func testFinishedAndRewatchingCountRealEpisodesAndNewestDuplicateWins() throws {
        let old = try entry(id: 1, progress: 0, updatedAt: 1)
        let new = try entry(id: 2, progress: 6, updatedAt: 2)
        let finished = try entry(id: 3, mediaID: 30, status: "REPEATING", progress: 4, mediaStatus: "FINISHED", nextEpisode: nil)
        let items = HomeLibraryContent.catchUp([old, new, finished], now: now)
        XCTAssertEqual(items.map(\.id), [30, 10])
        XCTAssertEqual(items.map(\.remaining), [8, 1])
        XCTAssertEqual(HomeLibraryContent.unique([new, old]).count, 1)
    }
    func testShuffleOnlyChoosesReleasedPlannedTitlesAndKeepsWatchlistOrderStable() throws {
        let watching = try entry()
        let planned = try entry(id: 2, mediaID: 20, status: "PLANNING", updatedAt: 2)
        let future = try entry(id: 3, mediaID: 30, status: "PLANNING", mediaStatus: "NOT_YET_RELEASED", nextEpisode: 1, updatedAt: 3)
        let unknown = try entry(id: 4, mediaID: 40, status: "PLANNING", nextEpisode: nil, updatedAt: 4)
        let entries = [watching, planned, future, unknown, planned]
        XCTAssertEqual(HomeLibraryContent.planned(entries).map(\.mediaId), [40, 30, 20])
        XCTAssertEqual(HomeLibraryContent.shuffleCandidates(entries, now: now).map(\.id), [20])
    }
}
