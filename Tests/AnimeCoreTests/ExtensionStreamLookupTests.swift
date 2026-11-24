import XCTest
@testable import AnimeCore

final class ExtensionStreamLookupTests: XCTestCase {
    private func anime(_ json: String = #"{"id":1,"title":{"english":"The Laid-Off Cheat-Granting Mage","romaji":"Tsuihou Sareta Cheat Fuyo Majutsushi"},"synonyms":["Cheat Mage"]}"#) throws -> Anime {
        try JSONDecoder().decode(Anime.self, from: Data(json.utf8))
    }
    private func media(_ title: String, url: String = "series", episodes: [ExtensionEpisode] = []) -> ExtensionMedia {
        .init(payload: .object(["title": .string(title), "url": .string(url), "episodes": .array(episodes.map(\.payload))]))
    }
    private func episode(_ number: ExtensionJSON, season: String = "", name: String = "Video", url: String = "opaque") -> ExtensionEpisode {
        .init(payload: .object(["episodeNumber": number, "name": .string(name), "url": .string(url), "sortMap": .object(["season": .string(season)])]))
    }
    func testAliasesNormalizePunctuationAndKeepSeasonNumbers() throws {
        let anime = try anime()
        XCTAssertNotNil(ExtensionStreamLookup.matchingMedia([media("The Laid Off Cheat Granting Mage")], anime: anime))
        XCTAssertNotNil(ExtensionStreamLookup.matchingMedia([media("Tsuihou Sareta Cheat Fuyo Majutsushi")], anime: anime))
        XCTAssertNil(ExtensionStreamLookup.matchingMedia([media("Cheat Mage Season 2")], anime: anime))
        XCTAssertNil(ExtensionStreamLookup.matchingMedia([media("Cheat Mage", url: "sub"), media("Cheat Mage", url: "dub")], anime: anime))
        XCTAssertNotNil(ExtensionStreamLookup.matchingMedia([media("Cheat Mage"), media("Cheat Mage")], anime: anime))
    }
    func testEpisodeUsesNumericPayloadAndNeverArrayPosition() {
        let values = [episode(.string("8")), episode(.number(7), url: "opaque-json-7"), episode(.string("6"))]
        XCTAssertEqual(ExtensionStreamLookup.matchingEpisode(values, number: 7)?.id, "opaque-json-7")
        XCTAssertNil(ExtensionStreamLookup.matchingEpisode(values, number: 2))
        XCTAssertNil(ExtensionStreamLookup.matchingEpisode([episode(.string("7.5"))], number: 7))
        XCTAssertNotNil(ExtensionStreamLookup.matchingEpisode([episode(.string(""), name: "Episode 7 — A new start")], number: 7))
        XCTAssertNil(ExtensionStreamLookup.matchingEpisode([episode(.string(""), name: "7 heroes in 2026")], number: 7))
    }
    func testAmbiguousSeasonsAndDuplicateEpisodeRequireManualChoice() {
        XCTAssertNil(ExtensionStreamLookup.matchingEpisode([episode(.string("7"), season: "1"), episode(.string("7"), season: "2")], number: 7))
        XCTAssertNil(ExtensionStreamLookup.matchingEpisode([episode(.string("7"), season: "1"), episode(.string("8"), season: "2")], number: 7))
        XCTAssertNil(ExtensionStreamLookup.matchingEpisode([episode(.string("7")), episode(.string("7"))], number: 7))
        XCTAssertNotNil(ExtensionStreamLookup.matchingEpisode([episode(.string(""))], number: 1, movie: true))
        XCTAssertNil(ExtensionStreamLookup.matchingEpisode([episode(.string(""))], number: 1))
    }
    func testVideoKeepsSubtitlesHeadersAndDoesNotInventEnglishAudio() throws {
        let video = try JSONDecoder().decode(ExtensionVideo.self, from: Data(#"{"url":"https://video.example/master.m3u8","quality":"1080p","headers":{"Referer":"https://source.example"},"subtitles":[{"file":"https://video.example/en.vtt","label":"English"}]}"#.utf8))
        let stream = try video.stream(sourceName: "Sora")
        XCTAssertEqual(stream.videoURL?.absoluteString, video.url)
        XCTAssertEqual(stream.subtitles?.first?.videoURL?.absoluteString, "https://video.example/en.vtt")
        XCTAssertEqual(video.headers?["Referer"], "https://source.example")
        XCTAssertFalse(StreamSourceMetadata(stream: stream).audio.english)
        XCTAssertTrue(video.canPlay)
    }
    func testResolutionTriesRomajiAndPassesOpaqueEpisodeUnchanged() async throws {
        let expected = episode(.string("7"), url: #"{"id":"opaque-7","token":"provider-data"}"#)
        let selected = media("Tsuihou Sareta Cheat Fuyo Majutsushi", episodes: [expected])
        let client = StubExtensionStreams(media: selected)
        let result = try await ExtensionStreamLookup.resolve(source: source(), anime: anime(), episode: 7, client: client)
        XCTAssertEqual(result.videos.count, 1)
        let queries = await client.queries
        XCTAssertEqual(queries.count, 2)
        let received = await client.received
        XCTAssertEqual(received, expected.payload)
    }
    func testWrongTitleDoesNotFetchVideos() async throws {
        let client = StubExtensionStreams(media: media("Another Anime"))
        let result = try await ExtensionStreamLookup.resolve(source: source(), anime: anime(), episode: 7, client: client)
        XCTAssertTrue(result.videos.isEmpty)
        XCTAssertNotNil(result.message)
        let received = await client.received
        XCTAssertNil(received)
    }
    func testCancellationNeverReturnsStaleVideos() async throws {
        let client = StubExtensionStreams(media: media("Cheat Mage", episodes: [episode(.string("7"))]), cancelAfterSearch: true)
        let task = Task { try await ExtensionStreamLookup.resolve(source: source(), anime: anime(), episode: 7, client: client) }
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected error") }
        let received = await client.received
        XCTAssertNil(received)
    }
    private func source() throws -> UnifiedExtensionSource {
        try JSONDecoder().decode(UnifiedExtensionSource.self, from: Data(#"{"id":"jorm","managerId":"sora","kind":"anime","name":"Jormungandr"}"#.utf8))
    }
}

private actor StubExtensionStreams: ExtensionStreamClient {
    let media: ExtensionMedia
    let cancelAfterSearch: Bool
    var queries: [String] = []
    var received: ExtensionJSON?
    init(media: ExtensionMedia, cancelAfterSearch: Bool = false) { self.media = media; self.cancelAfterSearch = cancelAfterSearch }
    func search(source: UnifiedExtensionSource, query: String) async throws -> ExtensionMediaPage {
        queries.append(query)
        if cancelAfterSearch { throw CancellationError() }
        let list = query == media.title ? [media] : []
        let data = try JSONEncoder().encode(list)
        return try JSONDecoder().decode(ExtensionMediaPage.self, from: Data("{\"hasNextPage\":false,\"list\":".utf8) + data + Data("}".utf8))
    }
    func detail(source: UnifiedExtensionSource, media: ExtensionMedia) async throws -> ExtensionMedia { self.media }
    func videos(source: UnifiedExtensionSource, episode: ExtensionEpisode) async throws -> [ExtensionVideo] {
        received = episode.payload
        return try JSONDecoder().decode([ExtensionVideo].self, from: Data(#"[{"url":"https://video.example/7.m3u8","quality":"1080p"}]"#.utf8))
    }
}
