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
        let names = ["alpha": "Alpha sources", "beta": "Beta sources", "catalog": "Fixture catalog", "imdb": "IMDb sources", "configure-first": "Needs setup", "configured": "Configured sources", "subtitles": "Fixture subtitles"]
        let name = names[provider] ?? "UI preview"
        guard ["preview", "alpha", "beta", "unavailable", "catalog", "imdb", "configure-first", "configured", "subtitles"].contains(provider),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else { throw PlaybackError.invalidAddon }
        if url.lastPathComponent == "manifest.json" {
            var manifest: [String: Any] = ["id": "ui.multiple", "name": name, "types": ["series", "movie"], "resources": ["stream"], "idPrefixes": ["anilist:"]]
            if provider == "catalog" {
                manifest["resources"] = ["catalog", "meta"]; manifest["idPrefixes"] = ["tt"]
                manifest["catalogs"] = [["id": "fixture", "type": "movie", "name": "Fixture movies", "extra": [["name": "search"], ["name": "skip"]]]]
            }
            if ["imdb", "configured"].contains(provider) { manifest["idPrefixes"] = ["tt"] }
            if provider == "configured" { manifest["behaviorHints"] = ["configurable": true] }
            if provider == "subtitles" { manifest["resources"] = ["subtitles"]; manifest["idPrefixes"] = ["tt"] }
            if provider == "configure-first" { manifest["behaviorHints"] = ["configurable": true, "configurationRequired": true] }
            return (try JSONSerialization.data(withJSONObject: manifest), response)
        }
        if url.path.contains("/catalog/") {
            let metas: [[String: Any]] = url.path.contains("skip=2") ? [] : [["id": "tt100", "type": "movie", "name": "Catalog movie", "description": "An exact-ID catalog fixture."]]
            // Only one page is needed; skip=1 is the following empty page.
            return (try JSONSerialization.data(withJSONObject: ["metas": url.path.contains("skip=1") ? [] : metas]), response)
        }
        if url.path.contains("/meta/") {
            return (Data(#"{"meta":{"id":"tt100","type":"movie","name":"Catalog movie","description":"Uses the exact provider ID, not an AniList ID."}}"#.utf8), response)
        }
        if url.path.contains("/subtitles/") {
            return (Data(#"{"subtitles":[{"id":"fixture-en","lang":"en","url":"https://video.example/catalog/en.srt"}]}"#.utf8), response)
        }
        if provider == "unavailable" { throw PlaybackError.unavailable }
        let streams: [[String: Any]] = [["name": "\(name) · \(url.lastPathComponent)",
            "description": provider == "alpha" ? "1080p · Audio: ja · Subtitles: en" : "1080p · Audio: en / ja",
            "url": "https://video.example/\(provider)/episode.mkv"]]
        return (try JSONSerialization.data(withJSONObject: ["streams": streams]), response)
    }
}
#endif
