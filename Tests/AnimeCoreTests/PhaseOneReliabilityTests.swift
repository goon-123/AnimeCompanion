import XCTest
@testable import AnimeCore

final class PhaseOneReliabilityTests: XCTestCase {
    private func stream(_ fields: [String: Any]) throws -> StremioStream {
        try JSONDecoder().decode(StremioStream.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    private func anime(_ fields: [String: Any] = [:]) throws -> Anime {
        try JSONDecoder().decode(Anime.self, from: JSONSerialization.data(withJSONObject: ["id": 10, "episodes": 12].merging(fields) { _, new in new }))
    }
    private func entry(_ progress: Int, status: String = "CURRENT", mediaID: Int = 10) throws -> LibraryEntry {
        try JSONDecoder().decode(LibraryEntry.self, from: JSONSerialization.data(withJSONObject:
            ["id": 100, "mediaId": mediaID, "status": status, "progress": progress]))
    }
    func testSourceRowsRemoveBrokenExpressionsButRetainUsefulMetadata() throws {
        let source = try stream(["name": "  Provider   1080p  ",
            "description": "1080p · English + Japanese\ninvalid expression(stream.audio.join(','))\n2.4 GB\n${stream.codec}",
            "url": "https://video.example/9.mkv?token=a%2Bb"])
        XCTAssertEqual(source.displayName, "Provider 1080p")
        XCTAssertEqual(source.details, "1080p · English + Japanese\n2.4 GB")
        XCTAssertEqual(source.description, "1080p · English + Japanese\ninvalid expression(stream.audio.join(','))\n2.4 GB\n${stream.codec}", "Original text remains available on demand")
        XCTAssertEqual(source.videoURL?.absoluteString, "https://video.example/9.mkv?token=a%2Bb", "Cleaning display text must not rewrite playback URLs")
    }
    func testBrokenOrBlankDescriptionsFallBackToTitleThenFilename() throws {
        let source = try stream(["name": "invalid expression(provider.name)", "description": "\n \n", "title": "  English audio  "])
        XCTAssertEqual(source.displayName, "Video source"); XCTAssertEqual(source.details, "English audio")
        let filename = try stream(["description": "invalid expression(audio)", "title": "{{title}}", "behaviorHints": ["filename": "Show.S01E09.1080p.mkv"]])
        XCTAssertEqual(filename.details, "Show.S01E09.1080p.mkv")
        XCTAssertEqual(try stream([:]).details, "Source details unavailable")
    }
    func testSourceTextNormalizesEscapedNewlinesDuplicatesAndTerminalCodes() {
        XCTAssertEqual(PlaybackSourceText.clean("\u{001B}[31m1080p\u{001B}[0m\\nEnglish\\nEnglish\r\n2 GB"), "1080p\nEnglish\n2 GB")
        XCTAssertNil(PlaybackSourceText.clean(" \n\t"))
        XCTAssertNil(PlaybackSourceText.clean("TypeError: stream.audio is undefined"))
        XCTAssertEqual(PlaybackSourceText.clean("A\nB\nC", maximumLines: 2), "A\nB")
        XCTAssertEqual(PlaybackSourceText.clean(String(repeating: "x", count: 2_000))?.count, 281)
    }
    func testLibraryNextEpisodeUsesWatchedProgressWithoutAddingAiringStatus() throws {
        let progress = LibraryWatchProgress(anime: try anime(), entry: try entry(4))
        XCTAssertEqual(progress.nextEpisode, 5); XCTAssertEqual(progress.label, "Next: Ep 5")
        XCTAssertEqual(LibraryWatchProgress(anime: try anime(), entry: try entry(0, status: "REPEATING")).nextEpisode, 1)
        XCTAssertEqual(LibraryWatchProgress(anime: try anime(), entry: try entry(4, status: "PAUSED")).nextEpisode, 5)
    }
    func testCompletedAndUnreleasedTitlesDoNotAdvertiseANonexistentNextEpisode() throws {
        for count in [12, 99] {
            let progress = LibraryWatchProgress(anime: try anime(), entry: try entry(count))
            XCTAssertNil(progress.nextEpisode); XCTAssertEqual(progress.label, "All episodes watched")
        }
        XCTAssertNil(LibraryWatchProgress(anime: try anime(), entry: try entry(4, status: "COMPLETED")).nextEpisode)
        let upcoming = LibraryWatchProgress(anime: try anime(["status": "NOT_YET_RELEASED"]), entry: try entry(0))
        XCTAssertNil(upcoming.nextEpisode); XCTAssertEqual(upcoming.label, "Not yet released")
        XCTAssertEqual(LibraryWatchProgress(anime: try anime(["format": "MOVIE", "episodes": 1]), entry: try entry(0)).label, "Ready to watch")
    }
    func testUnrelatedLibraryEntryCannotSelectAnotherTitlesEpisode() throws {
        XCTAssertEqual(PlaybackEpisodeSelection.initial(anime: try anime(), entry: try entry(9, mediaID: 99), resumeEpisode: 3), 3)
        XCTAssertEqual(PlaybackEpisodeSelection.initial(anime: try anime(), entry: try entry(9, mediaID: 99), resumeEpisode: nil), 1)
    }
    func testFilteredScanReachesMatchesBeyondTheOldThreePageLimit() {
        let counts = [0, 0, 0, 0, 2]
        var scanned = 0, matches = 0
        while DiscoveryScanPolicy.shouldContinue(matches: matches, hasMore: true, pagesScanned: scanned) {
            matches += counts[scanned]; scanned += 1
        }
        XCTAssertEqual(scanned, 5); XCTAssertEqual(matches, 2)
        XCTAssertFalse(DiscoveryScanPolicy.shouldContinue(matches: 0, hasMore: true, pagesScanned: scanned), "An empty catalog must not cause an unlimited request loop")
    }
    func testFilteredScanFillsSparsePagesAndStopsWhenEnoughMatchesOrEndReached() {
        XCTAssertTrue(DiscoveryScanPolicy.shouldContinue(matches: 1, hasMore: true, pagesScanned: 1))
        XCTAssertFalse(DiscoveryScanPolicy.shouldContinue(matches: 12, hasMore: true, pagesScanned: 1))
        XCTAssertFalse(DiscoveryScanPolicy.shouldContinue(matches: 0, hasMore: false, pagesScanned: 1))
        XCTAssertTrue(DiscoveryScanPolicy.shouldContinue(matches: 12, hasMore: true, pagesScanned: 0, target: 24), "A manual continuation should find another batch")
    }
    func testPartialSearchNeverClaimsTheWholeCatalogHasNoMatches() {
        let partial = DiscoveryCoverage(loaded: true, loading: false, scanning: false, hasMore: true, requiresDubs: true, dubsLoaded: true, dubsUnavailable: false)
        XCTAssertEqual(partial, .partial); XCTAssertEqual(partial.emptyTitle, "No matches yet")
        XCTAssertTrue(partial.emptyMessage?.contains("More titles") == true)
        let complete = DiscoveryCoverage(loaded: true, loading: false, scanning: false, hasMore: false, requiresDubs: true, dubsLoaded: true, dubsUnavailable: false)
        XCTAssertEqual(complete, .complete); XCTAssertEqual(complete.emptyTitle, "No matching titles")
    }
    func testLoadingScanningAndDubOutagesNeverBecomeFalseEmptyResults() {
        let states: [DiscoveryCoverage] = [
            .init(loaded: false, loading: false, scanning: false, hasMore: false, requiresDubs: false, dubsLoaded: false, dubsUnavailable: false),
            .init(loaded: true, loading: true, scanning: false, hasMore: false, requiresDubs: false, dubsLoaded: true, dubsUnavailable: false),
            .init(loaded: true, loading: false, scanning: true, hasMore: true, requiresDubs: true, dubsLoaded: true, dubsUnavailable: false),
            .init(loaded: true, loading: false, scanning: false, hasMore: false, requiresDubs: true, dubsLoaded: false, dubsUnavailable: false),
            .init(loaded: true, loading: false, scanning: false, hasMore: false, requiresDubs: true, dubsLoaded: true, dubsUnavailable: true)
        ]
        XCTAssertEqual(states, [.loading, .loading, .searching, .checkingDubs, .unavailableDubs])
        XCTAssertTrue(states.allSatisfy { $0.emptyTitle == nil && $0.emptyMessage == nil })
    }
    private let redirect = URL(string: "animecompanion://oauth/anilist")!
    private func oauth(_ suffix: String) -> URL { URL(string: "animecompanion://oauth/anilist" + suffix)! }
    func testOAuthBindsTokensToTheActiveAttempt() throws {
        let token = try OAuthCallback.parse(oauth("#access_token=token&token_type=Bearer&state=current&expires_in=3600"), expectedRedirect: redirect, expectedState: "current", now: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(token.expiresAt, Date(timeIntervalSince1970: 4600))
        for suffix in ["#access_token=x&token_type=Bearer", "#access_token=x&token_type=Bearer&state=old", "?state=current#access_token=x&token_type=Bearer&state=current"] {
            XCTAssertThrowsError(try OAuthCallback.parse(oauth(suffix), expectedRedirect: redirect, expectedState: "current"))
        }
    }
    func testOAuthRejectsValuelessDuplicatesBadExpiryAndCredentialedRedirects() {
        for suffix in ["#access_token&access_token=x&token_type=Bearer", "#access_token=x&token_type=Bearer&expires_in=abc", "#access_token=x&token_type=Bearer&expires_in=nan", "#access_token=%20&token_type=Bearer"] {
            XCTAssertThrowsError(try OAuthCallback.parse(oauth(suffix), expectedRedirect: redirect))
        }
        XCTAssertThrowsError(try OAuthCallback.parse(URL(string: "animecompanion://user@oauth/anilist#access_token=x&token_type=Bearer")!, expectedRedirect: redirect))
    }
}
