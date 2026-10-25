#if DEBUG
import Foundation
import AnimeCore

enum UnifiedExplorePreview {
    static var active: Bool { ProcessInfo.processInfo.arguments.contains("--ui-unified-preview") }
}

struct UnifiedReadingPreviewTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw ServiceError.invalidResponse }
        if url.path.contains("/series/search") || url.path.contains("/discover/") {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let text = query.first { $0.name == "q" }?.value
            let page = Int(query.first { $0.name == "page" }?.value ?? "1") ?? 1
            let format = query.first { $0.name == "type" }?.value
            let failed = ProcessInfo.processInfo.arguments.contains("--ui-unified-reading-failure")
            var records = (page == 1 ? [73, 74, 77] : [75, 76]).map { id -> [String: Any] in
                var value = LibraryCustomizationPreview.series(id)
                value["type"] = [74, 76].contains(id) ? "novel" : id == 75 ? "manhwa" : "manga"
                value["title"] = (text ?? "Glass Harbor") + " · " + (value["type"] as? String ?? "manga") + " \(id)"
                value["content_rating"] = id == 77 ? "pornographic" : "safe"
                return value
            }
            if let format { records = records.filter { $0["type"] as? String == format } }
            let payload: [String: Any] = ["data": records, "pagination": ["page": page, "count": 5,
                "next": page == 1 ? "https://api.mangabaka.org/v2/series/search?page=2" as Any : NSNull()]]
            return (try JSONSerialization.data(withJSONObject: failed ? [:] : payload),
                HTTPURLResponse(url: url, statusCode: failed ? 503 : 200, httpVersion: nil, headerFields: nil)!)
        }
        return try await LibraryCustomizationTransport().data(for: request)
    }
}

struct UnifiedAnimePreviewTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let query = body?["query"] as? String ?? ""
        let variables = body?["variables"] as? [String: Any] ?? [:]
        guard (query.contains("query Search") || query.contains("query Browse")), let text = variables["search"] as? String else {
            return try await PhaseTwoPreviewTransport().data(for: request)
        }
        if text == "slow" { try? await Task.sleep(for: .seconds(2)) }
        let page = variables["page"] as? Int ?? 1
        let records = (page == 1 ? [1, 2] : [3, 4]).map { id -> [String: Any] in
            var value = PhaseTwoPreviewTransport.media(id)
            value["title"] = ["english": text + " · anime \(id)"]
            return value
        }
        let payload: [String: Any] = ["data": ["Page": ["media": records, "pageInfo": ["hasNextPage": page == 1]]]]
        guard let url = request.url else { throw ServiceError.invalidResponse }
        return (try JSONSerialization.data(withJSONObject: payload), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
#endif
