import Foundation

public enum AnimeSeriesContent {
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
