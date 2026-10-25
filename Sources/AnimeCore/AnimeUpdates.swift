import Foundation

public enum AnimeUpdates {
    /// Current catalog artwork, not a claim about when a visual was announced.
    public static func visuals(in response: ExploreResponse?, includeAdult: Bool) -> [Anime] {
        guard let response else { return [] }
        var seen = Set<Int>()
        return ((response.seasonal.media ?? []) + (response.upcoming.media ?? [])).filter {
            (includeAdult || $0.isAdult != true) &&
            $0.coverURL.map { $0.scheme == "https" && $0.host != nil && $0.user == nil && $0.password == nil } == true &&
            seen.insert($0.id).inserted
        }
    }

    /// A conservative title match against publisher headlines; never infer an ID match.
    public static func headline(_ article: NewsArticle, matches anime: Anime) -> Bool {
        let headline = " " + NewsFeed.normalized(article.title) + " "
        return headlineAliases(for: anime).contains { headline.contains(" " + $0 + " ") }
    }

    /// Headlines describe a franchise in many ways: Season 3, 3rd Season, or no season at all.
    /// Only remove explicit terminal season/part/cour markers, never a title's bare number.
    public static func headlineAliases(for anime: Anime) -> [String] {
        var seen = Set<String>(), result: [String] = []
        for raw in [anime.title?.english, anime.title?.romaji, anime.title?.userPreferred].compactMap({ $0 }) {
            let title = NewsFeed.normalized(raw)
            for candidate in [title, baseHeadlineTitle(title)] where !candidate.isEmpty {
                if seen.insert(candidate).inserted { result.append(candidate) }
                if candidate.hasPrefix("the ") {
                    let short = String(candidate.dropFirst(4))
                    if short.split(separator: " ").count >= 2, seen.insert(short).inserted { result.append(short) }
                }
            }
        }
        return result
    }

    /// At most two distinct publisher searches, preferring English then romaji.
    public static func headlineSearchTerms(for anime: Anime) -> [String] {
        var seen = Set<String>()
        return Array([anime.title?.english, anime.title?.romaji, anime.title?.userPreferred].compactMap { raw -> String? in
            guard let raw else { return nil }
            var title = baseHeadlineTitle(NewsFeed.normalized(raw))
            if title.hasPrefix("the "), title.split(separator: " ").count >= 3 { title = String(title.dropFirst(4)) }
            guard !title.isEmpty, title.count <= 200, seen.insert(title).inserted else { return nil }
            return title
        }.prefix(2))
    }

    private static func baseHeadlineTitle(_ value: String) -> String {
        let suffix = #"\s+(?:the\s+)?(?:(?:season|part|cour)\s+(?:[0-9]+|[ivx]+)|(?:[0-9]+(?:st|nd|rd|th)?|first|second|third|fourth|fifth|final|last)\s+(?:season|part|cour))$"#
        var title = value
        while true {
            let shorter = title.replacingOccurrences(of: suffix, with: "", options: .regularExpression)
            // Keep ambiguous short names intact rather than widening them to common fragments.
            guard shorter != title, shorter.count >= 5 else { return title }
            title = shorter
        }
    }
}
