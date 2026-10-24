import Foundation

/// The response and its optional content-rating lookup travel together. Neither
/// belongs in the public catalog cache; the app encrypts this account cache.
public struct MangaBakaRecommendationPayload: Codable, Sendable {
    public let response: Data
    public let details: Data?

    public init(response: Data, details: Data? = nil) {
        self.response = response; self.details = details
    }

    public func records() throws -> [MangaBakaSeries] {
        guard response.count <= 6_000_000, (details?.count ?? 0) <= 6_000_000 else { throw MangaBakaError.invalidResponse }
        let records = try JSONDecoder().decode(MBRecommendationResponse.self, from: response).items
        var seen = Set<Int>()
        let unique = Array(records.filter { seen.insert($0.id).inserted }.prefix(24))
        guard let details else { return unique }
        let resolved = try JSONDecoder().decode(MBRecommendationDetails.self, from: details).data
        let wanted = Set(unique.map(\.id))
        guard resolved.allSatisfy({ wanted.contains($0.id) }) else { throw MangaBakaError.invalidResponse }
        let byID = Dictionary(resolved.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return unique.map { item in
            MangaBakaContentRating(rawValue: item.contentRating ?? "") == nil ? byID[item.id] ?? item : item
        }
    }
}

private struct MBRecommendationDetails: Decodable { let data: [MangaBakaSeries] }

public struct MangaBakaRecommendationSnapshot: Codable, Sendable {
    public static let lifetime: TimeInterval = 7 * 24 * 60 * 60
    public let payload: MangaBakaRecommendationPayload
    public let fetchedAt: Date
    public let status: MangaBakaRecommendationStatus?
    public var refreshAt: Date { fetchedAt.addingTimeInterval(Self.lifetime) }

    public init(payload: MangaBakaRecommendationPayload, fetchedAt: Date = Date(), status: MangaBakaRecommendationStatus? = nil) {
        self.payload = payload; self.fetchedAt = fetchedAt; self.status = status
    }
}
