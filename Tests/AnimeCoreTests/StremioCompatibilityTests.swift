import XCTest
@testable import AnimeCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class StremioCompatibilityTests: XCTestCase {
    private let fullManifest = #"{"id":"standard","name":"Standard provider","types":["movie","series","tv","custom"],"resources":["catalog","meta","stream","subtitles"],"idPrefixes":["tt","kitsu:","custom:"],"catalogs":[{"type":"movie","id":"popular","name":"Popular","extra":[{"name":"search"},{"name":"skip"},{"name":"genre","isRequired":true,"options":["Action","Sci-Fi"]}]}]}"#
    private func addon(_ json: String? = nil, path: String = "private%2Bconfig/manifest.json?key=a%26b") throws -> InstalledAddon {
        InstalledAddon(endpoint: try AddonEndpoint("https://addon.example/\(path)"), manifest: try JSONDecoder().decode(AddonManifest.self, from: Data((json ?? fullManifest).utf8)))
    }
    private func stream(_ json: String = #"{"url":"https://video.example/file.mkv","behaviorHints":{"filename":"Anime & Friends + 01.mkv","videoHash":"abcdef1234567890","videoSize":1234567}}"#) throws -> StremioStream {
        try JSONDecoder().decode(StremioStream.self, from: Data(json.utf8))
    }
    func testResourceURLsSupportExactIMDbKitsuAndCustomIDs() throws {
        let endpoint = try addon().endpoint
        for id in ["tt1234567:2:3", "kitsu:42:7", "custom:channel-1"] {
            let url = try endpoint.streamURL(type: "series", id: id)
            XCTAssertEqual(url.lastPathComponent, id + ".json")
            XCTAssertEqual(url.query, "key=a%26b")
            XCTAssertTrue(url.absoluteString.contains("/private%2Bconfig/stream/series/"))
        }
        XCTAssertEqual(try endpoint.streamURL(type: "tv", id: "custom:live").path, "/private+config/stream/tv/custom:live.json")
    }
    func testResourceSegmentsCannotInjectRoutesOrQueryAndExtraValuesRoundTrip() throws {
        let endpoint = try addon().endpoint
        let url = try endpoint.resourceURL("catalog", type: "movie", id: "my/catalog?x=1#fragment", extra: ["search": "A & B / C + 日本語", "skip": "25"])
        XCTAssertTrue(url.absoluteString.contains("my%2Fcatalog%3Fx%3D1%23fragment"))
        XCTAssertTrue(url.absoluteString.contains("search=A%20%26%20B%20%2F%20C%20%2B%20"))
        XCTAssertEqual(url.query, "key=a%26b")
        for id in ["", "..", "a/../manifest", "a\nsecret"] { XCTAssertThrowsError(try endpoint.resourceURL("meta", type: "series", id: id)) }
        XCTAssertThrowsError(try endpoint.resourceURL("../manifest", type: "series", id: "tt1"))
        XCTAssertThrowsError(try endpoint.resourceURL("meta", type: "../movie", id: "tt1"))
    }
    func testConfigureURLPreservesOpaqueConfigurationAndQuery() throws {
        XCTAssertEqual(try addon().endpoint.configurationURL.absoluteString, "https://addon.example/private%2Bconfig/configure?key=a%26b")
        XCTAssertEqual(try AddonEndpoint("stremio://addon.example/manifest.json").configurationURL.absoluteString, "https://addon.example/configure")
    }
    func testObjectResourceWithoutPrefixesDoesNotInheritGlobalPrefixes() throws {
        let manifest = try addon(#"{"id":"x","name":"x","types":["movie"],"idPrefixes":["tt"],"resources":[{"name":"stream","types":["series"]},"meta"]}"#).manifest
        XCTAssertTrue(manifest.supports(type: "series", id: "kitsu:12:1"))
        XCTAssertFalse(manifest.supports(type: "movie", id: "tt12"))
        XCTAssertTrue(manifest.supports(resource: "meta", type: "movie", id: "tt12"))
        XCTAssertFalse(manifest.supports(resource: "meta", type: "movie", id: "kitsu:12"))
        let restored = try JSONDecoder().decode(AddonManifest.self, from: JSONEncoder().encode(manifest))
        XCTAssertTrue(restored.supports(type: "series", id: "custom:12"))
        XCTAssertFalse(restored.supports(resource: "meta", type: "movie", id: "custom:12"))
    }
    func testLegacySavedStringResourceObjectsKeepGlobalPrefixes() throws {
        let manifest = try addon(#"{"id":"x","name":"x","types":["series"],"idPrefixes":["mal:"],"resources":[{"name":"stream"}]}"#).manifest
        XCTAssertTrue(manifest.supports(type: "series", id: "mal:1:3"))
        XCTAssertFalse(manifest.supports(type: "series", id: "tt1:1:3"))
        let restored = try JSONDecoder().decode(AddonManifest.self, from: JSONEncoder().encode(manifest))
        XCTAssertFalse(restored.supports(type: "series", id: "anilist:1:3"))
    }
    func testCatalogScopesIgnoreMediaIDPrefixesAndExtraDefaultsAreOptional() throws {
        let manifest = try addon().manifest
        XCTAssertTrue(manifest.supports(resource: "catalog", type: "movie", id: "popular"))
        XCTAssertFalse(manifest.supports(resource: "catalog", type: "anime", id: "popular"))
        XCTAssertEqual(manifest.catalogs?.first?.extras.first { $0.isRequired == true }?.name, "genre")
        let legacy = try JSONDecoder().decode(AddonCatalog.self, from: Data(#"{"type":"movie","id":"legacy","extraSupported":["search"],"extraRequired":["search"]}"#.utf8))
        XCTAssertEqual(legacy.extras.first?.isRequired, true)
    }
    func testCatalogMetadataAndSubtitleOnlyManifestsInstallWithoutAnimeSupport() async throws {
        for resource in ["catalog", "meta", "subtitles", "stream", "addon_catalog", "custom_extension"] {
            let json = "{\"id\":\"x\",\"name\":\"Provider\",\"types\":[\"movie\"],\"idPrefixes\":[\"tt\"],\"resources\":[\"\(resource)\"]}"
            let transport = CompatibilityTransport([(200, json)])
            let installed = try await StremioClient(transport: transport).install("stremio://addon.example/manifest.json")
            XCTAssertTrue(installed.manifest.advertises(resource))
            XCTAssertFalse(installed.supportsAnime)
            XCTAssertFalse(installed.manifest.capabilitySummary.isEmpty)
        }
    }
    func testMalformedAndEmptyManifestsAreStillRejected() async throws {
        for json in [#"{"id":"x","name":"x","types":[],"resources":[]}"#, #"{"id":"","name":"x","types":[],"resources":["catalog"]}"#, #"{"id":"x","name":" ","types":[],"resources":["stream"]}"#, #"{"id":"x","name":"x","types":[],"resources":[{}]}"#, #"{"error":"bad"}"#] {
            do { _ = try await StremioClient(transport: CompatibilityTransport([(200, json)])).install("https://addon.example"); XCTFail("Expected invalid manifest") }
            catch { XCTAssertEqual(error as? PlaybackError, .invalidManifest) }
        }
    }
    func testConfigurationRequiredAndAdultHintsSurvivePersistence() async throws {
        let installed = try addon(#"{"id":"x","name":"Setup","types":["movie"],"resources":["stream"],"behaviorHints":{"configurable":true,"configurationRequired":true,"adult":true,"p2p":true}}"#)
        var collection = AddonCollection(); collection.install(installed)
        let restored = try JSONDecoder().decode(AddonCollection.self, from: JSONEncoder().encode(collection))
        XCTAssertEqual(restored.installations.first?.addon.manifest.behaviorHints?.adult, true)
        let transport = CompatibilityTransport([])
        do { _ = try await StremioClient(transport: transport).streams(addon: installed, request: .init(type: "movie", id: "tt1")); XCTFail("Expected setup required") }
        catch { XCTAssertEqual(error as? PlaybackError, .configurationRequired) }
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testCatalogRequiredFiltersAndOpaqueExtrasAreUsedExactly() async throws {
        let provider = try addon(), catalog = try XCTUnwrap(provider.manifest.catalogs?.first)
        let transport = CompatibilityTransport([(200, #"{"metas":[{"id":"tt123","type":"movie","name":"Example"}]}"#)])
        let client = StremioClient(transport: transport)
        do { _ = try await client.catalog(addon: provider, catalog: catalog); XCTFail("Expected missing required extra") }
        catch { XCTAssertEqual(error as? PlaybackError, .unsupportedResource) }
        let result = try await client.catalog(addon: provider, catalog: catalog, extra: ["genre": "Sci-Fi", "search": "A & B", "skip": "50"])
        XCTAssertEqual(result.metas.first?.id, "tt123")
        let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://addon.example/private%2Bconfig/catalog/movie/popular/genre=Sci-Fi&search=A%20%26%20B&skip=50.json?key=a%26b")
    }
    func testCatalogLossyEntriesKeepRawPaginationOffsetAndMissingEnvelopeIsAnError() async throws {
        let provider = try addon(), catalog = try XCTUnwrap(provider.manifest.catalogs?.first)
        let transport = CompatibilityTransport([(200, #"{"metas":[{"id":"tt1","type":"movie","name":"Good"},{"id":42},{"id":"tt2","type":"movie","name":"Other"}]}"#), (200, #"{"error":"bad"}"#)])
        let client = StremioClient(transport: transport)
        let result = try await client.catalog(addon: provider, catalog: catalog, extra: ["genre": "Action"])
        XCTAssertEqual(result.receivedCount, 3); XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.metas.map(\.id), ["tt1", "tt2"])
        do { _ = try await client.catalog(addon: provider, catalog: catalog, extra: ["genre": "Action"]); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? PlaybackError, .invalidManifest) }
    }
    func testMetaKeepsExactSeasonEpisodeAndEmbeddedStreamIDs() async throws {
        let json = #"{"meta":{"id":"tt123","type":"series","name":"Series","videos":[{"id":"tt123:2:7","title":"Episode seven","season":2,"episode":7,"streams":[{"name":"Direct EN","url":"https://video.example/7"}]}]}}"#
        let transport = CompatibilityTransport([(200, json)])
        let result = try await StremioClient(transport: transport).meta(addon: addon(), request: .init(type: "series", id: "tt123"))
        XCTAssertEqual(result?.videos?.first?.id, "tt123:2:7")
        XCTAssertEqual(result?.videos?.first?.season, 2)
        let owner = UUID()
        let snapshot = AddonStreamSnapshot.embedded(result?.videos?.first?.streams ?? [], addonID: owner, addonName: "Metadata provider")
        XCTAssertEqual(snapshot.sources.first?.stream.videoURL?.path, "/7"); XCTAssertEqual(snapshot.pendingCount, 0)
        XCTAssertEqual(snapshot.sources.first?.id.addonID, owner)
        XCTAssertEqual(snapshot.sources.first?.addonName, "Metadata provider")
        let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].url!.path.hasSuffix("/meta/series/tt123.json"))
    }
    func testMismatchedAndMalformedMetadataCannotSubstituteAnotherTitle() async throws {
        for json in [#"{"meta":{"id":"ttOther","type":"movie","name":"Wrong"}}"#, #"{"meta":{"id":"tt1","type":"series","name":"Wrong type"}}"#, #"{"error":"bad"}"#] {
            do { _ = try await StremioClient(transport: CompatibilityTransport([(200, json)])).meta(addon: addon(), request: .init(type: "movie", id: "tt1")); XCTFail("Expected invalid metadata") }
            catch { XCTAssertEqual(error as? PlaybackError, .invalidManifest) }
        }
        let empty = try await StremioClient(transport: CompatibilityTransport([(200, #"{"meta":null}"#)])).meta(addon: addon(), request: .init(type: "movie", id: "tt1"))
        XCTAssertNil(empty)
    }
    func testExactVideoLookupDoesNotGuessAniListOrChangeProviderID() async throws {
        let transport = CompatibilityTransport([(200, #"{"streams":[{"name":"EN","description":"Audio: en / ja","url":"https://video.example/7"}]}"#)])
        let result = try await StremioClient(transport: transport).streams(addon: addon(), request: .init(type: "series", id: "tt123:2:7"))
        XCTAssertEqual(result.streams.count, 1)
        XCTAssertTrue(StreamSourceMetadata(stream: result.streams[0]).audio.english)
        let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].url!.path.hasSuffix("/stream/series/tt123:2:7.json"))
    }
    func testExactVideoMultiLookupFiltersNonStreamsUnsupportedIDsAndDisabledProviders() async throws {
        let good = try addon(), subtitles = try addon(#"{"id":"sub","name":"Subtitles","types":["series"],"resources":["subtitles"]}"#, path: "sub")
        let unsupported = try addon(#"{"id":"ani","name":"AniList only","types":["series"],"resources":["stream"],"idPrefixes":["anilist:"]}"#, path: "ani")
        let transport = CompatibilityTransport([(200, #"{"streams":[{"url":"https://video.example/7"}]}"#)])
        let active = AddonInstallation(addon: good)
        let result = try await StremioClient(transport: transport).streams(installations: [active, AddonInstallation(addon: subtitles), AddonInstallation(addon: unsupported), AddonInstallation(addon: good, enabled: false)], request: .init(type: "series", id: "tt123:2:7"))
        XCTAssertEqual(result.sources.count, 1); XCTAssertEqual(result.sources.first?.id.addonID, active.id)
        XCTAssertTrue(result.issues.isEmpty)
        let requests = await transport.requests; XCTAssertEqual(requests.count, 1)
    }
    func testNativeAnimeStreamLookupSkipsCatalogAndSubtitleOnlyProviders() async throws {
        let catalog = try addon(#"{"id":"cat","name":"Catalog","types":["series"],"resources":["catalog","subtitles"]}"#)
        let transport = CompatibilityTransport([])
        let anime = try JSONDecoder().decode(Anime.self, from: Data(#"{"id":1,"episodes":12,"format":"TV"}"#.utf8))
        let result = try await StremioClient(transport: transport).streams(installations: [AddonInstallation(addon: catalog)], anime: anime, episode: 1)
        XCTAssertTrue(result.sources.isEmpty); XCTAssertTrue(result.issues.isEmpty)
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testSubtitleLookupPassesExactVideoAndOptionalFileHintsWithoutQueryInjection() async throws {
        let transport = CompatibilityTransport([(200, #"{"subtitles":[{"id":"en","lang":"eng","url":"https://video.example/sub.srt?key=a%2Bb"},{"url":"file:///private/sub.srt"},{"url":42}]}"#)])
        let tracks = try await StremioClient(transport: transport).subtitles(addon: addon(), request: .init(type: "series", id: "tt1:2:3"), stream: stream())
        XCTAssertEqual(tracks.count, 1); XCTAssertEqual(tracks[0].lang, "eng")
        let requests = await transport.requests
        XCTAssertTrue(requests[0].url!.absoluteString.contains("subtitles/series/tt1:2:3/filename=Anime%20%26%20Friends%20%2B%2001.mkv&videoHash=abcdef1234567890&videoSize=1234567.json"))
        XCTAssertEqual(requests[0].url?.query, "key=a%26b")
    }
    func testUntrackedPlayerLaunchHasNoTrackingCallbacksOrInventedAniListID() throws {
        let subtitle = URL(string: "https://video.example/sub.srt?lang=en&token=a%2Bb")!
        let launch = try VidHubPlayback.untrackedLaunchURL(stream: stream(), title: "Catalog title", subtitle: subtitle)
        let items = URLComponents(url: launch, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertFalse(items.contains { ["request-id", "x-success", "x-error", "x-cancel"].contains($0.name) })
        XCTAssertEqual(items.first { $0.name == "sub" }?.value, subtitle.absoluteString)
        XCTAssertEqual(items.first { $0.name == "position" }?.value, "0")
        XCTAssertThrowsError(try VidHubPlayback.untrackedLaunchURL(stream: stream(#"{"infoHash":"torrent"}"#), title: "Torrent"))
        XCTAssertThrowsError(try VidHubPlayback.untrackedLaunchURL(stream: stream(#"{"url":"https://video.example/7","behaviorHints":{"proxyHeaders":{"request":{"Referer":"https://origin.example"}}}}"#), title: "Headers"))
    }
    func testOptionalSubtitleFileHintsCannotDiscardAnOtherwisePlayableStream() throws {
        for raw in [#""123""#, "-1", #""unknown""#, "null", "{}"] {
            let source = try stream("{\"url\":\"https://video.example/7\",\"behaviorHints\":{\"videoHash\":42,\"videoSize\":\(raw)}}")
            XCTAssertNotNil(source.videoURL); XCTAssertNil(source.behaviorHints?.videoHash)
            XCTAssertEqual(source.behaviorHints?.videoSize, raw == #""123""# ? 123 : nil)
        }
    }
    func testExactLookupPreservesPartialEntriesAndDoesNotRetryPrivateAuthorizationErrors() async throws {
        let transport = CompatibilityTransport([(200, #"{"streams":[{"url":"https://video.example/7"},{"url":42},{"infoHash":"torrent"}]}"#), (403, "private diagnostic")])
        let client = StremioClient(transport: transport), provider = try addon()
        let result = try await client.streams(addon: provider, request: .init(type: "series", id: "tt1:2:3"))
        XCTAssertEqual(result.streams.count, 2); XCTAssertEqual(result.skippedCount, 1)
        XCTAssertNotNil(result.streams[1].unavailableReason)
        do { _ = try await client.streams(addon: provider, request: .init(type: "series", id: "tt1:2:3")); XCTFail("Expected authorization failure") }
        catch { XCTAssertEqual(error as? PlaybackError, .http(403)); XCTAssertFalse(error.localizedDescription.contains("private")) }
        let requests = await transport.requests; XCTAssertEqual(requests.count, 2)
    }
    func testBrowserInterceptsOnlyManifestLinksAndPreservesConfiguredTokens() throws {
        for value in ["stremio://addon.example/opaque%2Btoken/manifest.json?key=a%26b", "https://addon.example/opaque%2Btoken/manifest.json?key=a%26b"] {
            let endpoint = try XCTUnwrap(AddonBrowserLink.installEndpoint(URL(string: value)!))
            XCTAssertEqual(endpoint.manifestURL.absoluteString, "https://addon.example/opaque%2Btoken/manifest.json?key=a%26b")
        }
        for value in ["https://addon.example/configure", "https://addon.example/notmanifest.json", "http://addon.example/manifest.json", "javascript:alert(1)", "file:///manifest.json", "https://u:p@addon.example/manifest.json"] {
            XCTAssertNil(AddonBrowserLink.installEndpoint(URL(string: value)!))
        }
        XCTAssertNotNil(AddonBrowserLink.installEndpoint(URL(string: "stremio://addon.example/manifest.json/")!))
        XCTAssertEqual(AddonBrowserLink.directoryURL.host, "stremio-addons.net")
    }
    func testBrowserDoesNotAutomaticallyOpenOtherAppsOrLocalFiles() {
        for value in ["stremio://addon.example/manifest.json", "open-vidhub://play", "file:///private/a", "javascript:alert(1)", "http://insecure.example", "https://u:p@addon.example"] {
            XCTAssertFalse(AddonBrowserLink.permitsPage(URL(string: value)!))
        }
        XCTAssertTrue(AddonBrowserLink.permitsPage(URL(string: "https://provider.example/configure?token=a%2Bb")!))
    }
    func testDirectoryStremioWebInstallHandoffPreservesRawAndEncodedPrivateLinks() throws {
        let input = "https://addon.example/opaque%2Btoken/manifest.json?key=a%26b&mode=1"
        let encoded = try XCTUnwrap(input.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        for value in [input, encoded] {
            let link = URL(string: "https://web.stremio.com/#/addons?addon=\(value)")!
            XCTAssertEqual(AddonBrowserLink.installEndpoint(link)?.manifestURL.absoluteString, input)
        }
        XCTAssertNil(AddonBrowserLink.installEndpoint(URL(string: "https://unrelated.example/#/addons?addon=\(input)")!))
        XCTAssertNil(AddonBrowserLink.installEndpoint(URL(string: "https://web.stremio.com/#/addons?addon=file:///private/manifest.json")!))
    }
}

private actor CompatibilityTransport: HTTPTransport {
    private var responses: [(Int, String)]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [(Int, String)]) { self.responses = responses }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation(); requests.append(request)
        guard !responses.isEmpty else { throw PlaybackError.unavailable }
        let (status, body) = responses.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
