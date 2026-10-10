import XCTest
@testable import AnimeCore
import Foundation

final class DiscoveryPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2000)
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    private func anime(status: String = "RELEASING") throws -> Anime {
        try decode(Anime.self, "{\"id\":10,\"idMal\":20,\"status\":\"\(status)\",\"episodes\":12,\"nextAiringEpisode\":{\"episode\":7,\"airingAt\":3000}}")
    }
    private func schedule(episode: Int) throws -> DubSnapshot {
        DubSnapshot(upcoming: try decode([RawDubItem].self,
            "[{\"episodeNumber\":\(episode),\"episodeDate\":3000,\"verified\":true,\"media\":{\"media\":{\"id\":10,\"idMal\":20}}}]"), history: [])
    }

    func testGreenDotRequiresReleasingStatusNotJustAFutureEpisode() throws {
        XCTAssertTrue(try anime().isCurrentlyAiring)
        for status in ["NOT_YET_RELEASED", "FINISHED", "HIATUS", "CANCELLED", "UNKNOWN"] {
            XCTAssertFalse(try anime(status: status).isCurrentlyAiring, status)
        }
        XCTAssertFalse(Anime(id: 10, title: "Missing status").isCurrentlyAiring)
    }
    func testReportedDubUsesShortAvailabilityWithoutChangingDetailedCount() throws {
        let title = try anime()
        let feed = try decode([RawDubFeedItem].self, #"[{"id":10,"episode":{"aired":2,"airedAt":1000}}]"#)
        let progress = LibraryDubProgress(anime: title, snapshot: DubSnapshot(upcoming: [], history: feed), index: nil, now: now)
        XCTAssertEqual(progress.discoveryStatus, .available)
        XCTAssertEqual(progress.discoveryStatus.label, "Dub available")
        XCTAssertEqual(progress.discoveryStatus.tone, .available)
        XCTAssertEqual(progress.label(for: title, now: now), "Dub 2/6 released")
        XCTAssertEqual(progress.released, 2)
    }
    func testKnownAvailabilityDoesNotRequireAnEpisodeCount() throws {
        let progress = LibraryDubProgress(anime: try anime(), snapshot: nil, index: DubIndex(dubbed: [20], partial: []), now: now)
        XCTAssertNil(progress.released)
        XCTAssertEqual(progress.discoveryStatus, .available)
    }
    func testCompletedListingAvailabilityIsGreenWhileItsCountStaysEstimated() throws {
        let title = try anime(status: "FINISHED")
        let progress = LibraryDubProgress(anime: title, snapshot: nil, index: DubIndex(dubbed: [20], partial: []), now: now)
        XCTAssertEqual(progress.discoveryStatus, .available)
        XCTAssertEqual(progress.discoveryStatus.tone, .available)
        XCTAssertEqual(progress.confidence, .estimated)
        XCTAssertTrue(progress.label(for: title, now: now).contains("estimated"))
        XCTAssertFalse(title.isCurrentlyAiring)
    }
    func testPartialDubKeepsItsDistinctShortLabel() throws {
        let progress = LibraryDubProgress(anime: try anime(), snapshot: nil, index: DubIndex(dubbed: [], partial: [20]), now: now)
        XCTAssertEqual(progress.discoveryStatus, .partial)
        XCTAssertEqual(progress.discoveryStatus.label, "Partial dub")
        XCTAssertEqual(progress.discoveryStatus.tone, .available)
    }
    func testScheduleInferenceAloneCannotBecomeConfirmedAvailability() throws {
        let progress = LibraryDubProgress(anime: try anime(), snapshot: try schedule(episode: 3), index: nil, now: now)
        XCTAssertEqual(progress.released, 2)
        XCTAssertEqual(progress.discoveryStatus, .estimated)
        XCTAssertEqual(progress.discoveryStatus.label, "Dub estimated")
        XCTAssertEqual(progress.discoveryStatus.tone, .estimated)
    }
    func testPremiereAnnouncementIsNotAnAvailableDubEvenWithAListing() throws {
        for index in [nil, DubIndex(dubbed: [20], partial: [])] as [DubIndex?] {
            let progress = LibraryDubProgress(anime: try anime(status: "NOT_YET_RELEASED"), snapshot: try schedule(episode: 1), index: index, now: now)
            XCTAssertNil(progress.released)
            XCTAssertEqual(progress.discoveryStatus, .announced)
            XCTAssertEqual(progress.discoveryStatus.tone, .announced)
        }
    }
    func testUncorroboratedSourceStaysUnconfirmed() throws {
        let progress = LibraryDubProgress(anime: try anime(), snapshot: nil, index: DubIndex(dubbed: [], partial: [], sourceCounts: [20: 1]), now: now)
        XCTAssertEqual(progress.discoveryStatus, .unconfirmed)
        XCTAssertEqual(progress.discoveryStatus.label, "Dub unconfirmed")
        XCTAssertEqual(progress.discoveryStatus.tone, .estimated)
        XCTAssertNil(progress.released)
    }
    func testUnknownDataDiffersFromNoDubReported() throws {
        let title = try anime()
        let unknown = LibraryDubProgress(anime: title, snapshot: nil, index: nil, now: now)
        let notReported = LibraryDubProgress(anime: title, snapshot: nil, index: DubIndex(dubbed: [], partial: []), now: now)
        XCTAssertEqual(unknown.discoveryStatus, .unknown)
        XCTAssertEqual(unknown.discoveryStatus.label, "Dub unknown")
        XCTAssertEqual(notReported.discoveryStatus, .notReported)
        XCTAssertEqual(notReported.discoveryStatus.label, "No dub reported")
        XCTAssertEqual(unknown.discoveryStatus.tone, .neutral)
        XCTAssertEqual(notReported.discoveryStatus.tone, .neutral)
    }
}
