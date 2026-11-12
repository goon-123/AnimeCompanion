import XCTest
@testable import AnimeCore

final class ExternalPlayerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2000)
    private func request(_ player: ExternalVideoPlayer) -> PendingPlayback {
        PendingPlayback(episode: .init(animeID: 1, episode: 9), title: "Anime & Friends", createdAt: Date(timeIntervalSince1970: 1000), startPosition: 45, player: player)
    }
    private func stream(_ url: String = "https://video.example/episode.mkv?token=abc+def%2Fghi&n=1#part", headers: Bool = false) throws -> StremioStream {
        var object: [String: Any] = ["url": url, "behaviorHints": ["filename": "Anime & Friends + 09.mkv"]]
        if headers { object["behaviorHints"] = ["proxyHeaders": ["request": ["Referer": "https://video.example"]]] }
        return try JSONDecoder().decode(StremioStream.self, from: JSONSerialization.data(withJSONObject: object))
    }
    private func values(_ url: URL) throws -> [String: String] {
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
    private func returned(_ pending: PendingPlayback, action: String = "success", report: [String: String]) throws -> URL {
        let launch = try ExternalPlayerPlayback.launchURL(stream: stream(), pending: pending)
        var callback = try XCTUnwrap(URLComponents(string: try XCTUnwrap(values(launch)["x-" + action])))
        callback.queryItems? += report.map { URLQueryItem(name: $0.key, value: $0.value) }
        return try XCTUnwrap(callback.url)
    }
    func testNewPlayerLaunchesPreserveSignedURLsSubtitlesAndOpaqueCallbacks() throws {
        let video = try stream()
        let subtitle = URL(string: "https://video.example/en.srt?key=a+b%2B&lang=en")!
        for player in [ExternalVideoPlayer.outplayer, .infuse] {
            let pending = request(player)
            let launch = try ExternalPlayerPlayback.launchURL(stream: video, pending: pending, position: 125.9, subtitle: subtitle)
            let query = try values(launch)
            XCTAssertEqual(launch.scheme, player.rawValue)
            XCTAssertEqual(launch.host, "x-callback-url"); XCTAssertEqual(launch.path, "/play")
            XCTAssertEqual(query["url"], video.videoURL?.absoluteString)
            XCTAssertEqual(query["position"], "125")
            XCTAssertEqual(query[player == .outplayer ? "subtitle" : "sub"], subtitle.absoluteString)
            XCTAssertTrue(launch.absoluteString.contains("abc%2Bdef%252Fghi%26n%3D1"), "A signed URL's literal plus must not become a space")
            XCTAssertEqual(query["filename"], player == .infuse ? "Anime & Friends + 09.mkv" : nil)
            for action in player == .outplayer ? ["success", "cancel", "error"] : ["success", "error"] {
                let callback = try XCTUnwrap(query["x-" + action].flatMap(URL.init(string:)))
                XCTAssertEqual(callback.path, "/" + action)
                XCTAssertEqual(try values(callback)["request-id"], pending.requestID.uuidString)
            }
            if player == .infuse { XCTAssertNil(query["x-cancel"]) }
        }
    }
    func testOutplayerCloseSavesPositionAndRuntimeWhileFinishIsExplicit() throws {
        let pending = request(.outplayer)
        let closed = try returned(pending, action: "cancel", report: ["url": "https://video.example/episode.mkv", "position": "325.5", "duration": "1440"])
        XCTAssertEqual(try ExternalPlayerPlayback.outcome(url: closed, pending: pending, now: now), .success(position: 325.5, duration: 1440, finished: false))
        let finished = try returned(pending, report: ["url": "https://video.example/episode.mkv"])
        XCTAssertEqual(try ExternalPlayerPlayback.outcome(url: finished, pending: pending, now: now), .success(position: 0, duration: nil, finished: true))
    }
    func testInfuseSuccessOnlySavesResumeEvenWithAnUnsupportedFinishedStatus() throws {
        let pending = request(.infuse)
        let closed = try returned(pending, report: ["lastPlayedUrl": "https://video.example/episode.mkv", "position": "125", "status": "finished", "duration": "1440"])
        XCTAssertEqual(try ExternalPlayerPlayback.outcome(url: closed, pending: pending, now: now), .success(position: 125, duration: nil, finished: false))
    }
    func testCallbacksKeepTheLaunchedPlayerAndRejectAnotherOrExpiredRequest() throws {
        for player in [ExternalVideoPlayer.outplayer, .infuse] {
            let pending = request(player)
            let callback = try returned(pending, report: ["position": "125"])
            XCTAssertNil(try ExternalPlayerPlayback.outcome(url: callback, pending: request(player), now: now))
            XCTAssertNil(try ExternalPlayerPlayback.outcome(url: callback, pending: pending, now: now.addingTimeInterval(86400)))
            XCTAssertNil(try ExternalPlayerPlayback.outcome(url: URL(string: "animecompanion://oauth/anilist")!, pending: pending, now: now))
            XCTAssertNil(try ExternalPlayerPlayback.outcome(url: URL(string: callback.absoluteString + "#unexpected")!, pending: pending, now: now))
        }
    }
    func testMalformedCallbacksCannotOverwriteProgress() throws {
        for player in [ExternalVideoPlayer.outplayer, .infuse] {
            let pending = request(player), action = player == .outplayer ? "cancel" : "success"
            for position in ["nan", "inf", "-1", "31536001", "text"] {
                let callback = try returned(pending, action: action, report: ["position": position, "duration": "1440"])
                XCTAssertThrowsError(try ExternalPlayerPlayback.outcome(url: callback, pending: pending, now: now))
            }
            let valid = try returned(pending, action: action, report: ["position": "125", "duration": "1440"])
            let duplicate = URL(string: valid.absoluteString + "&position=20")!
            XCTAssertThrowsError(try ExternalPlayerPlayback.outcome(url: duplicate, pending: pending, now: now))
        }
    }
    func testErrorsDoNotBecomeCompletions() throws {
        for player in [ExternalVideoPlayer.outplayer, .infuse] {
            let pending = request(player)
            let failed = try returned(pending, action: "error", report: ["errorCode": "100", "errorMessage": "Unsupported"])
            XCTAssertEqual(try ExternalPlayerPlayback.outcome(url: failed, pending: pending, now: now), .failed(code: 100))
        }
    }
    func testUntrackedLaunchesNeverCarryEpisodeCallbacks() throws {
        for player in ExternalVideoPlayer.allCases {
            let query = try values(ExternalPlayerPlayback.untrackedLaunchURL(player: player, stream: stream(), title: "Independent file"))
            XCTAssertNil(query["request-id"])
            for key in ["x-success", "x-cancel", "x-error"] { XCTAssertNil(query[key]) }
        }
    }
    func testAllPlayersRejectUnsupportedSourcesAndBoundResumePositions() throws {
        for player in ExternalVideoPlayer.allCases {
            let pending = request(player)
            for url in ["file:///private/data", "outplayer://loop", "javascript:alert(1)"] {
                XCTAssertThrowsError(try ExternalPlayerPlayback.launchURL(stream: stream(url), pending: pending))
            }
            XCTAssertThrowsError(try ExternalPlayerPlayback.launchURL(stream: stream(headers: true), pending: pending))
            for position in [Double.nan, Double.infinity, -10] {
                let query = try values(ExternalPlayerPlayback.launchURL(stream: stream(), pending: pending, position: position))
                XCTAssertEqual(query["position"], "0")
            }
        }
    }
    func testOlderSessionsAndUnknownSettingsKeepVidHubAndNewSessionsRememberTheirPlayer() throws {
        let legacy = PendingPlayback(episode: .init(animeID: 1, episode: 9), title: "Legacy")
        let decoded = try JSONDecoder().decode(PendingPlayback.self, from: JSONEncoder().encode(legacy))
        XCTAssertNil(decoded.player); XCTAssertEqual(decoded.destination, .vidHub)
        XCTAssertEqual(ExternalVideoPlayer(preference: nil), .vidHub)
        XCTAssertEqual(ExternalVideoPlayer(preference: "removed-player"), .vidHub)
        for player in ExternalVideoPlayer.allCases {
            let saved = try JSONDecoder().decode(PendingPlayback.self, from: JSONEncoder().encode(request(player)))
            XCTAssertEqual(saved.destination, player)
        }
    }
}
