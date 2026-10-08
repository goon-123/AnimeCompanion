import XCTest
@testable import AnimeCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class DubEvidenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2000)
    private func anime(_ json: String) throws -> Anime { try decode(Anime.self, json) }
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    private func snapshot(_ schedule: String = "[]", _ history: String = "[]") throws -> DubSnapshot {
        DubSnapshot(upcoming: try decode([RawDubItem].self, schedule), history: try decode([RawDubFeedItem].self, history))
    }

    func testPremiereBatchReportsTwoEpisodesAndKeepsTheNextDateEstimated() throws {
        let title = try anime(#"{"id":169581,"idMal":56733,"episodes":13,"status":"RELEASING","nextAiringEpisode":{"episode":3,"airingAt":3000}}"#)
        let data = try snapshot(
            #"[{"episodeNumber":3,"episodeDate":4000,"verified":false,"media":{"media":{"id":169581,"idMal":56733}}}]"#,
            #"[{"id":169581,"idMal":56733,"episode":{"aired":1,"airedAt":1000}},{"id":169581,"idMal":56733,"episode":{"aired":2,"airedAt":1000}}]"#)
        let progress = LibraryDubProgress(anime: title, snapshot: data, index: DubIndex(dubbed: [56733], partial: [], sourceCounts: [56733: 4]), now: now)
        XCTAssertEqual(progress.released, 2)
        XCTAssertEqual(progress.label(for: title, now: now), "Dub 2/2 released")
        XCTAssertEqual(progress.confidence, .reported)
        XCTAssertEqual(progress.tone, .available)
        XCTAssertEqual(progress.agreeingSources, 4)
        XCTAssertEqual(data.events(now: now).first { $0.episode == 3 }?.certainty, .unverified)
    }

    func testSourceAgreementCountsAreNotEpisodeCounts() throws {
        let counts = try decode(DubSourceCounts.self, #"{"20":4,"30":1,"partial":[30],"metadata":{"version":2}}"#)
        XCTAssertEqual(counts.sources, [20: 4, 30: 1])
        XCTAssertEqual(counts.partial, [30])
        let title = try anime(#"{"id":10,"idMal":20,"status":"RELEASING"}"#)
        let progress = LibraryDubProgress(anime: title, snapshot: nil, index: DubIndex(dubbed: [20], partial: [], sourceCounts: counts.sources), now: now)
        XCTAssertNil(progress.released)
        XCTAssertEqual(progress.agreeingSources, 4)
        XCTAssertEqual(progress.tone, .available, "An available dub stays visible even when no episode count is supplied.")
        XCTAssertThrowsError(try decode(DubSourceCounts.self, #"{"changed_schema":[]}"#))
    }

    func testFinishedOriginalBroadcastNeverOverridesAStillReleasingDub() throws {
        let title = try anime(#"{"id":10,"idMal":20,"status":"FINISHED","episodes":12}"#)
        let data = try snapshot(
            #"[{"episodeNumber":7,"episodeDate":3000,"verified":true,"media":{"media":{"id":10,"idMal":20}}}]"#,
            #"[{"id":10,"episode":{"aired":6,"airedAt":1000}}]"#)
        let progress = LibraryDubProgress(anime: title, snapshot: data, index: DubIndex(dubbed: [20], partial: []), now: now)
        XCTAssertEqual(progress.released, 6)
        XCTAssertFalse(progress.completeListing)
        XCTAssertEqual(progress.confidence, .reported)
    }

    func testScheduleFallbackIsExplicitlyEstimatedAndDoesNotInventAReleaseDate() throws {
        let title = try anime(#"{"id":10,"idMal":20,"status":"RELEASING","episodes":12,"nextAiringEpisode":{"episode":5,"airingAt":5000}}"#)
        let data = try snapshot(#"[{"episodeNumber":3,"episodeDate":3000,"verified":false,"media":{"media":{"id":10}}}]"#)
        let progress = LibraryDubProgress(anime: title, snapshot: data, index: nil, now: now)
        XCTAssertEqual(progress.released, 2)
        XCTAssertEqual(progress.confidence, .estimated)
        XCTAssertEqual(progress.label(for: title, now: now), "Dub ~2/4 · estimated")
        XCTAssertEqual(progress.tone, .estimated)
        XCTAssertNil(progress.lastReleaseAt)
        XCTAssertTrue(data.events(now: now).allSatisfy { $0.certainty != .recorded })
    }

    func testDistantPastDelayedAndNotYetReleasedSchedulesNeverInventCounts() throws {
        let title = try anime(#"{"id":10,"status":"RELEASING"}"#)
        for entry in [
            #"{"episodeNumber":3,"episodeDate":1000,"media":{"media":{"id":10}}}"#,
            #"{"episodeNumber":3,"episodeDate":2000000,"media":{"media":{"id":10}}}"#,
            #"{"episodeNumber":3,"episodeDate":3000,"delayedIndefinitely":true,"media":{"media":{"id":10}}}"#,
            #"{"episodeNumber":3,"episodeDate":3000,"delayedUntil":4000,"media":{"media":{"id":10}}}"#,
            #"{"episodeNumber":1,"episodeDate":3000,"media":{"media":{"id":10}}}"#
        ] {
            let progress = LibraryDubProgress(anime: title, snapshot: try snapshot("[\(entry)]"), index: nil, now: now)
            XCTAssertNil(progress.released)
        }
        let future = try anime(#"{"id":10,"status":"NOT_YET_RELEASED"}"#)
        let progress = LibraryDubProgress(anime: future, snapshot: try snapshot(#"[{"episodeNumber":3,"episodeDate":3000,"media":{"media":{"id":10}}}]"#), index: nil, now: now)
        XCTAssertNil(progress.released)
    }

    func testMALMappingResolvesHistoryButRejectsContradictoryIDsAndImpossibleEpisodes() throws {
        let title = try anime(#"{"id":10,"idMal":20,"episodes":12,"status":"RELEASING"}"#)
        let data = try snapshot(
            #"[{"route":"example-anime","episodeNumber":3,"episodeDate":3000,"verified":true,"media":{"media":{"id":999,"idMal":20}}}]"#,
            #"[{"id":999,"idMal":20,"episode":{"aired":2,"airedAt":1000}},{"id":10,"idMal":99,"episode":{"aired":8,"airedAt":1000}},{"id":10,"episode":{"aired":13,"airedAt":1000}},{"id":10,"episode":{"aired":3,"airedAt":3000}}]"#)
        let progress = LibraryDubProgress(anime: title, snapshot: data, index: nil, now: now)
        XCTAssertEqual(progress.released, 2)
        let events = data.events(knownMedia: [title.id: title], now: now)
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy { $0.anime.id == title.id })
        XCTAssertEqual(events.first?.anime.id, title.id)
        XCTAssertEqual(events.first?.episode, 2)
        XCTAssertEqual(data.schedulePage(for: title)?.absoluteString, "https://animeschedule.net/anime/example-anime")
    }

    func testCompletedListingInferenceIsLabeledEstimated() throws {
        let title = try anime(#"{"id":10,"idMal":20,"status":"FINISHED","episodes":12}"#)
        let progress = LibraryDubProgress(anime: title, snapshot: nil, index: DubIndex(dubbed: [20], partial: []), now: now)
        XCTAssertEqual(progress.released, 12)
        XCTAssertTrue(progress.completeListing)
        XCTAssertEqual(progress.confidence, .estimated)
        XCTAssertTrue(progress.label(for: title).contains("estimated"))
    }

    func testPostponedEventUsesTheReplacementDate() throws {
        let data = try snapshot(#"[{"episodeNumber":3,"episodeDate":1000,"delayedUntil":4000,"media":{"media":{"id":10}}}]"#)
        XCTAssertEqual(data.events(now: now).first?.date, Date(timeIntervalSince1970: 4000))
        XCTAssertEqual(data.events(now: now).first?.certainty, .delayed)
    }

    func testHistoryOutagePreservesScheduleAndWarns() async throws {
        let transport = DubEvidenceTransport([
            DubClient.scheduleURL: (200, #"[{"episodeNumber":3,"episodeDate":3000,"media":{"media":{"id":10}}}]"#),
            DubClient.feedURL: (503, ""), DubProvider.legacy.url(for: "dub-episode-feed.json"): (503, ""),
            DubClient.manifestURL: (200, #"{"dubbed":{"schedule":2000,"episodes":2000}}"#)
        ])
        let data = try await DubClient(transport: transport).snapshot()
        XCTAssertEqual(data.upcoming.count, 1)
        XCTAssertTrue(data.history.isEmpty)
        XCTAssertNil(data.historyProvider)
        XCTAssertFalse(data.warnings(now: now).isEmpty)
    }

    func testScheduleOutagePreservesHistoryAndLegacyFallbackIsVisible() async throws {
        let legacy = DubProvider.legacy
        let transport = DubEvidenceTransport([
            DubClient.scheduleURL: (503, ""), legacy.url(for: "dub-schedule.json"): (503, ""),
            DubClient.feedURL: (503, ""), legacy.url(for: "dub-episode-feed.json"): (200, #"[{"id":10,"episode":{"aired":2,"airedAt":1000}}]"#),
            legacy.url(for: "last-updated.json"): (200, #"{"dubbed":{"episodes":1000}}"#)
        ])
        let data = try await DubClient(transport: transport).snapshot()
        XCTAssertEqual(data.history.count, 1)
        XCTAssertEqual(data.historyProvider, .legacy)
        XCTAssertNil(data.scheduleProvider)
        XCTAssertTrue(data.warnings(now: now).contains { $0.contains("fallback") })
    }

    func testIndexFallbackUsesTwoSourcesAndKeepsPartialListings() async throws {
        let transport = DubEvidenceTransport([
            DubClient.indexURL: (503, ""),
            DubClient.countsURL: (200, #"{"20":4,"30":1,"40":3,"partial":[40]}"#)
        ])
        let index = try await DubClient(transport: transport).index()
        XCTAssertEqual(index.availability(malId: 20), .dubbed)
        XCTAssertEqual(index.availability(malId: 30), .unknown)
        XCTAssertEqual(index.availability(malId: 40), .partial)
        XCTAssertEqual(index.agreeingSources(malId: 20), 4)
    }

    func testCorroboratedCountsCanFillAnAvailabilityIndexThatIsBehind() async throws {
        let transport = DubEvidenceTransport([
            DubClient.indexURL: (200, #"{"dubbed":[50]}"#),
            DubClient.countsURL: (200, #"{"20":4,"30":1,"partial":[]}"#)
        ])
        let index = try await DubClient(transport: transport).index()
        XCTAssertEqual(index.availability(malId: 20), .dubbed)
        XCTAssertEqual(index.availability(malId: 30), .unknown)
        XCTAssertEqual(index.availability(malId: 50), .dubbed, "Curated listings remain available even without a source-count entry.")
    }

    func testStaleFeedIsDetectedEvenWhenDownloadSucceeds() throws {
        let data = DubSnapshot(upcoming: [], history: [], scheduleUpdatedAt: now.addingTimeInterval(-4 * 86400), historyUpdatedAt: now)
        XCTAssertTrue(data.warnings(now: now).contains { $0.contains("schedule has not updated") })
        XCTAssertFalse(data.warnings(now: now).contains { $0.contains("release feed has not updated") })
    }

    func testConcurrentRefreshesShareTheReleaseRequests() async throws {
        let transport = DubEvidenceTransport([
            DubClient.scheduleURL: (200, "[]"), DubClient.feedURL: (200, "[]"),
            DubClient.manifestURL: (200, #"{"dubbed":{"schedule":2000,"episodes":2000}}"#)
        ])
        let client = DubClient(transport: transport)
        async let first = client.snapshot(refresh: true)
        async let second = client.snapshot(refresh: true)
        let (a, b) = try await (first, second)
        XCTAssertEqual(a.fetchedAt, b.fetchedAt)
        let calls = await transport.calls
        XCTAssertEqual(calls[DubClient.feedURL], 1)
        XCTAssertEqual(calls[DubClient.scheduleURL], 1)
    }

    func testStalledSuccessfulFeedUsesNewerAlternateWithoutReplacingFreshSchedule() async throws {
        let current = Date(), old = current.addingTimeInterval(-4 * 86400)
        let legacy = DubProvider.legacy
        let transport = DubEvidenceTransport([
            DubClient.scheduleURL: (200, #"[{"episodeNumber":3,"media":{"media":{"id":10}}}]"#),
            DubClient.feedURL: (200, #"[{"id":10,"episode":{"aired":1,"airedAt":1000}}]"#),
            DubClient.manifestURL: (200, "{\"dubbed\":{\"schedule\":\(current.timeIntervalSince1970),\"episodes\":\(old.timeIntervalSince1970)}}"),
            legacy.url(for: "last-updated.json"): (200, "{\"dubbed\":{\"schedule\":\(old.timeIntervalSince1970),\"episodes\":\(current.timeIntervalSince1970)}}"),
            legacy.url(for: "dub-episode-feed.json"): (200, #"[{"id":10,"episode":{"aired":2,"airedAt":1000}}]"#)
        ])
        let data = try await DubClient(transport: transport).snapshot(refresh: true)
        XCTAssertEqual(data.history.first?.episode.aired, 2)
        XCTAssertEqual(data.historyProvider, .legacy)
        XCTAssertEqual(try XCTUnwrap(data.historyUpdatedAt).timeIntervalSince1970, current.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(data.scheduleProvider, .current)
        XCTAssertEqual(data.upcoming.first?.episodeNumber, 3)
        XCTAssertFalse(data.warnings().contains { $0.contains("has not updated") })
        let calls = await transport.calls
        XCTAssertNil(calls[legacy.url(for: "dub-schedule.json")])
    }

    func testOlderAlternateCannotReplaceAStalledPrimaryFeed() async throws {
        let old = Date().addingTimeInterval(-4 * 86400), older = Date().addingTimeInterval(-30 * 86400)
        let legacy = DubProvider.legacy
        let transport = DubEvidenceTransport([
            DubClient.scheduleURL: (200, "[]"), DubClient.feedURL: (200, #"[{"id":10,"episode":{"aired":2,"airedAt":1000}}]"#),
            DubClient.manifestURL: (200, "{\"dubbed\":{\"schedule\":\(old.timeIntervalSince1970),\"episodes\":\(old.timeIntervalSince1970)}}"),
            legacy.url(for: "last-updated.json"): (200, "{\"dubbed\":{\"schedule\":\(older.timeIntervalSince1970),\"episodes\":\(older.timeIntervalSince1970)}}")
        ])
        let data = try await DubClient(transport: transport).snapshot()
        XCTAssertEqual(data.historyProvider, .current)
        XCTAssertEqual(data.history.first?.episode.aired, 2)
        XCTAssertTrue(data.warnings().contains { $0.contains("release feed has not updated") })
        let calls = await transport.calls
        XCTAssertNil(calls[legacy.url(for: "dub-episode-feed.json")])
    }

    func testFreshPrimaryDoesNotRequestTheAlternate() async throws {
        let current = Date().timeIntervalSince1970
        let transport = DubEvidenceTransport([
            DubClient.scheduleURL: (200, "[]"), DubClient.feedURL: (200, "[]"),
            DubClient.manifestURL: (200, "{\"dubbed\":{\"schedule\":\(current),\"episodes\":\(current)}}")
        ])
        let data = try await DubClient(transport: transport).snapshot()
        XCTAssertTrue(data.warnings().isEmpty)
        let calls = await transport.calls
        XCTAssertNil(calls[DubProvider.legacy.url(for: "last-updated.json")])
    }

    func testFailedNewerAlternatePreservesPrimaryEpisodesAndStaleNotice() async throws {
        let current = Date().timeIntervalSince1970, old = Date().addingTimeInterval(-4 * 86400).timeIntervalSince1970
        let legacy = DubProvider.legacy
        let transport = DubEvidenceTransport([
            DubClient.scheduleURL: (200, "[]"), DubClient.feedURL: (200, #"[{"id":10,"episode":{"aired":2,"airedAt":1000}}]"#),
            DubClient.manifestURL: (200, "{\"dubbed\":{\"schedule\":\(current),\"episodes\":\(old)}}"),
            legacy.url(for: "last-updated.json"): (200, "{\"dubbed\":{\"episodes\":\(current)}}"),
            legacy.url(for: "dub-episode-feed.json"): (503, "")
        ])
        let data = try await DubClient(transport: transport).snapshot()
        XCTAssertEqual(data.historyProvider, .current)
        XCTAssertEqual(data.history.first?.episode.aired, 2)
        XCTAssertTrue(data.warnings().contains { $0.contains("release feed has not updated") })
    }

    func testForcedRefreshGetsNewEpisodesAndAvailabilityDespiteFreshCaches() async throws {
        let current = Date().timeIntervalSince1970
        let transport = DubEvidenceTransport([
            DubClient.scheduleURL: (200, "[]"), DubClient.feedURL: (200, #"[{"id":10,"episode":{"aired":1,"airedAt":1000}}]"#),
            DubClient.manifestURL: (200, "{\"dubbed\":{\"schedule\":\(current),\"episodes\":\(current)}}"),
            DubClient.indexURL: (200, #"{"dubbed":[20]}"#), DubClient.countsURL: (200, #"{"20":2,"partial":[]}"#)
        ])
        let client = DubClient(transport: transport)
        _ = try await client.snapshot(); _ = try await client.index()
        await transport.setResponse(for: DubClient.feedURL, status: 200, body: #"[{"id":10,"episode":{"aired":2,"airedAt":1000}}]"#)
        await transport.setResponse(for: DubClient.countsURL, status: 200, body: #"{"20":2,"30":4,"partial":[]}"#)
        let cached = try await client.snapshot(), cachedIndex = try await client.index()
        XCTAssertEqual(cached.history.first?.episode.aired, 1)
        XCTAssertEqual(cachedIndex.availability(malId: 30), .notReported)
        let updated = try await client.snapshot(refresh: true), updatedIndex = try await client.index(refresh: true)
        XCTAssertEqual(updated.history.first?.episode.aired, 2)
        XCTAssertEqual(updatedIndex.availability(malId: 30), .dubbed)
        let calls = await transport.calls, policies = await transport.cachePolicies
        XCTAssertEqual(calls[DubClient.feedURL], 2)
        XCTAssertEqual(calls[DubClient.countsURL], 2)
        XCTAssertTrue(policies.allSatisfy { $0 == .reloadIgnoringLocalCacheData })
    }

    func testRefreshCanRecoverAfterAFailedRequestAndKeepsThePreviousCache() async throws {
        let transport = DubEvidenceTransport([
            DubClient.scheduleURL: (200, "[]"), DubClient.feedURL: (200, #"[{"id":10,"episode":{"aired":1,"airedAt":1000}}]"#)
        ])
        let client = DubClient(transport: transport)
        _ = try await client.snapshot()
        await transport.setResponse(for: DubClient.scheduleURL, status: 503, body: "")
        await transport.setResponse(for: DubClient.feedURL, status: 503, body: "")
        do { _ = try await client.snapshot(refresh: true); XCTFail("A total outage must not appear as a successful empty feed.") }
        catch { }
        let cached = try await client.snapshot()
        XCTAssertEqual(cached.history.first?.episode.aired, 1)
        await transport.setResponse(for: DubClient.feedURL, status: 200, body: #"[{"id":10,"episode":{"aired":2,"airedAt":1000}}]"#)
        let recovered = try await client.snapshot(refresh: true)
        XCTAssertEqual(recovered.history.first?.episode.aired, 2)
    }
}

private actor DubEvidenceTransport: HTTPTransport {
    private var responses: [URL: (Int, String)]
    private(set) var calls: [URL: Int] = [:]
    private(set) var cachePolicies: [URLRequest.CachePolicy] = []
    init(_ responses: [URL: (Int, String)]) { self.responses = responses }
    func setResponse(for url: URL, status: Int, body: String) { responses[url] = (status, body) }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw ServiceError.invalidResponse }
        calls[url, default: 0] += 1
        cachePolicies.append(request.cachePolicy)
        guard let (status, body) = responses[url] else { throw ServiceError.invalidResponse }
        try await Task.sleep(nanoseconds: 1_000_000)
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
