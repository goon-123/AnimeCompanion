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
}
