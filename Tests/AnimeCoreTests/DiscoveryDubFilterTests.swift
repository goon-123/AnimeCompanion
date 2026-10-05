import XCTest
@testable import AnimeCore

final class DiscoveryDubFilterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2000)
    private func anime(_ json: String) throws -> Anime { try JSONDecoder().decode(Anime.self, from: Data(json.utf8)) }

    func testUnknownAndUnavailableProvidersAreNeverEvidenceOfNoDub() throws {
        let title = try anime(#"{"id":10,"idMal":20}"#)
        let unknown = LibraryDubProgress(anime: title, snapshot: nil, index: nil, now: now)
        XCTAssertTrue(DiscoveryDubFilter.all.matches(progress: nil, next: nil, now: now))
        XCTAssertFalse(DiscoveryDubFilter.available.matches(progress: unknown, next: nil, now: now))
        XCTAssertFalse(DiscoveryDubFilter.notReported.matches(progress: unknown, next: nil, now: now))
        XCTAssertFalse(DiscoveryDubFilter.notReported.matches(progress: nil, next: nil, now: now))
        let missingID = LibraryDubProgress(anime: Anime(id: 10, title: "Unknown"), snapshot: nil, index: DubIndex(dubbed: [], partial: []), now: now)
        XCTAssertFalse(DiscoveryDubFilter.notReported.matches(progress: missingID, next: nil, now: now))
    }
    func testRecordedAndPartialDubsAreAvailableWithoutInventingCounts() throws {
        let title = try anime(#"{"id":10,"idMal":20,"status":"RELEASING"}"#)
        let history = try JSONDecoder().decode([RawDubFeedItem].self, from: Data(#"[{"id":10,"episode":{"aired":6,"airedAt":1000}},{"id":10,"episode":{"aired":7,"airedAt":3000}}]"#.utf8))
        let recorded = LibraryDubProgress(anime: title, snapshot: DubSnapshot(upcoming: [], history: history), index: nil, now: now)
        XCTAssertEqual(recorded.released, 6)
        XCTAssertTrue(DiscoveryDubFilter.available.matches(progress: recorded, next: nil, now: now))
        let partial = LibraryDubProgress(anime: title, snapshot: nil, index: DubIndex(dubbed: [], partial: [20]), now: now)
        XCTAssertNil(partial.released)
        XCTAssertTrue(DiscoveryDubFilter.available.matches(progress: partial, next: nil, now: now))
        let estimate = ReleaseEvent(anime: title, episode: 7, kind: .dub, date: now.addingTimeInterval(60), certainty: .unverified)
        XCTAssertTrue(DiscoveryDubFilter.airing.matches(progress: partial, next: estimate, now: now))
        XCTAssertFalse(DiscoveryDubFilter.airing.matches(progress: partial, next: nil, now: now))
    }
    func testScheduledFilterRequiresVerifiedFutureDate() throws {
        let title = try anime(#"{"id":10,"idMal":20}"#)
        let progress = LibraryDubProgress(anime: title, snapshot: nil, index: nil, now: now)
        for certainty in [ScheduleCertainty.unverified, .delayed, .recorded] {
            let event = ReleaseEvent(anime: title, episode: 1, kind: .dub, date: now.addingTimeInterval(60), certainty: certainty)
            XCTAssertFalse(DiscoveryDubFilter.scheduled.matches(progress: progress, next: event, now: now))
        }
        let future = ReleaseEvent(anime: title, episode: 1, kind: .dub, date: now.addingTimeInterval(60), certainty: .verified)
        XCTAssertTrue(DiscoveryDubFilter.scheduled.matches(progress: progress, next: future, now: now))
        let past = ReleaseEvent(anime: title, episode: 1, kind: .dub, date: now.addingTimeInterval(-60), certainty: .verified)
        XCTAssertFalse(DiscoveryDubFilter.scheduled.matches(progress: progress, next: past, now: now))
    }
    func testAnnouncementDoesNotMatchNoDubReported() throws {
        let title = try anime(#"{"id":10,"idMal":20}"#)
        let index = DubIndex(dubbed: [], partial: [])
        let absent = LibraryDubProgress(anime: title, snapshot: nil, index: index, now: now)
        XCTAssertTrue(DiscoveryDubFilter.notReported.matches(progress: absent, next: nil, now: now))
        let upcoming = try JSONDecoder().decode([RawDubItem].self, from: Data(#"[{"episodeNumber":1,"episodeDate":3000,"verified":true,"media":{"media":{"id":10,"idMal":20}}}]"#.utf8))
        let announced = LibraryDubProgress(anime: title, snapshot: DubSnapshot(upcoming: upcoming, history: []), index: index, now: now)
        XCTAssertFalse(DiscoveryDubFilter.notReported.matches(progress: announced, next: nil, now: now))
        XCTAssertFalse(DiscoveryDubFilter.available.matches(progress: announced, next: nil, now: now))
    }
    func testRatingBoundaryCompletedAndRewatchingFilters() throws {
        let title = try anime(#"{"id":10,"averageScore":80}"#)
        var preferences = DiscoveryPreferences(); preferences.minimumScore = 80; preferences.hideCompleted = true
        let completed = try JSONDecoder().decode(LibraryEntry.self, from: Data(#"{"id":100,"mediaId":10,"status":"COMPLETED"}"#.utf8))
        let rewatch = try JSONDecoder().decode(LibraryEntry.self, from: Data(#"{"id":100,"mediaId":10,"status":"REPEATING"}"#.utf8))
        XCTAssertTrue(preferences.matches(anime: title, progress: nil, next: nil, entry: nil, now: now))
        XCTAssertFalse(preferences.matches(anime: title, progress: nil, next: nil, entry: completed, now: now))
        XCTAssertTrue(preferences.matches(anime: title, progress: nil, next: nil, entry: rewatch, now: now))
        preferences.minimumScore = 90
        XCTAssertFalse(preferences.matches(anime: title, progress: nil, next: nil, entry: nil, now: now))
        var query = DiscoveryFilters(category: .trending); query.minimumScore = 80
        let variables = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(query.variables(page: 1))) as? [String: Any])
        XCTAssertEqual(variables["minimumScore"] as? Int, 79, "AniList's greater-than filter must include exactly 8.0")
        query.minimumScore = 0
        XCTAssertNil(query.variables(page: 1)["minimumScore"])
    }
}
