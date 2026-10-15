import Foundation

/// A watch-first projection, not a second progress database. AniList determines
/// the episode; only a local record for that exact episode can supply resume.
public struct ContinueWatchingItem: Identifiable, Sendable {
    public let entry: LibraryEntry
    public let episode: Int
    public let resume: PlaybackProgress?
    public var id: Int { entry.mediaId }

    public static func items(entries: [LibraryEntry], playback: [String: PlaybackProgress], now: Date = Date()) -> [Self] {
        entries.compactMap { entry -> Self? in
            guard entry.status == .watching || entry.status == .rewatching,
                  let anime = entry.media, anime.id == entry.mediaId,
                  let next = LibraryWatchProgress(anime: anime, entry: entry).nextEpisode else { return nil }
            // A future broadcast can prove the next unwatched episode is not out.
            if let airing = LibraryAiringProgress(anime: anime, watched: entry.progressValue, now: now),
               let released = airing.released, next > released { return nil }
            let saved = playback[PlaybackEpisode(animeID: anime.id, episode: next).key]
            let resume = saved.flatMap { !$0.finished && $0.position.isFinite && $0.position > 0
                && $0.position <= VidHubPlayback.maximumPosition ? $0 : nil }
            return Self(entry: entry, episode: next, resume: resume)
        }.sorted {
            let first = $0.resume?.updatedAt ?? Date(timeIntervalSince1970: Double($0.entry.updatedAt ?? 0))
            let second = $1.resume?.updatedAt ?? Date(timeIntervalSince1970: Double($1.entry.updatedAt ?? 0))
            if first != second { return first > second }
            return $0.id < $1.id
        }
    }
}

/// Only list episodes actually included in the metadata. Unknown totals are not
/// expanded into an invented season; the playback sheet still accepts a number.
public enum AnimeEpisodeCatalog {
    public static func episodes(anime: Anime, visibleLimit: Int) -> [Int] {
        let total = anime.format == "MOVIE" ? 1 : (anime.episodes ?? 0)
        guard total > 0, visibleLimit > 0 else { return [] }
        return Array(1...min(100_000, total, visibleLimit))
    }
}
