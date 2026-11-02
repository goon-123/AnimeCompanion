import Foundation

/// Original broadcast evidence takes precedence over planned totals and dub
/// dates. Unknown, undated episodes are not silently assumed to be unaired.
public struct AnimeEpisodeReleaseGroups: Sendable {
    public let aired: [AnimeEpisodeMetadata]
    public let upcoming: [AnimeEpisodeMetadata]
    public let next: AiringEpisode?
    public let unairedCount: Int?
    public var hasUpcoming: Bool { !upcoming.isEmpty || next != nil || (unairedCount ?? 0) > 0 }
    public init(anime: Anime, episodes: [AnimeEpisodeMetadata], now: Date = Date()) {
        aired = episodes.filter { Self.isReleased($0, anime: anime, now: now) }
        upcoming = episodes.filter { !Self.isReleased($0, anime: anime, now: now) }.sorted { $0.number < $1.number }
        if anime.status != "FINISHED", let value = anime.nextAiringEpisode, value.episode > 0, value.date > now {
            next = value
        } else { next = nil }
        if let total = anime.episodes, total > 0, let released = anime.releasedEpisodeCount(at: now) {
            unairedCount = max(0, total - released)
        } else { unairedCount = nil }
    }
    public static func isReleased(_ episode: AnimeEpisodeMetadata, anime: Anime, now: Date = Date()) -> Bool {
        guard anime.status != "NOT_YET_RELEASED" else { return false }
        if let released = anime.releasedEpisodeCount(at: now) { return episode.number <= released }
        return !episode.isFuture(at: now)
    }
    /// Paginated metadata must not make the next unwatched episode disappear.
    /// Fill number-only rows where the original broadcast confirms release,
    /// while keeping real metadata and never inventing titles, dates or stills.
    public static func listedEpisodes(anime: Anime, metadata: [AnimeEpisodeMetadata], watched: Int, now: Date = Date()) -> [AnimeEpisodeMetadata] {
        var values = metadata.reduce(into: [Int: AnimeEpisodeMetadata]()) { result, episode in
            if (1...10_000).contains(episode.number) { result[episode.number] = episode }
        }
        let released = anime.releasedEpisodeCount(at: now)
        let count: Int
        if metadata.isEmpty {
            count = min(10_000, max(max(anime.episodes ?? 0, released ?? 0), max(watched, anime.nextAiringEpisode?.episode ?? 0)))
        } else { count = min(10_000, max(0, released ?? 0)) }
        if count > 0 {
            for number in 1...count where values[number] == nil { values[number] = AnimeEpisodeMetadata(number: number) }
        }
        if let next = anime.nextAiringEpisode, (1...10_000).contains(next.episode), next.date > now, values[next.episode] == nil {
            values[next.episode] = AnimeEpisodeMetadata(number: next.episode)
        }
        return values.values.sorted { $0.number < $1.number }
    }
}
