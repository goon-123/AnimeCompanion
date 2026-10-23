#if DEBUG
import Foundation
import AnimeCore

/// Owned HTML/JSON responses exercise the production gallery client and parser.
/// These drawings are test fixtures, not LiveChart artwork or live-service evidence.
struct VisualGalleryPreviewTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw AnimeVisualsError.invalidResponse }
        try await Task.sleep(for: .milliseconds(250))
        let data: Data
        var status = 200
        if url.host == "raw.githubusercontent.com" {
            data = Data("anilist\tlivechart\tmyanimelist\n1\t10001\t1\n5\t10005\t5\n".utf8)
        } else if url.host == "www.livechart.me" {
            if ProcessInfo.processInfo.arguments.contains("--ui-visuals-denied") {
                status = 403; data = Data("Access denied".utf8)
            } else {
                let next = url.query == nil ? "<a rel='next' href='?page=2'>Next</a>" : ""
                let names = url.query == nil ? ["Roxy", "Sylphiette", "Rudeus", "Eris"] : ["Key visual", "Teaser visual"]
                let cards = names.map { name in
                    let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
                    return """
                    <article data-anime-visual-url-value="https://u.livechart.me/owned-visuals/\(slug)-large.png">
                    <img src="https://u.livechart.me/owned-visuals/\(slug).png" alt="\(name)">
                    <div>\(name)</div><div>© Owned gallery fixture</div></article>
                    """
                }.joined()
                data = Data("<html><body>\(cards)\(next)</body></html>".utf8)
            }
        } else if url.host == "api.jikan.moe" {
            data = Data(#"{"data":[{"jpg":{"image_url":"https://cdn.myanimelist.net/owned-visuals/key-visual.png"}},{"jpg":{"image_url":"https://cdn.myanimelist.net/owned-visuals/teaser-visual.png"}}]}"#.utf8)
        } else { throw AnimeVisualsError.invalidResponse }
        return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
#endif
