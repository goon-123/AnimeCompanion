import XCTest
@testable import AnimeCore

final class StreamSourceMetadataTests: XCTestCase {
    private func source(_ description: String, title: String? = nil, name: String = "Provider", filename: String? = nil, playable: Bool = true) throws -> StremioStream {
        var fields: [String: Any] = ["description": description, "name": name]
        if let title { fields["title"] = title }
        if let filename { fields["behaviorHints"] = ["filename": filename] }
        if playable { fields["url"] = "https://video.example/9.mkv?token=a%2Bb" }
        else { fields["infoHash"] = "test" }
        return try JSONDecoder().decode(StremioStream.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func testEnglishCodesNamesFlagsAndAIOStreamsSmallCaps() {
        for value in ["en", "EN", "eng", "English", "Audio: en-US", "[EN_GB]", "🌎 🇺🇸", "🌐 🇬🇧", "🔊 ᴇɴ"] {
            XCTAssertTrue(StreamAudioInfo(texts: [value]).english, value)
        }
    }
    func testJapaneseCodesNamesFlagsAndSmallCaps() {
        for value in ["ja", "JA", "jpn", "Japanese", "Audio: ja-JP", "🌎 🇯🇵", "🔊 ᴊᴀ"] {
            let info = StreamAudioInfo(texts: [value])
            XCTAssertTrue(info.japanese, value); XCTAssertFalse(info.english, value)
        }
    }
    func testEnglishSubtitlesNeverBecomeEnglishAudio() {
        for value in ["Audio: ja · Subtitles: en", "Audio: ja Subtitles: en", "Languages: Japanese | Subtitles: English", "English subtitles / Japanese audio", "Audio: ja · English and Japanese subtitles", "Audio: ja · English / French subtitles", "Audio: ja · English (subtitles)", "ja\nSubs / en", "🌐 🇯🇵 📝 🇺🇸", "Show.Japanese.English.Subbed.mkv"] {
            let info = StreamAudioInfo(texts: [value])
            XCTAssertFalse(info.english, value); XCTAssertTrue(info.japanese, value)
        }
    }
    func testSeparateSubtitleObjectsNeverProveEnglishAudio() throws {
        let json = #"{"name":"Provider","description":"Audio: ja","url":"https://video.example/9","subtitles":[{"lang":"en","url":"https://video.example/sub.srt"}]}"#
        let stream = try JSONDecoder().decode(StremioStream.self, from: Data(json.utf8))
        XCTAssertFalse(StreamSourceMetadata(stream: stream).audio.english)
    }
    func testAudioListedAfterSubtitlesIsStillDetected() {
        let info = StreamAudioInfo(texts: ["Subtitles: en | Audio: ja, en"])
        XCTAssertTrue(info.english); XCTAssertTrue(info.japanese)
    }
    func testTemplateLiteralsDoNotFabricateEnglishAudio() {
        for value in ["invalid expression(stream.languages.includes('en'))", "${stream.audio.includes('en')}", "{{stream.languages.includes('en')}}", "TypeError: english audio lookup failed"] {
            XCTAssertFalse(StreamAudioInfo(texts: [value]).english, value)
        }
    }
    func testCleanupRetainsRealLanguagesBesideAnInvalidExpression() throws {
        let original = "1080p · invalid expression(stream.audio.join('en')) · Audio: en, ja · 2.4 GB"
        let stream = try source(original)
        XCTAssertFalse(stream.details.contains("invalid expression"))
        XCTAssertTrue(stream.details.contains("Audio: en, ja"))
        let info = StreamSourceMetadata(stream: stream)
        XCTAssertTrue(info.audio.english); XCTAssertTrue(info.audio.japanese)
        XCTAssertEqual(info.quality, "1080p"); XCTAssertEqual(info.size, "2.4 GB")
    }
    func testLanguageSurvivesDisplayTruncationAndLaterMetadataFields() throws {
        let description = (0..<45).map { "Release details \($0)" }.joined(separator: "\n") + "\nAudio: en / ja"
        let stream = try source(description)
        XCTAssertFalse(stream.details.contains("Audio:"))
        XCTAssertTrue(StreamSourceMetadata(stream: stream).audio.english)
        XCTAssertTrue(StreamSourceMetadata(stream: try source("Video release", title: "Audio: eng, jpn")).audio.english)
        XCTAssertTrue(StreamSourceMetadata(stream: try source("Video release", filename: "Show.S01E09.[ENG.JPN].mkv")).audio.english)
    }
    func testDualOrMultiAudioAloneDoesNotPromiseEnglish() {
        for value in ["Dual Audio", "MULTI-AUDIO", "Dual.Audio"] {
            let info = StreamAudioInfo(texts: [value])
            XCTAssertTrue(info.multiAudio); XCTAssertFalse(info.english)
            XCTAssertEqual(info.label, "Multi audio · English unconfirmed")
        }
    }
    func testLanguageTokenBoundariesAndExplicitNegativeReports() {
        for value in ["Provider engine · season eleven", "No English audio · Japanese", "Japanese without English", "English audio unavailable · ja"] {
            XCTAssertFalse(StreamAudioInfo(texts: [value]).english, value)
        }
    }
    func testQualityCodecAndSizeAreReadIndependentlyOfDescriptionChoice() throws {
        let info = StreamSourceMetadata(stream: try source("Audio: en", name: "Provider 4K", filename: "Show.HEVC.2.3GB.mkv"))
        XCTAssertEqual(info.quality, "4K"); XCTAssertEqual(info.codec, "HEVC"); XCTAssertEqual(info.size, "2.3GB")
        XCTAssertEqual(info.technicalSummary, "4K · HEVC · 2.3GB")
    }
    func testEnglishFirstOrderingPreservesSourceIdentityAndProviderOrder() throws {
        let streams = try [source("Audio: ja"), source("Audio: en"), source("Languages unlisted"), source("Audio: en, ja"), source("Audio: en", playable: false)]
        XCTAssertEqual(StreamSourceSelection.indices(in: streams), [1, 3, 0, 2])
        XCTAssertEqual(StreamSourceSelection.indices(in: streams, audio: .english), [1, 3])
        XCTAssertEqual(StreamSourceSelection.indices(in: streams, audio: .japanese), [3, 0])
        XCTAssertEqual(StreamSourceSelection.indices(in: streams, audio: .english, playableOnly: false), [1, 3, 4])
        XCTAssertTrue(StreamSourceSelection.indices(in: [try source("Audio: ja")], audio: .english).isEmpty)
        XCTAssertEqual(StreamSourceSelection.indices(in: streams, search: "English"), [1, 3])
        XCTAssertTrue(StreamSourceSelection.indices(in: [], audio: .english).isEmpty)
    }
    func testLanguageParsingNeverRewritesThePlaybackURL() throws {
        let stream = try source("invalid expression(stream.codec) · Audio: en, ja")
        _ = StreamSourceMetadata(stream: stream)
        XCTAssertEqual(stream.videoURL?.absoluteString, "https://video.example/9.mkv?token=a%2Bb")
    }
}
