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
        let headline = " " + normalized(article.title) + " "
        return [anime.title?.romaji, anime.title?.english, anime.title?.userPreferred].compactMap { $0 }.contains {
            let title = normalized($0)
            return !title.isEmpty && headline.contains(" " + title + " ")
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
