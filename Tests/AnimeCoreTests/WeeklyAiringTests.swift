import XCTest
@testable import AnimeCore
import Foundation

final class WeeklyAiringTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_795_372_200)

    private func anime(_ id: Int, status: String?) throws -> Anime {
        var object: [String: Any] = ["id": id, "title": ["english": "Series \(id)"]]
        if let status { object["status"] = status }
        return try JSONDecoder().decode(Anime.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func event(_ anime: Anime, kind: ReleaseKind = .sub, certainty: ScheduleCertainty = .broadcast) -> ReleaseEvent {
        ReleaseEvent(anime: anime, episode: 9, kind: kind, date: now, certainty: certainty)
    }

    func testFinishedBroadcastIsHiddenEvenWhenDubEpisodesAreStillReleasing() throws {
        let finished = try anime(1, status: "FINISHED")
        let events = [event(finished), event(finished, kind: .dub, certainty: .verified),
                      event(finished, kind: .dub, certainty: .recorded)]
        XCTAssertTrue(WeeklyAiring.events(from: events).isEmpty)
        // Filtering the widget must not delete releases from the full calendar.
        XCTAssertEqual(ScheduleDayReleases(on: now, events: events, now: now).events.count, 2)
    }

    func testFinishedLibraryMetadataRejectsStaleNextEpisodeAndDubEvents() throws {
        let stale = try anime(1, status: "RELEASING")
        let finished = try anime(1, status: "FINISHED")
        XCTAssertTrue(WeeklyAiring.events(from: [event(stale), event(stale, kind: .dub, certainty: .unverified)],
                                         metadata: [finished]).isEmpty)
    }

    func testDubSourceFinishedStatusWinsWhenLibraryCopyIsStillReleasing() throws {
        let source = try JSONDecoder().decode(RawDubItem.self, from: Data("""
        {"episodeNumber":9,"episodeDate":1795372200,"verified":true,
         "media":{"media":{"id":1,"status":"FINISHED","episodes":10}}}
        """.utf8))
        let snapshot = DubSnapshot(upcoming: [source], history: [])
        let stale = try anime(1, status: "RELEASING")
        let events = snapshot.events(knownMedia: [1: stale], now: now)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.anime.status, "RELEASING")
        XCTAssertTrue(WeeklyAiring.events(from: events, metadata: [stale] + snapshot.upcoming.compactMap { $0.media?.media }).isEmpty)
    }

    func testTerminalStatusRejectsEveryCopyWithoutHidingAnotherSeason() throws {
        let old = try anime(1, status: "RELEASING")
        let finished = try anime(1, status: "FINISHED")
        let sequel = try anime(2, status: "RELEASING")
        let cancelled = try anime(3, status: "CANCELLED")
        let events = [event(old, kind: .dub), event(sequel), event(finished), event(cancelled)]
        XCTAssertEqual(WeeklyAiring.events(from: events).map(\.anime.id), [2])
        XCTAssertEqual(WeeklyAiring.events(from: Array(events.reversed())).map(\.anime.id), [2])
    }

    func testActivePremiereAndUnknownStatusKeepDatedReleasesAndPosterDeduplication() throws {
        let ongoing = try anime(1, status: "RELEASING")
        let premiere = try anime(2, status: "NOT_YET_RELEASED")
        let unknown = try anime(3, status: nil)
        let events = [event(ongoing), event(ongoing, kind: .dub, certainty: .verified), event(premiere), event(unknown)]
        let eligible = WeeklyAiring.events(from: events)
        XCTAssertEqual(eligible.map(\.id), events.map(\.id))
        XCTAssertEqual(ScheduleDayReleases(on: now, events: eligible, now: now).trackedAnime(ids: [1, 2]).map(\.id), [1, 2])
    }
}
