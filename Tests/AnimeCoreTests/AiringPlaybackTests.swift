import XCTest
@testable import AnimeCore

final class AiringPlaybackTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2000)
    private func anime(_ json: String) throws -> Anime { try JSONDecoder().decode(Anime.self, from: Data(json.utf8)) }
    private func entry(_ progress: Int, status: String = "CURRENT") throws -> LibraryEntry {
        try JSONDecoder().decode(LibraryEntry.self, from: Data("{\"id\":100,\"mediaId\":10,\"status\":\"\(status)\",\"progress\":\(progress)}".utf8))
    }
    private func airing() throws -> Anime {
        try anime(#"{"id":10,"episodes":12,"status":"RELEASING","nextAiringEpisode":{"episode":7,"airingAt":3000}}"#)
    }
    func testCatchUpUsesReleasedEpisodesNotSeasonTotal() throws {
        let title = try airing()
        let behind = try XCTUnwrap(LibraryAiringProgress(anime: title, watched: 4, now: now))
        XCTAssertEqual(behind.state, .behind); XCTAssertEqual(behind.behindCount, 2)
        XCTAssertEqual(behind.watched, 4); XCTAssertEqual(behind.released, 6)
        XCTAssertEqual(behind.nextEpisode, 7); XCTAssertEqual(behind.nextDate, Date(timeIntervalSince1970: 3000))
        XCTAssertEqual(behind.label, "2 episodes behind")
        XCTAssertEqual(LibraryAiringProgress(anime: title, watched: 6, now: now)?.state, .caughtUp)
        XCTAssertEqual(LibraryAiringProgress(anime: title, watched: 8, now: now)?.behindCount, 0)
    }
    func testFinishedAndFutureTitlesDoNotGetCatchUpBadges() throws {
        for status in ["FINISHED", "NOT_YET_RELEASED", "CANCELLED", "HIATUS"] {
            let title = try anime("{\"id\":10,\"status\":\"\(status)\",\"episodes\":12,\"nextAiringEpisode\":{\"episode\":7,\"airingAt\":3000}}")
            XCTAssertNil(LibraryAiringProgress(anime: title, watched: 2, now: now))
        }
    }
    func testMissingExpiredAndImpossibleSchedulesStayUnknown() throws {
        for json in [
            #"{"id":10,"status":"RELEASING"}"#,
            #"{"id":10,"status":"RELEASING","nextAiringEpisode":{"episode":7,"airingAt":1500}}"#,
            #"{"id":10,"status":"RELEASING","episodes":12,"nextAiringEpisode":{"episode":13,"airingAt":3000}}"#,
            #"{"id":10,"status":"RELEASING","nextAiringEpisode":{"episode":0,"airingAt":3000}}"#
        ] {
            let result = LibraryAiringProgress(anime: try anime(json), watched: 6, now: now)
            XCTAssertEqual(result?.state, .unknown); XCTAssertNil(result?.released); XCTAssertNil(result?.nextDate)
        }
    }
    func testFirstEpisodeIsUpcomingNotCaughtUp() throws {
        let title = try anime(#"{"id":10,"status":"RELEASING","nextAiringEpisode":{"episode":1,"airingAt":3000}}"#)
        XCTAssertEqual(LibraryAiringProgress(anime: title, watched: 0, now: now)?.state, .waiting)
    }
    func testAiringDubOfFinishedOriginalUsesOnlyReportedDubCount() throws {
        let title = try anime(#"{"id":10,"idMal":20,"episodes":12,"status":"FINISHED"}"#)
        let history = try JSONDecoder().decode([RawDubFeedItem].self, from: Data(#"[{"id":10,"episode":{"aired":3,"airedAt":1000}}]"#.utf8))
        let progress = LibraryDubProgress(anime: title, snapshot: DubSnapshot(upcoming: [], history: history), index: nil, now: now)
        let next = ReleaseEvent(anime: title, episode: 4, kind: .dub, date: Date(timeIntervalSince1970: 3000), certainty: .verified)
        let behind = LibraryAiringProgress(anime: title, watched: 1, source: .dub, dub: progress, nextDub: next, now: now)
        XCTAssertEqual(behind?.released, 3); XCTAssertEqual(behind?.behindCount, 2)
        XCTAssertEqual(behind?.state, .behind); XCTAssertEqual(behind?.nextEpisode, 4)
        XCTAssertEqual(behind?.estimatedDate, false)
        XCTAssertNil(LibraryAiringProgress(anime: title, watched: 1, now: now))
        XCTAssertEqual(LibraryAiringProgress(anime: title, watched: 3, source: .dub, dub: progress, nextDub: next, now: now)?.state, .caughtUp)
    }
    func testEstimatedDubCountCannotProduceGreenOrYellowTrackingStatus() throws {
        let title = try airing()
        let planned = try JSONDecoder().decode([RawDubItem].self, from: Data(#"[{"episodeNumber":5,"episodeDate":3000,"media":{"media":{"id":10}}}]"#.utf8))
        let progress = LibraryDubProgress(anime: title, snapshot: DubSnapshot(upcoming: planned, history: []), index: nil, now: now)
        XCTAssertEqual(progress.confidence, .estimated)
        let next = ReleaseEvent(anime: title, episode: 5, kind: .dub, date: Date(timeIntervalSince1970: 3000), certainty: .unverified)
        let result = LibraryAiringProgress(anime: title, watched: 4, source: .dub, dub: progress, nextDub: next, now: now)
        XCTAssertEqual(result?.state, .unknown); XCTAssertNil(result?.released)
        XCTAssertEqual(result?.estimatedDate, true); XCTAssertEqual(result?.nextEpisode, 5)
    }
    func testDubAnnouncementsAndUnmatchedSchedulesAreNotOngoingAirings() throws {
        let title = try airing()
        let future = Date(timeIntervalSince1970: 3000)
        for next in [
            ReleaseEvent(anime: title, episode: 1, kind: .dub, date: future, certainty: .verified),
            ReleaseEvent(anime: Anime(id: 99, title: "Other season"), episode: 4, kind: .dub, date: future, certainty: .verified),
            ReleaseEvent(anime: title, episode: 4, kind: .sub, date: future, certainty: .broadcast),
            ReleaseEvent(anime: title, episode: 4, kind: .dub, date: now, certainty: .verified),
            ReleaseEvent(anime: title, episode: 4, kind: .dub, date: nil, certainty: .delayed)
        ] { XCTAssertNil(LibraryAiringProgress(anime: title, watched: 3, source: .dub, nextDub: next, now: now)) }
    }
    func testAniListProgressOverridesOlderAndLaterLocalResumeEpisodes() throws {
        let title = try airing(), tracked = try entry(4)
        for resume in [nil, 1, 5, 9] as [Int?] {
            XCTAssertEqual(PlaybackEpisodeSelection.initial(anime: title, entry: tracked, resumeEpisode: resume), 5)
        }
        XCTAssertEqual(PlaybackEpisodeSelection.initial(anime: title, entry: try entry(3), resumeEpisode: 1), 4)
    }
    func testPlaybackBoundsMoviesUnknownCountsAndRewatches() throws {
        let title = try airing()
        XCTAssertEqual(PlaybackEpisodeSelection.initial(anime: title, entry: try entry(12), resumeEpisode: 1), 12)
        XCTAssertEqual(PlaybackEpisodeSelection.initial(anime: title, entry: try entry(0, status: "REPEATING"), resumeEpisode: 12), 1)
        XCTAssertEqual(PlaybackEpisodeSelection.initial(anime: title, entry: try entry(4, status: "PAUSED"), resumeEpisode: 1), 5)
        XCTAssertEqual(PlaybackEpisodeSelection.initial(anime: title, entry: try entry(-2), resumeEpisode: nil), 1)
        XCTAssertEqual(PlaybackEpisodeSelection.initial(anime: Anime(id: 10, title: "Unknown"), entry: try entry(Int.max), resumeEpisode: nil), 100_000)
        let movie = try anime(#"{"id":10,"format":"MOVIE"}"#)
        XCTAssertEqual(PlaybackEpisodeSelection.initial(anime: movie, entry: try entry(4), resumeEpisode: 8), 1)
    }
    func testUntrackedTitlesCanResumeButRejectInvalidLocalEpisode() throws {
        let title = try airing()
        XCTAssertEqual(PlaybackEpisodeSelection.initial(anime: title, entry: nil, resumeEpisode: 4), 4)
        for resume in [nil, 0, -1, 13] as [Int?] {
            XCTAssertEqual(PlaybackEpisodeSelection.initial(anime: title, entry: nil, resumeEpisode: resume), 1)
        }
    }
    func testTrackingEqualityIgnoresMetadataButProtectsNotesScoresAndRewatches() throws {
        let original = try entry(4)
        let refreshed = try JSONDecoder().decode(LibraryEntry.self, from: Data(#"{"id":100,"mediaId":10,"status":"CURRENT","progress":4,"score":0,"notes":"","repeat":0,"media":{"id":10,"title":{"english":"Refreshed"}}}"#.utf8))
        XCTAssertTrue(original.hasSameTracking(as: refreshed))
        for change in ["\"notes\":\"Edited elsewhere\"", "\"score\":90", "\"repeat\":2"] {
            let other = try JSONDecoder().decode(LibraryEntry.self, from: Data("{\"id\":100,\"mediaId\":10,\"status\":\"CURRENT\",\"progress\":4,\(change)}".utf8))
            XCTAssertFalse(original.hasSameTracking(as: other))
        }
        XCTAssertFalse(original.hasSameTracking(as: try entry(5)))
    }
}
