#if DEBUG
import Foundation
import AnimeCore

/// Opt-in UI-test transport. Synthetic URLs are never requested or included in Release.
actor PlaybackPreviewTransport: HTTPTransport {
    private var streamRequests = 0
    static func addon() throws -> InstalledAddon {
        let json = #"{"id":"ui.preview","name":"UI preview","types":["series","movie"],"resources":["stream"],"idPrefixes":["anilist:"]}"#
        return InstalledAddon(endpoint: try AddonEndpoint("https://addon.example/preview"),
            manifest: try JSONDecoder().decode(AddonManifest.self, from: Data(json.utf8)))
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        streamRequests += 1
        if ProcessInfo.processInfo.arguments.contains("--ui-playback-refresh-failure"), streamRequests > 1 {
            throw PlaybackError.unavailable
        }
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            throw PlaybackError.unavailable
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-playback-languages") || ProcessInfo.processInfo.arguments.contains("--ui-playback-ja-only") {
            let sources: [[String: Any]] = [
                ["name": "Provider A · \(url.lastPathComponent)", "description": "1080p · 1.2 GB\nAudio: ja · Subtitles: en", "url": "https://video.example/ja.mkv",
                 "subtitles": [["id": "en", "lang": "English", "url": "https://video.example/en.srt"]]],
                ["name": "Provider B · \(url.lastPathComponent)",
                 "description": "1080p · HEVC · 2.4 GB\nRelease metadata\n" + String(repeating: "Release details ", count: 30) + "\nAdditional source information\ninvalid expression(stream.audio.unknown('fr')) · Audio: ᴇɴ / ᴊᴀ",
                 "url": "https://video.example/en.mkv"],
                ["name": "Unlisted provider", "description": "Multi audio · 720p · 900 MB", "url": "https://video.example/unknown.mkv"],
                ["name": "Torrent provider", "description": "Audio: en", "infoHash": "preview"]
            ]
            let selection = ProcessInfo.processInfo.arguments.contains("--ui-playback-ja-only") ? Array(sources.prefix(1)) : sources
            return (try JSONSerialization.data(withJSONObject: ["streams": selection]), response)
        }
        let malformed = ProcessInfo.processInfo.arguments.contains("--ui-playback-malformed-source")
        let payload: [String: Any] = ["streams": [["name": "Preview · \(url.lastPathComponent)",
            "description": malformed ? "1080p · English audio\ninvalid expression(stream.audio.join(','))\n2.4 GB" : "1080p · English audio · UI test source", "url": "https://video.example/episode.mkv",
            "subtitles": [["id": "en", "lang": "English", "url": "https://video.example/en.srt"]]]]]
        return (try JSONSerialization.data(withJSONObject: payload), response)
    }
}
#endif
