#if DEBUG
import Foundation
import AnimeCore

enum SpotlightPolishPreview {
    static var active: Bool { ProcessInfo.processInfo.arguments.contains("--ui-spotlight-polish") }
}

/// Exercises the complete mapped metadata / textless parser / decode path with
/// owned artwork. It never contacts an external service or uses account data.
struct SpotlightPolishPreviewTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(for: .milliseconds(120))
        guard let url = request.url else { throw ServiceError.invalidResponse }
        let data: Data
        if url == SeriesArtworkClient.mappingURL {
            let rows: [[String: Any]] = (1...5).map { id in
                ["anilist_id": id, "mal_id": id, "type": id == 5 ? "MOVIE" : "TV",
                 "imdb_id": ["tt\(9000000 + id)"], "themoviedb_id": [(id == 5 ? "movie" : "tv"): 600000 + id]]
            }
            data = try JSONSerialization.data(withJSONObject: rows)
        } else if url.host == "v3-cinemeta.strem.io" {
            let imdb = url.deletingPathExtension().lastPathComponent
            let id = (Int(imdb.dropFirst(2)) ?? 9000001) - 9000000
            let meta: [String: Any] = ["id": imdb, "type": id == 5 ? "movie" : "series",
                "poster": "https://image.tmdb.org/t/p/original/owned-spotlight-branded-\(id).png",
                "logo": "https://image.tmdb.org/t/p/original/owned-spotlight-logo-\(id).png"]
            data = try JSONSerialization.data(withJSONObject: ["meta": meta])
        } else if url.host == "api.ani.zip" {
            let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value.flatMap(Int.init) ?? 1
            data = try JSONSerialization.data(withJSONObject: ["mappings": ["anilist_id": id, "mal_id": id, "type": id == 5 ? "MOVIE" : "TV"], "images": []] as [String: Any])
        } else if url.host == "www.themoviedb.org" {
            let parts = url.path.split(separator: "/")
            let id = (parts.count > 1 ? Int(parts[1]) : nil).map { $0 - 600000 } ?? 1
            let kind = parts.last == "posters" ? "poster" : "backdrop"
            let html = """
            <html><head><link rel="canonical" href="https://www.themoviedb.org\(url.path)"></head><body>
            <a id="image_language_xx" class="active">No Language</a><li data-image-id="owned-\(id)">
            <div class="image_content"><a title="View Original" href="https://image.tmdb.org/t/p/original/owned-spotlight-\(kind)-\(id).png">Image</a></div>
            <input data-language="xx" data-kind="\(kind)"></li></body></html>
            """
            data = Data(html.utf8)
        } else { throw ServiceError.invalidResponse }
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
#endif
