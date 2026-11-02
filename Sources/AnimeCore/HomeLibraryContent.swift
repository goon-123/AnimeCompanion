import Foundation

public struct HomeCatchUpItem: Identifiable, Sendable {
    public let entry: LibraryEntry
    public let anime: Anime
    public let remaining: Int
    public let aired: Int
    public var id: Int { anime.id }
}

/// Callers supply their content-filtered library. Never infer missing episodes
/// from a planned season total or English dub availability.
public enum HomeLibraryContent {
    public static func unique(_ entries: [LibraryEntry]) -> [LibraryEntry] {
        var seen = Set<Int>()
        return entries.sorted {
            if ($0.updatedAt ?? 0) != ($1.updatedAt ?? 0) { return ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
            return $0.id > $1.id
        }.filter { seen.insert($0.mediaId).inserted }
    }
    public static func catchUp(_ entries: [LibraryEntry], now: Date = Date()) -> [HomeCatchUpItem] {
        unique(entries).compactMap { entry -> HomeCatchUpItem? in
            guard entry.status == .watching || entry.status == .rewatching, let anime = entry.media else { return nil }
            let summary = LibraryBroadcastSummary(anime: anime, watched: entry.progressValue, now: now)
            guard summary.state == .behind, let aired = summary.aired else { return nil }
            return HomeCatchUpItem(entry: entry, anime: anime, remaining: max(0, aired - max(0, entry.progressValue)), aired: aired)
        }.sorted {
            if $0.remaining != $1.remaining { return $0.remaining > $1.remaining }
            return $0.anime.id < $1.anime.id
        }
    }
    public static func planned(_ entries: [LibraryEntry]) -> [LibraryEntry] {
        unique(entries).filter { $0.status == .planning && $0.media != nil }
    }
    public static func shuffleCandidates(_ entries: [LibraryEntry], now: Date = Date()) -> [Anime] {
        planned(entries).compactMap(\.media).filter { ($0.releasedEpisodeCount(at: now) ?? 0) > 0 }
    }
}
