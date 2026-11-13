import XCTest
import AnimeCore
@testable import AnimeCompanion

final class ExternalPlayerStoreTests: XCTestCase {
    @MainActor func testPlayerPreferencePersistsAndReturnUsesLaunchedPlayerDespiteChangedSetting() throws {
        let suite = "com.animecompanion.player-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let initial = PlaybackStore(defaults: defaults)
        XCTAssertEqual(initial.player, .vidHub)
        initial.player = .outplayer
        XCTAssertEqual(PlaybackStore(defaults: defaults).player, .outplayer)

        let pending = PendingPlayback(episode: .init(animeID: 1, episode: 9), title: "Owned fixture", startPosition: 0, player: .outplayer)
        defaults.set(try JSONEncoder().encode(pending), forKey: "playback.pending")
        defaults.set(true, forKey: "playback.autoMarkEpisodes")
        let returning = PlaybackStore(defaults: defaults)
        returning.player = .infuse
        let callback = URL(string: "animecompanion://playback/success?request-id=\(pending.requestID.uuidString)")!
        XCTAssertEqual(returning.handle(callback), pending.episode)
        XCTAssertEqual(returning.saved(animeID: 1, episode: 9)?.finished, true)
        XCTAssertNil(defaults.data(forKey: "playback.pending"))
        XCTAssertNil(returning.handle(callback), "An already consumed callback cannot update progress again")
    }
    @MainActor func testInfuseReturnPersistsResumeWithoutMarkingWatched() throws {
        let suite = "com.animecompanion.player-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let pending = PendingPlayback(episode: .init(animeID: 1, episode: 9), title: "Owned fixture", startPosition: 0, player: .infuse)
        defaults.set(try JSONEncoder().encode(pending), forKey: "playback.pending")
        defaults.set(true, forKey: "playback.autoMarkEpisodes")
        let returning = PlaybackStore(defaults: defaults)
        let callback = URL(string: "animecompanion://playback/success?request-id=\(pending.requestID.uuidString)&position=125")!
        XCTAssertNil(returning.handle(callback))
        XCTAssertEqual(returning.saved(animeID: 1, episode: 9)?.position, 125)
        XCTAssertEqual(returning.saved(animeID: 1, episode: 9)?.finished, false)
        XCTAssertEqual(PlaybackStore(defaults: defaults).resumeEpisode(animeID: 1), 9)
    }
}
