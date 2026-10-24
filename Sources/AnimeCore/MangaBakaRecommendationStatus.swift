import Foundation

/// The service's own readiness response, rather than an assumption based on an
/// empty list. Saved only with the encrypted account recommendation snapshot.
public struct MangaBakaRecommendationStatus: Codable, Sendable, Equatable {
    public let coldStart: Bool?
    public let profileStale: Bool?
    public let libraryCount: Int?

    private enum CodingKeys: String, CodingKey {
        case data, coldStart = "cold_start", profileStale = "profile_stale", libraryCount = "library_count"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.data) { self = try c.decode(Self.self, forKey: .data); return }
        coldStart = try c.decodeIfPresent(Bool.self, forKey: .coldStart)
        profileStale = try c.decodeIfPresent(Bool.self, forKey: .profileStale)
        libraryCount = try c.decodeIfPresent(Int.self, forKey: .libraryCount).flatMap { $0 >= 0 ? $0 : nil }
        guard coldStart != nil || profileStale != nil || libraryCount != nil else { throw MangaBakaError.invalidResponse }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(coldStart, forKey: .coldStart)
        try c.encodeIfPresent(profileStale, forKey: .profileStale)
        try c.encodeIfPresent(libraryCount, forKey: .libraryCount)
    }
}
