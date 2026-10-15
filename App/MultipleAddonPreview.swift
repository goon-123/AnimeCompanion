#if DEBUG
import Foundation
import AnimeCore

/// Synthetic manifest installs and source responses; never accesses the network
/// or production Keychain. Both configurations deliberately share a manifest ID.
actor MultipleAddonPreviewTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        guard let url = request.url, url.host == "addon.example" else { throw PlaybackError.invalidAddon }
        let provider = url.pathComponents.dropFirst().first ?? "preview"
        let name = provider == "alpha" ? "Alpha sources" : provider == "beta" ? "Beta sources" : "UI preview"
        guard ["preview", "alpha", "beta", "unavailable"].contains(provider),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else { throw PlaybackError.invalidAddon }
        if url.lastPathComponent == "manifest.json" {
            let manifest: [String: Any] = ["id": "ui.multiple", "name": name, "types": ["series", "movie"], "resources": ["stream"], "idPrefixes": ["anilist:"]]
            return (try JSONSerialization.data(withJSONObject: manifest), response)
        }
        if provider == "unavailable" { throw PlaybackError.unavailable }
        let streams: [[String: Any]] = [["name": "\(name) · \(url.lastPathComponent)",
            "description": provider == "alpha" ? "1080p · Audio: ja · Subtitles: en" : "1080p · Audio: en / ja",
            "url": "https://video.example/\(provider)/episode.mkv"]]
        return (try JSONSerialization.data(withJSONObject: ["streams": streams]), response)
    }
}
#endif
