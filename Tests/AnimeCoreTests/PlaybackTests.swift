import XCTest
@testable import AnimeCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class PlaybackTests: XCTestCase {
    private let manifest = #"{"id":"test.addon","name":"Test addon","types":["movie","series","anime"],"resources":[{"name":"stream","types":["movie","series","anime"],"idPrefixes":["anilist","mal:"]}]}"#
    private func anime(_ json: String = #"{"id":1,"idMal":2,"format":"TV","episodes":26}"#) throws -> Anime { try JSONDecoder().decode(Anime.self, from: Data(json.utf8)) }
    private func stream(_ json: String = #"{"name":"Source","url":"https://video.example/episode.mkv?token=a%2Bb&n=1#part","behaviorHints":{"filename":"Anime & Friends + 01.mkv"}}"#) throws -> StremioStream { try JSONDecoder().decode(StremioStream.self, from: Data(json.utf8)) }
    private func decodedManifest(_ json: String? = nil) throws -> AddonManifest { try JSONDecoder().decode(AddonManifest.self, from: Data((json ?? manifest).utf8)) }
    private func pending() -> PendingPlayback { PendingPlayback(episode: PlaybackEpisode(animeID: 1, episode: 9), title: "Example episode", createdAt: Date(timeIntervalSince1970: 1000)) }
    private func callback(_ path: String = "success", values: [URLQueryItem] = []) -> URL {
        var parts = URLComponents(string: "animecompanion://playback/\(path)")!; parts.queryItems = values; return parts.url!
    }
    private func success(_ request: PendingPlayback, position: String = "125", status: String = "stopped", extra: [URLQueryItem] = []) -> URL {
        callback(values: [URLQueryItem(name: "request-id", value: request.requestID.uuidString), URLQueryItem(name: "position", value: position), URLQueryItem(name: "status", value: status)] + extra)
    }
    func testNormalizesBaseManifestAndStremioInstallLinksWithoutChangingCredentials() throws {
        for input in ["https://addon.example/stremio/user/opaque%2Btoken", "https://addon.example/stremio/user/opaque%2Btoken/manifest.json", "stremio://addon.example/stremio/user/opaque%2Btoken/manifest.json/"] {
            let endpoint = try AddonEndpoint(input)
            XCTAssertEqual(endpoint.manifestURL.absoluteString, "https://addon.example/stremio/user/opaque%2Btoken/manifest.json")
            XCTAssertEqual(endpoint.displayHost, "addon.example")
            XCTAssertEqual(try endpoint.streamURL(type: "series", id: "anilist:1:9").absoluteString, "https://addon.example/stremio/user/opaque%2Btoken/stream/series/anilist:1:9.json")
        }
        let query = try AddonEndpoint(" https://addon.example/config/?key=a%2Bb%26c \n")
        XCTAssertEqual(try query.streamURL(type: "movie", id: "mal:2").query, "key=a%2Bb%26c")
    }
    func testRejectsNonNetworkAndInsecureAddonInputsAndPathInjection() throws {
        for url in ["file:///etc/passwd", "javascript:alert(1)", "http://addon.example/manifest.json", "https://u:p@addon.example/", "https://addon.example/#token", "https://addon.example/has space"] { XCTAssertThrowsError(try AddonEndpoint(url), url) }
        let endpoint = try AddonEndpoint("https://addon.example/config")
        XCTAssertThrowsError(try endpoint.streamURL(type: "../meta", id: "anilist:1"))
        XCTAssertThrowsError(try endpoint.streamURL(type: "series", id: "anilist:1/../../secret"))
    }
    func testUsesAnimeEntryEpisodeNumbersAndMovieIDsWithoutInventingTVSeasons() throws {
        let requests = AnimeStreamRequest.candidates(anime: try anime(), episode: 9, manifest: try decodedManifest())
        XCTAssertEqual(requests.map(\.id), ["anilist:1:9", "mal:2:9"])
        XCTAssertEqual(requests.map(\.type), ["series", "series"])
        let movie = try anime(#"{"id":5,"idMal":6,"format":"MOVIE","episodes":1}"#)
        XCTAssertEqual(AnimeStreamRequest.candidates(anime: movie, episode: 1, manifest: try decodedManifest()).map(\.id), ["anilist:5", "mal:6"])
        XCTAssertTrue(AnimeStreamRequest.candidates(anime: movie, episode: 2, manifest: try decodedManifest()).isEmpty)
    }
    func testHonorsManifestResourceScopesAndGlobalPrefixes() throws {
        let mal = try decodedManifest(#"{"id":"x","name":"x","types":["series"],"resources":["stream"],"idPrefixes":["mal:"]}"#)
        XCTAssertEqual(AnimeStreamRequest.candidates(anime: try anime(), episode: 1, manifest: mal).map(\.id), ["mal:2:1"])
        let scoped = try decodedManifest(#"{"id":"x","name":"x","types":["series","anime"],"resources":[{"name":"catalog","idPrefixes":["anilist"]},{"name":"stream","types":["anime"],"idPrefixes":["mal:"]}],"idPrefixes":["tt"]}"#)
        let request = AnimeStreamRequest.candidates(anime: try anime(), episode: 1, manifest: scoped)
        XCTAssertEqual(request.map(\.type), ["anime"]); XCTAssertEqual(request.map(\.id), ["mal:2:1"])
        XCTAssertFalse(scoped.supports(type: "series", id: "mal:2:1"))
    }
    func testInstallMakesManifestRequestAndRejectsCatalogOnlyAddons() async throws {
        let transport = PlaybackTransport(responses: [(200, manifest)])
        let addon = try await StremioClient(transport: transport).install("https://addon.example/private")
        XCTAssertEqual(addon.manifest.name, "Test addon")
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.url?.path, "/private/manifest.json")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Accept"), "application/json")
        let catalog = PlaybackTransport(responses: [(200, #"{"id":"x","name":"Catalog","types":["series"],"resources":["catalog"]}"#)])
        do { _ = try await StremioClient(transport: catalog).install("https://addon.example"); XCTFail("Expected invalid manifest") }
        catch { XCTAssertEqual(error as? PlaybackError, .invalidManifest) }
    }
    func testFallsBackToMALOnlyAfterEmptyResultAndPreservesServerSourceOrder() async throws {
        let transport = PlaybackTransport(responses: [(200, #"{"streams":[]}"#), (200, #"{"streams":[{"name":"Second lookup first result","url":"https://video.example/1"},{"name":"Second lookup second result","url":"https://video.example/2"}]}"#)])
        let addon = InstalledAddon(endpoint: try AddonEndpoint("https://addon.example/private"), manifest: try decodedManifest())
        let result = try await StremioClient(transport: transport).streams(addon: addon, anime: try anime(), episode: 9)
        XCTAssertEqual(result.streams.map(\.displayName), ["Second lookup first result", "Second lookup second result"])
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url!.lastPathComponent }, ["anilist:1:9.json", "mal:2:9.json"])
    }
    func testDoesNotRetryAuthorizationFailureAndNeverLeaksPrivateURL() async throws {
        let transport = PlaybackTransport(responses: [(403, "private diagnostic body")])
        let addon = InstalledAddon(endpoint: try AddonEndpoint("https://addon.example/private-token"), manifest: try decodedManifest())
        do { _ = try await StremioClient(transport: transport).streams(addon: addon, anime: try anime(), episode: 1); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? PlaybackError, .http(403)); XCTAssertFalse(error.localizedDescription.contains("private-token")) }
        let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
    }
    func testMalformedAndUnsupportedStreamsAreHandledIndependently() async throws {
        let response = #"{"streams":[{"url":"https://video.example/ok","description":"English + Japanese"},{"url":42},{"infoHash":"abc"},{"externalUrl":"https://website.example/watch"},{"url":"https://video.example/protected","behaviorHints":{"proxyHeaders":{"request":{"Referer":"https://origin.example"}}}}]}"#
        let client = StremioClient(transport: PlaybackTransport(responses: [(200, response)]))
        let addon = InstalledAddon(endpoint: try AddonEndpoint("https://addon.example"), manifest: try decodedManifest())
        let result = try await client.streams(addon: addon, anime: try anime(), episode: 1)
        XCTAssertEqual(result.streams.count, 4); XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.streams.filter { $0.unavailableReason == nil }.count, 1)
        XCTAssertEqual(result.streams[0].details, "English + Japanese")
        XCTAssertThrowsError(try VidHubPlayback.launchURL(stream: result.streams[3], pending: pending()))
    }
    func testMissingStreamsFieldIsNotMisreportedAsNoResults() async throws {
        let client = StremioClient(transport: PlaybackTransport(responses: [(200, #"{"error":"upstream failed"}"#)]))
        let addon = InstalledAddon(endpoint: try AddonEndpoint("https://addon.example"), manifest: try decodedManifest())
        do { _ = try await client.streams(addon: addon, anime: try anime(), episode: 1); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? PlaybackError, .invalidManifest) }
    }
    func testVidHubURLRoundTripsNestedURLsAndUsesNewPlayContract() throws {
        let request = pending(); let source = try stream()
        let sub = URL(string: "https://video.example/sub.srt?lang=en&key=abc%2Bdef")!
        let url = try VidHubPlayback.launchURL(stream: source, pending: request, position: 125, subtitle: sub)
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(parts.scheme, "open-vidhub"); XCTAssertEqual(parts.host, "x-callback-url"); XCTAssertEqual(parts.path, "/play")
        XCTAssertEqual(values["url"], source.videoURL?.absoluteString); XCTAssertEqual(values["sub"], sub.absoluteString)
        XCTAssertEqual(values["position"], "125"); XCTAssertEqual(values["filename"], "Anime & Friends + 01.mkv")
        XCTAssertEqual(values["request-id"], request.requestID.uuidString)
        XCTAssertEqual(values["x-success"], "animecompanion://playback/success")
        XCTAssertEqual(values["x-cancel"], "animecompanion://playback/cancel")
    }
    func testRejectsNonVideoSchemesAndClampsResumeBounds() throws {
        XCTAssertThrowsError(try VidHubPlayback.launchURL(stream: stream(#"{"url":"file:///private/data"}"#), pending: pending()))
        XCTAssertThrowsError(try VidHubPlayback.launchURL(stream: stream(#"{"url":"open-vidhub://loop"}"#), pending: pending()))
        for value in [Double.nan, Double.infinity, -5] {
            let url = try VidHubPlayback.launchURL(stream: stream(), pending: pending(), position: value)
            XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "position" })?.value, "0")
        }
    }
    func testStoppedIsNotFinishedAndCallbackDurationIsOptional() throws {
        let request = pending()
        XCTAssertEqual(try VidHubPlayback.outcome(url: success(request), pending: request, now: Date(timeIntervalSince1970: 2000)), .success(position: 125, duration: nil, finished: false))
        XCTAssertEqual(try VidHubPlayback.outcome(url: success(request, position: "1440", status: "finished", extra: [URLQueryItem(name: "duration", value: "1441")]), pending: request, now: Date(timeIntervalSince1970: 2000)), .success(position: 1440, duration: 1441, finished: true))
        XCTAssertEqual(PlaybackProgress(position: 1440, duration: 1441, finished: true).position, 0)
    }
    func testRejectsUnrelatedStaleOrUnmatchedCallbacks() throws {
        let request = pending(), now = Date(timeIntervalSince1970: 2000)
        XCTAssertNil(try VidHubPlayback.outcome(url: success(pending()), pending: request, now: now))
        XCTAssertNil(try VidHubPlayback.outcome(url: URL(string: "animecompanion://oauth/anilist?access_token=test")!, pending: request, now: now))
        XCTAssertNil(try VidHubPlayback.outcome(url: success(request), pending: request, now: Date(timeIntervalSince1970: 100_000)))
        XCTAssertNil(try VidHubPlayback.outcome(url: callback("not-success"), pending: request, now: now))
    }
    func testRejectsMalformedProgressAndDuplicateParameters() throws {
        let request = pending(), now = Date(timeIntervalSince1970: 2000)
        for value in ["nan", "inf", "-1", "31536001", "not-a-number"] { XCTAssertThrowsError(try VidHubPlayback.outcome(url: success(request, position: value), pending: request, now: now)) }
        XCTAssertThrowsError(try VidHubPlayback.outcome(url: success(request, status: "unknown"), pending: request, now: now))
        XCTAssertThrowsError(try VidHubPlayback.outcome(url: success(request, extra: [URLQueryItem(name: "position", value: "999")]), pending: request, now: now))
    }
    func testCancellationAndFailureDoNotFabricateProgress() throws {
        let request = pending(), now = Date(timeIntervalSince1970: 2000)
        let id = URLQueryItem(name: "request-id", value: request.requestID.uuidString)
        XCTAssertEqual(try VidHubPlayback.outcome(url: callback("cancel", values: [id]), pending: request, now: now), .cancelled)
        XCTAssertEqual(try VidHubPlayback.outcome(url: callback("error", values: [id, URLQueryItem(name: "errorCode", value: "201")]), pending: request, now: now), .failed(code: 201))
    }
}

private actor PlaybackTransport: HTTPTransport {
    var responses: [(Int, String)]
    private(set) var requests: [URLRequest] = []
    init(responses: [(Int, String)]) { self.responses = responses }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw ServiceError.invalidResponse }
        let (status, body) = responses.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
