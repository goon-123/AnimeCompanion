#if DEBUG
import Foundation
import AnimeCore

/// Offline screen fixtures. No account credentials, tracking mutations or
/// external provider data are used, and the entire transport is Release-excluded.
struct PhaseTwoPreviewTransport: HTTPTransport {
    static func media(_ id: Int) -> [String: Any] {
        var result: [String: Any] = ["id": id, "idMal": id, "title": ["english": id == 1 ? "Phase 2 tracked title" : "Phase 2 title \(id)"],
            "status": "FINISHED", "format": "TV", "episodes": id == 1 ? 26 : 12,
            "genres": ["Action", "Sci-Fi"], "averageScore": 84, "description": "Offline screen fixture synopsis.",
            "studios": ["nodes": [["id": 1, "name": "Fixture studio"]]]]
        if (990101...990105).contains(id) {
            result["status"] = "RELEASING"
            if id != 990105 {
                result["nextAiringEpisode"] = ["episode": id == 990104 ? 1 : 7,
                    "airingAt": Int(Date().addingTimeInterval(86_400).timeIntervalSince1970)]
            }
        }
        if id == 5 { result["format"] = "MOVIE"; result["episodes"] = 1 }
        if id == 990106 { result["status"] = "NOT_YET_RELEASED" }
        if ProcessInfo.processInfo.arguments.contains("--ui-catalog-loading-preview") {
            result["coverImage"] = ["extraLarge": "https://catalog-preview.invalid/poster/\(id).png", "color": "#243B59"]
            result["bannerImage"] = "https://catalog-preview.invalid/banner/\(id).png"
        }
        return result
    }
    static func library() throws -> [LibraryEntry] {
        let items = [(1, 8, "CURRENT"), (5, 1, "COMPLETED"), (990101, 4, "CURRENT"),
                     (990102, 6, "CURRENT"), (990104, 0, "CURRENT"), (990105, 2, "CURRENT"), (990106, 0, "PLANNING")]
        let records: [[String: Any]] = items.map { id, progress, status in
            ["id": id, "mediaId": id, "status": status, "progress": progress,
             "updatedAt": id == 1 ? 2_000 : 1_000, "media": media(id)]
        }
        return try JSONDecoder().decode([LibraryEntry].self, from: JSONSerialization.data(withJSONObject: records))
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let query = body?["query"] as? String ?? ""
        if query.contains("query Explore"), ProcessInfo.processInfo.arguments.contains("--ui-catalog-loading-preview") {
            try await Task.sleep(for: .seconds(5))
        }
        let variables = body?["variables"] as? [String: Any] ?? [:]
        let page = variables["page"] as? Int ?? 1
        let ids = variables["ids"] as? [Int] ?? Array(((page - 1) * 24 + 1)...(page * 24))
        let result: [String: Any] = ["media": ids.map(Self.media), "pageInfo": ["hasNextPage": page < 2]]
        let payload: [String: Any]
        if query.contains("query Details") {
            var details = Self.media(variables["id"] as? Int ?? 1)
            if ProcessInfo.processInfo.arguments.contains("--ui-catalog-loading-preview") {
                details["trailer"] = ["id": "owned-preview", "site": "youtube"]
                if details["id"] as? Int == 1 {
                    var related = Self.media(5); related["type"] = "ANIME"
                    details["relations"] = ["edges": [["relationType": "SEQUEL", "node": related]]]
                }
            }
            payload = ["Media": details]
        }
        else if query.contains("query Explore") { payload = ["seasonal": result, "trending": result, "upcoming": result] }
        else { payload = ["Page": result] }
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else { throw ServiceError.invalidResponse }
        return (try JSONSerialization.data(withJSONObject: ["data": payload]), response)
    }
}
#endif
