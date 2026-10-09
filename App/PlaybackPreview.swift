#if DEBUG
import Foundation
import AnimeCore

/// Opt-in UI-test transport. Synthetic URLs are never requested or included in Release.
struct PlaybackPreviewTransport: HTTPTransport {
    static func addon() throws -> InstalledAddon {
        let json = #"{"id":"ui.preview","name":"UI preview","types":["series","movie"],"resources":["stream"],"idPrefixes":["anilist:"]}"#
        return InstalledAddon(endpoint: try AddonEndpoint("https://addon.example/preview"),
            manifest: try JSONDecoder().decode(AddonManifest.self, from: Data(json.utf8)))
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            throw PlaybackError.unavailable
        }
        let payload: [String: Any] = ["streams": [["name": "Preview · \(url.lastPathComponent)",
            "description": "1080p · English audio · UI test source", "url": "https://video.example/episode.mkv",
            "subtitles": [["id": "en", "lang": "English", "url": "https://video.example/en.srt"]]]]]
        return (try JSONSerialization.data(withJSONObject: payload), response)
    }
}
#endif
