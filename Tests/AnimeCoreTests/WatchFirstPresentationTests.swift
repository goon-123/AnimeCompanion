import XCTest
@testable import AnimeCore

final class WatchFirstPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000)
    private func entry(id: Int = 10, watched: Int = 4, status: String = "CURRENT", media: [String: Any] = [:], updated: Int = 1_000) throws -> LibraryEntry {
        let anime: [String: Any] = ["id": id, "episodes": 12, "format": "TV", "status": "FINISHED"]
            .merging(media) { _, new in new }
        return try JSONDecoder().decode(LibraryEntry.self, from: JSONSerialization.data(withJSONObject:
            ["id": id, "mediaId": id, "progress": watched, "status": status, "updatedAt": updated, "media": anime]))
    }
    func testQueueUsesAniListNextEpisodeAndIgnoresStaleAndLaterResume() throws {
        let tracked = try entry()
        let playback = ["10:1": PlaybackProgress(position: 100, duration: 1_400, finished: false),
                        "10:9": PlaybackProgress(position: 200, duration: 1_400, finished: false)]
        let item = try XCTUnwrap(ContinueWatchingItem.items(entries: [tracked], playback: playback, now: now).first)
        XCTAssertEqual(item.episode, 5)
        XCTAssertNil(item.resume)
        XCTAssertEqual(item.entry.progressValue, 4, "Building a watch queue must never change tracking")
    }
    func testMatchingEpisodeCarriesResumeAndFinishedRecordsDoNot() throws {
        let tracked = try entry()
        let saved = PlaybackProgress(position: 121, duration: 1_400, finished: false, updatedAt: now)
        let item = try XCTUnwrap(ContinueWatchingItem.items(entries: [tracked], playback: ["10:5": saved], now: now).first)
        XCTAssertEqual(item.resume?.position, 121)
        let finished = PlaybackProgress(position: 1_400, duration: 1_400, finished: true)
        XCTAssertNil(ContinueWatchingItem.items(entries: [tracked], playback: ["10:5": finished], now: now).first?.resume)
    }
    func testQueueExcludesCompletedDroppedPausedPlanningAndFullyWatchedTitles() throws {
        for status in ["COMPLETED", "DROPPED", "PAUSED", "PLANNING"] {
            XCTAssertTrue(ContinueWatchingItem.items(entries: [try entry(status: status)], playback: [:], now: now).isEmpty)
        }
        XCTAssertTrue(ContinueWatchingItem.items(entries: [try entry(watched: 12)], playback: [:], now: now).isEmpty)
        XCTAssertTrue(ContinueWatchingItem.items(entries: [try entry(watched: 99)], playback: [:], now: now).isEmpty)
    }
    func testRewatchesAndMoviesUseTheirOwnProgress() throws {
        let rewatch = try entry(watched: 0, status: "REPEATING")
        XCTAssertEqual(ContinueWatchingItem.items(entries: [rewatch], playback: [:], now: now).first?.episode, 1)
        let movie = try entry(id: 20, watched: 0, media: ["format": "MOVIE", "episodes": 1])
        XCTAssertEqual(ContinueWatchingItem.items(entries: [movie], playback: [:], now: now).first?.episode, 1)
        XCTAssertTrue(ContinueWatchingItem.items(entries: [try entry(watched: 1, media: ["format": "MOVIE", "episodes": 1])], playback: [:], now: now).isEmpty)
        XCTAssertNil(LibraryWatchProgress(anime: try XCTUnwrap(entry(media: ["format": "MOVIE", "episodes": NSNull()]).media), entry: try entry(watched: 1)).nextEpisode)
    }
    func testFutureAndCaughtUpBroadcastsDoNotOfferUnreleasedEpisodes() throws {
        let schedule: [String: Any] = ["status": "RELEASING", "nextAiringEpisode": ["episode": 7, "airingAt": 3_000]]
        XCTAssertTrue(ContinueWatchingItem.items(entries: [try entry(watched: 6, media: schedule)], playback: [:], now: now).isEmpty)
        XCTAssertEqual(ContinueWatchingItem.items(entries: [try entry(watched: 4, media: schedule)], playback: [:], now: now).first?.episode, 5)
        XCTAssertTrue(ContinueWatchingItem.items(entries: [try entry(watched: 0, media: ["status": "NOT_YET_RELEASED"])], playback: [:], now: now).isEmpty)
    }
    func testUnknownAndExpiredSchedulesDoNotInventAReleaseCount() throws {
        let schedules: [[String: Any]] = [["status": "RELEASING"],
                                    ["status": "RELEASING", "nextAiringEpisode": ["episode": 7, "airingAt": 1_000]],
                                    ["status": "RELEASING", "nextAiringEpisode": ["episode": 99, "airingAt": 3_000]]]
        for media in schedules {
            XCTAssertEqual(ContinueWatchingItem.items(entries: [try entry(watched: 6, media: media)], playback: [:], now: now).first?.episode, 7)
        }
    }
    func testQueueSortUsesMatchingResumeThenAniListUpdateWithStableTies() throws {
        let entries = try [entry(id: 10, updated: 1_500), entry(id: 20, updated: 1_500), entry(id: 30, updated: 1_000)]
        let saved = ["30:5": PlaybackProgress(position: 100, duration: nil, finished: false, updatedAt: now)]
        XCTAssertEqual(ContinueWatchingItem.items(entries: Array(entries.reversed()), playback: saved, now: now).map(\.id), [30, 10, 20])
    }
    func testInvalidResumePositionsCannotReachIntegerUIFormatting() throws {
        for position in [Double.nan, .infinity, -1, 0, Double.greatestFiniteMagnitude] {
            let saved = ["10:5": PlaybackProgress(position: position, duration: nil, finished: false)]
            XCTAssertNil(ContinueWatchingItem.items(entries: [try entry()], playback: saved, now: now).first?.resume)
        }
    }
    func testExplicitEpisodeChoiceIsBoundedButAutomaticSelectionStillUsesAniList() throws {
        let tracked = try entry(watched: 8)
        let anime = try XCTUnwrap(tracked.media)
        XCTAssertEqual(PlaybackEpisodeSelection.initial(anime: anime, entry: tracked, resumeEpisode: 1), 9)
        XCTAssertEqual(PlaybackEpisodeSelection.initial(anime: anime, entry: tracked, resumeEpisode: 1, requestedEpisode: 2), 2)
        XCTAssertEqual(PlaybackEpisodeSelection.initial(anime: anime, entry: tracked, resumeEpisode: 1, requestedEpisode: Int.max), 12)
        XCTAssertEqual(PlaybackEpisodeSelection.initial(anime: anime, entry: tracked, resumeEpisode: nil, requestedEpisode: -4), 1)
        let movie = try XCTUnwrap(entry(media: ["format": "MOVIE", "episodes": 1]).media)
        XCTAssertEqual(PlaybackEpisodeSelection.initial(anime: movie, entry: nil, resumeEpisode: nil, requestedEpisode: 5), 1)
    }
    func testEpisodeListIsBoundedPaginatedAndDoesNotInventUnknownTotals() throws {
        let anime = try XCTUnwrap(entry(media: ["episodes": 100]).media)
        XCTAssertEqual(AnimeEpisodeCatalog.episodes(anime: anime, visibleLimit: 24), Array(1...24))
        XCTAssertEqual(AnimeEpisodeCatalog.episodes(anime: anime, visibleLimit: 120), Array(1...100))
        XCTAssertTrue(AnimeEpisodeCatalog.episodes(anime: anime, visibleLimit: 0).isEmpty)
        XCTAssertTrue(AnimeEpisodeCatalog.episodes(anime: Anime(id: 10, title: "Unknown"), visibleLimit: 24).isEmpty)
        let movie = try XCTUnwrap(entry(media: ["format": "MOVIE"]).media)
        XCTAssertEqual(AnimeEpisodeCatalog.episodes(anime: movie, visibleLimit: 24), [1])
        let huge = try XCTUnwrap(entry(media: ["episodes": Int.max]).media)
        XCTAssertEqual(AnimeEpisodeCatalog.episodes(anime: huge, visibleLimit: Int.max).count, 100_000)
    }
    func testAiringGroupsKeepUnknownAndUpcomingOutOfReadyAndCaughtUp() {
        XCTAssertEqual(AiringWatchlistGroup(state: .behind), .ready)
        XCTAssertEqual(AiringWatchlistGroup(state: .caughtUp), .caughtUp)
        XCTAssertEqual(AiringWatchlistGroup(state: .waiting), .upcoming)
        XCTAssertEqual(AiringWatchlistGroup(state: .unknown), .unverified)
        XCTAssertEqual(AiringWatchlistGroup.allCases, [.ready, .caughtUp, .upcoming, .unverified])
    }
    func testBalancedHeroKeepsImmersiveAndCustomPreferencesAvailable() {
        XCTAssertEqual(PosterLayout.featuredHeight(preferred: 620, viewportHeight: 800, fillScreen: true, balanced: true), 480)
        XCTAssertEqual(PosterLayout.featuredHeight(preferred: 700, viewportHeight: 1_100, fillScreen: true, balanced: true), 660)
        XCTAssertEqual(PosterLayout.featuredHeight(preferred: 620, viewportHeight: 800, fillScreen: true, balanced: false), 704)
        XCTAssertEqual(PosterLayout.featuredHeight(preferred: 620, viewportHeight: 800, fillScreen: false, balanced: true), 620)
        XCTAssertEqual(PosterLayout.featuredHeight(preferred: .nan, viewportHeight: .nan, fillScreen: true, balanced: true), 480)
    }
}
