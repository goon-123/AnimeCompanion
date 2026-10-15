#if DEBUG
import Foundation
import AnimeCore

/// Offline pagination fixture: the first dubbed match is beyond the old scan limit.
struct DiscoveryPreviewTransport: HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let variables = body?["variables"] as? [String: Any] ?? [:]
        let query = body?["query"] as? String ?? ""
        let page = variables["page"] as? Int ?? 1
        let search = (variables["search"] as? String ?? "").lowercased()
        let lastPage = search.contains("empty") ? 8 : 6
        let baseID = search.contains("empty") ? 990300 : 990200
        let record: [String: Any] = ["id": baseID + page, "idMal": baseID + page,
            "title": ["english": "Filtered preview page \(page)"], "episodes": 12,
            "genres": ["Action"], "format": "TV", "status": "FINISHED"]
        let result: [String: Any] = ["media": [record], "pageInfo": ["hasNextPage": page < lastPage]]
        let data: [String: Any]
        if query.contains("query Explore") { data = ["seasonal": result, "trending": result, "upcoming": result] }
        else { data = ["Page": result] }
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else { throw ServiceError.invalidResponse }
        return (try JSONSerialization.data(withJSONObject: ["data": data]), response)
    }
}
#endif
