#if DEBUG
import Foundation
import AnimeCore

/// Neutral owned metadata for native layout/navigation regressions. Never reads
/// Keychain, calls account services or performs remote library mutations.
enum LibraryCustomizationPreview {
    static var active: Bool { ProcessInfo.processInfo.arguments.contains("--ui-customization-preview") }
    static func series(_ id: Int) -> [String: Any] {
        ["id": id, "title": id == 73
            ? "The Archivist Who Woke Up in Another World Finds a New Beginning With the Courageous Companions of the Glass Harbor"
            : id == 74 ? "A Lantern Across the Sea" : "Echoes of the Glass Harbor",
         "native_title": "Owned original-language title", "type": id == 74 ? "novel" : "manga",
         "status": "releasing", "content_rating": "safe", "rating": 82.5, "total_chapters": 40,
         "cover": ["x350": "https://catalog-preview.invalid/poster/\(id).png"],
         "description": "An independently written story fixture for layout tests.", "genres": [], "tags": [], "publishers": []]
    }
    static func library(state: String? = nil) throws -> [MangaBakaLibraryEntry] {
        let values: [[String: Any]] = [73, 74, 75].map { id in
            ["series_id": id, "series": series(id), "state": id == 75 ? "completed" : "reading", "progress_chapter": id == 75 ? 40 : 4.5]
        }
        return try JSONDecoder().decode([MangaBakaLibraryEntry].self, from: JSONSerialization.data(withJSONObject: values))
            .filter { state == nil || $0.state == state }
    }
}
struct LibraryCustomizationTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, url.host == "api.mangabaka.org", request.httpMethod == nil || request.httpMethod == "GET" else { throw ServiceError.invalidResponse }
        let payload: [String: Any]
        if url.path == "/v1/my/library" {
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value
            let entries = try LibraryCustomizationPreview.library(state: state)
            payload = ["data": entries.map { entry in ["series_id": entry.id, "series": LibraryCustomizationPreview.series(entry.id),
                "state": entry.state, "progress_chapter": entry.chapter ?? 0] },
                "pagination": ["page": 1, "count": entries.count, "next": NSNull()]]
        } else if url.path.hasPrefix("/v1/my/library/") { payload = ["data": NSNull()] }
        else if url.path.hasSuffix("/recommendations") { payload = ["results": []] }
        else if url.path.hasSuffix("/status") { payload = ["cold_start": true, "library_count": 3] }
        else if let id = Int(url.lastPathComponent), [73, 74, 75].contains(id) { payload = ["data": LibraryCustomizationPreview.series(id)] }
        else { payload = ["data": []] }
        return (try JSONSerialization.data(withJSONObject: payload), HTTPURLResponse(url: url, statusCode: url.path.hasPrefix("/v1/my/library/") ? 404 : 200, httpVersion: nil, headerFields: nil)!)
    }
}
#endif
