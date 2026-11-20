import XCTest
@testable import AnimeCore

final class UnifiedExtensionTests: XCTestCase {
    func testMangaExtensionVisibilityDoesNotNeedTheAnimeAdultSwitch() throws {
        func source(_ kind: String) throws -> UnifiedExtensionSource {
            try JSONDecoder().decode(UnifiedExtensionSource.self, from: Data("{\"id\":\"1\",\"managerId\":\"example\",\"kind\":\"\(kind)\",\"isNsfw\":true}".utf8))
        }
        let manga = try source("manga"), novel = try source("novel"), anime = try source("anime")
        let reading = MangaBakaContentFilter(ratings: [.erotica])
        XCTAssertTrue(manga.isVisible(includeAdultAnime: false, readingContent: reading))
        XCTAssertTrue(novel.isVisible(includeAdultAnime: false, readingContent: reading))
        XCTAssertFalse(anime.isVisible(includeAdultAnime: false, readingContent: reading))
        XCTAssertFalse(manga.isVisible(includeAdultAnime: true, readingContent: .init()))
    }
    func testOpaqueProviderEpisodeSurvivesNativeRoundTrip() throws {
        let data = Data(#"{"url":"{\"provider\":\"archive\",\"episode\":12}","name":"Episode 12","episodeNumber":"12","memo":"opaque data + / %","sortMap":{"season":"2","type":"dub"}}"#.utf8)
        let episode = try JSONDecoder().decode(ExtensionEpisode.self, from: data)
        let encoded = try JSONEncoder().encode(episode)
        XCTAssertEqual(try JSONDecoder().decode(ExtensionJSON.self, from: encoded), try JSONDecoder().decode(ExtensionJSON.self, from: data))
        XCTAssertEqual(episode.payload["sortMap"]["season"].string, "2")
    }
    func testSameProviderIDInDifferentSystemsAndKindsDoesNotCollide() throws {
        func source(_ manager: String, _ kind: String) throws -> UnifiedExtensionSource {
            try JSONDecoder().decode(UnifiedExtensionSource.self,
                from: Data("{\"id\":\"1234\",\"managerId\":\"\(manager)\",\"kind\":\"\(kind)\",\"name\":\"Internet Archive\"}".utf8))
        }
        let sources = try [source("aniyomi-desktop", "anime"), source("aniyomi-desktop", "manga"), source("cloudstream-desktop", "anime")]
        XCTAssertEqual(Set(sources.map(\.id)).count, 3)
        XCTAssertEqual(sources[0].arguments["source"] as? String, "1234")
    }
    func testVideoHeadersAndSubtitlesArePreserved() throws {
        let bytes = Data(#"{"title":"1080p","url":"https://media.example/video.m3u8","quality":"1080p","headers":{"Referer":"https://source.example/","User-Agent":"Source player"},"subtitles":[{"file":"https://media.example/en.vtt","label":"English"}]}"#.utf8)
        let video = try JSONDecoder().decode(ExtensionVideo.self, from: bytes)
        XCTAssertEqual(video.arguments["headers"] as? [String: String], ["Referer": "https://source.example/", "User-Agent": "Source player"])
        XCTAssertEqual(video.subtitles?.first?.label, "English")
    }
}
