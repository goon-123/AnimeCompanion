import Foundation

/// MangaBaka's ratings are independent of AniList's single adult flag.
public struct MangaBakaContentFilter: Hashable, Sendable {
    public static let storageKey = "mangabaka.contentFilter.v1"
    public var ratings: Set<MangaBakaContentRating>
    public var includeUnrated: Bool

    public init(ratings: Set<MangaBakaContentRating> = [.safe, .suggestive], includeUnrated: Bool = false) {
        self.ratings = ratings; self.includeUnrated = includeUnrated
    }
    public static func legacy(includeAdult: Bool) -> Self {
        .init(ratings: Set(MangaBakaContentRating.allCases.filter { includeAdult || !$0.isMature }), includeUnrated: includeAdult)
    }
    private struct Saved: Codable { let ratings: [String]; let includeUnrated: Bool }
    public init(saved: String?, legacyIncludeAdult: Bool = false) {
        guard let saved else {
            self = .legacy(includeAdult: legacyIncludeAdult); return
        }
        guard let data = saved.data(using: .utf8), let value = try? JSONDecoder().decode(Saved.self, from: data) else {
            self.init(); return
        }
        self.init(ratings: Set(value.ratings.compactMap(MangaBakaContentRating.init(rawValue:))), includeUnrated: value.includeUnrated)
    }
    public var saved: String {
        let value = Saved(ratings: MangaBakaContentRating.allCases.filter(ratings.contains).map(\.rawValue), includeUnrated: includeUnrated)
        return String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
    }
    public var summary: String {
        let labels = MangaBakaContentRating.allCases.filter(ratings.contains).map(\.label) + (includeUnrated ? ["Unrated"] : [])
        return labels.isEmpty ? "No ratings enabled" : labels.joined(separator: " · ")
    }
    public func includes(_ rawRating: String?) -> Bool {
        guard let rating = rawRating?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let value = MangaBakaContentRating(rawValue: rating) else { return includeUnrated }
        return ratings.contains(value)
    }
}

extension MangaBakaSeries {
    public func isVisible(contentFilter: MangaBakaContentFilter) -> Bool { contentFilter.includes(contentRating) }
}
extension MangaBakaCoverImage {
    public func isVisible(contentFilter: MangaBakaContentFilter) -> Bool { contentFilter.includes(contentRating) }
}
extension MangaBakaQuery {
    public func allowedRatings(contentFilter: MangaBakaContentFilter) -> [MangaBakaContentRating] {
        MangaBakaContentRating.allCases.filter { contentFilter.ratings.contains($0) && (contentRatings.isEmpty || contentRatings.contains($0)) }
    }
    public func includes(_ series: MangaBakaSeries, contentFilter: MangaBakaContentFilter) -> Bool {
        series.isVisible(contentFilter: contentFilter) && (contentRatings.isEmpty || series.contentRating
            .flatMap(MangaBakaContentRating.init(rawValue:)).map(contentRatings.contains) == true)
    }
}
