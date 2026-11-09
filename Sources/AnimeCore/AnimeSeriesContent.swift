import Foundation

public enum AnimeSeriesContent {
    public static func showsOriginalBroadcast(for anime: Anime) -> Bool { anime.status == "RELEASING" }
    public static func nextBroadcast(for anime: Anime, now: Date = Date()) -> AiringEpisode? {
        guard anime.status == "RELEASING" || anime.status == "NOT_YET_RELEASED",
              let next = anime.nextAiringEpisode, next.episode > 0, next.date > now else { return nil }
        if let total = anime.episodes, total > 0, next.episode > total { return nil }
        return next
    }
    /// Written media have their own AniList IDs. Source works come first; keep
    /// alternate adaptations available without guessing equivalence by title.
    public static func writtenMedia(for anime: Anime, includeAdult: Bool) -> [RelatedAnime] {
        var seen = Set<Int>()
        let edges = anime.relations?.edges ?? []
        let ordered = edges.filter { $0.relationType == "SOURCE" } + edges.filter { $0.relationType != "SOURCE" }
        return ordered.compactMap(\.node).filter {
            $0.type == "MANGA" && (includeAdult || $0.isAdult != true) && seen.insert($0.id).inserted
        }
    }
}
