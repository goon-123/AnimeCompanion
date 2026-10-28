#if DEBUG
import Foundation
import AnimeCore

/// Neutral owned metadata for native layout/navigation regressions. Never reads
/// Keychain, calls account services or performs remote library mutations.
enum LibraryCustomizationPreview {
    static var active: Bool { ProcessInfo.processInfo.arguments.contains("--ui-customization-preview") }
    static var controlsActive: Bool { ProcessInfo.processInfo.arguments.contains("--ui-library-controls-preview") }
    static func series(_ id: Int) -> [String: Any] {
        if controlsActive, (801...807).contains(id) {
            let titles = ["Alpine Letters", "Beacon Letters", "Cedar Letters", "Dawn Letters", "Evergreen Letters", "Finished Letters", "Zinnia Letters"]
            let ratings = ["safe", "suggestive", "erotica", "pornographic", "unknown", "safe", "safe"]
            // Only neutral owned text/artwork; ratings exercise metadata filters.
            return ["id": id, "title": titles[id - 801], "type": id == 802 ? "novel" : "manga", "status": "releasing",
                "content_rating": ratings[id - 801], "rating": id == 807 ? 99 : 80, "total_chapters": 100,
                "description": "An independently written letter exchange fixture.", "genres": [], "tags": [], "publishers": []]
        }
        return ["id": id, "title": id == 73
            ? "The Archivist Who Woke Up in Another World Finds a New Beginning With the Courageous Companions of the Glass Harbor"
            : id == 74 ? "A Lantern Across the Sea" : "Echoes of the Glass Harbor",
         "native_title": "Owned original-language title", "type": id == 74 ? "novel" : "manga",
         "status": "releasing", "content_rating": "safe", "rating": 82.5, "total_chapters": 40,
         "cover": ["x350": "https://cdn.mangabaka.dev/owned-preview/poster/\(id).png"],
         "description": "An independently written story fixture for layout tests.", "genres": [], "tags": [], "publishers": []]
    }
    static func library(state: String? = nil) throws -> [MangaBakaLibraryEntry] {
        if controlsActive {
            let values: [[String: Any]] = (801...807).map { id in
                ["series_id": id, "series": series(id), "state": id == 806 ? "completed" : "reading",
                 "progress_chapter": id == 807 ? 99 : id - 800, "rating": id == 807 ? 95 : 50,
                 "updated_at": id == 807 ? "2026-10-26T12:00:00Z" : "2026-10-20T12:00:00Z"]
            }
            return try JSONDecoder().decode([MangaBakaLibraryEntry].self, from: JSONSerialization.data(withJSONObject: values))
                .filter { state == nil || $0.state == state }
        }
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
        if MangaBakaAccountsPreview.active && url.path == "/v1/my/profile" {
            let second = request.value(forHTTPHeaderField: "X-API-Key") == "owned-preview-second-account"
            payload = ["data": ["id": second ? "owned-reader-two" : "owned-reader", "nickname": second ? "HarborReader" : "LanternReader", "rating_steps": 1]]
        } else if url.path == "/v1/my/library" {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            let state = query?.first { $0.name == "state" }?.value
            let page = Int(query?.first { $0.name == "page" }?.value ?? "1") ?? 1
            if page == 1, ProcessInfo.processInfo.arguments.contains("--ui-home-library-delay") { try await Task.sleep(for: .seconds(5)) }
            let all = try LibraryCustomizationPreview.library(state: state).filter {
                !MangaBakaAccountsPreview.active || $0.id == (request.value(forHTTPHeaderField: "X-API-Key") == "owned-preview-second-account" ? 74 : 73)
            }
            let paginated = LibraryCustomizationPreview.controlsActive && all.contains { $0.id == 807 }
            let entries = paginated ? all.filter { page == 1 ? $0.id != 807 : $0.id == 807 } : all
            payload = ["data": entries.map { entry -> [String: Any] in ["series_id": entry.id, "series": LibraryCustomizationPreview.series(entry.id),
                "state": entry.state, "progress_chapter": entry.chapter ?? 0, "rating": entry.rating.map { $0 as Any } ?? NSNull(), "updated_at": entry.updatedAt.map { $0 as Any } ?? NSNull()] },
                "pagination": ["page": page, "count": all.count, "next": paginated && page == 1 ? "/owned-page-2" as Any : NSNull()]]
        } else if url.path.hasPrefix("/v1/my/library/") { payload = ["data": NSNull()] }
        else if url.path.hasSuffix("/recommendations") { payload = ["results": []] }
        else if url.path.hasSuffix("/status") { payload = ["cold_start": true, "library_count": 3] }
        else if let id = Int(url.lastPathComponent), [73, 74, 75].contains(id) { payload = ["data": LibraryCustomizationPreview.series(id)] }
        else { payload = ["data": []] }
        return (try JSONSerialization.data(withJSONObject: payload), HTTPURLResponse(url: url, statusCode: url.path.hasPrefix("/v1/my/library/") ? 404 : 200, httpVersion: nil, headerFields: nil)!)
    }
}
#endif
