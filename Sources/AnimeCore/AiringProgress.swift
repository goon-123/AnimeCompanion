import Foundation

public enum AiringProgressSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case broadcast, dub
    public var id: String { rawValue }
    public var label: String { self == .broadcast ? "Original broadcast" : "English dub" }
    public var shortLabel: String { self == .broadcast ? "SUB" : "DUB" }
}

public enum AiringCatchUpState: Sendable, Equatable { case caughtUp, behind, waiting, unknown }

/// Compares confirmed watched progress with released episodes, never the planned season total.
public struct LibraryAiringProgress: Sendable, Equatable {
    public let source: AiringProgressSource
    public let watched: Int
    public let released: Int?
    public let nextEpisode: Int?
    public let nextDate: Date?
    public let estimatedDate: Bool
    public let state: AiringCatchUpState
    public var behindCount: Int { max(0, (released ?? watched) - watched) }
    public var label: String {
        switch state {
        case .caughtUp: return "Caught up"
        case .behind: return "\(behindCount) \(behindCount == 1 ? "episode" : "episodes") behind"
        case .waiting: return "First episode upcoming"
        case .unknown: return "Airing · count unavailable"
        }
    }

    public init?(anime: Anime, watched: Int, source: AiringProgressSource = .broadcast,
                 dub: LibraryDubProgress? = nil, nextDub: ReleaseEvent? = nil, now: Date = Date()) {
        self.source = source
        self.watched = min(100_000, max(0, watched))
        switch source {
        case .broadcast:
            guard anime.status == "RELEASING" else { return nil }
            // An expired or inconsistent cached schedule cannot prove that someone is caught up.
            if let next = anime.nextAiringEpisode, next.date > now, next.episode > 0,
               anime.episodes.map({ $0 <= 0 || next.episode <= $0 }) ?? true {
                released = next.episode - 1; nextEpisode = next.episode; nextDate = next.date
            } else { released = nil; nextEpisode = nil; nextDate = nil }
            estimatedDate = false
        case .dub:
            // A first-episode announcement is not an ongoing dub. A finished original can still have an airing dub.
            guard let nextDub, nextDub.anime.id == anime.id, nextDub.kind == .dub, nextDub.episode > 1,
                  let date = nextDub.date, date > now,
                  nextDub.certainty == .verified || nextDub.certainty == .unverified else { return nil }
            nextEpisode = nextDub.episode; nextDate = date; estimatedDate = nextDub.certainty == .unverified
            if dub?.confidence == .reported, let count = dub?.released, count > 0, count < nextDub.episode,
               anime.episodes.map({ $0 <= 0 || count <= $0 }) ?? true { released = count }
            else { released = nil }
        }
        if let released {
            state = released == 0 ? .waiting : (self.watched >= released ? .caughtUp : .behind)
        } else { state = .unknown }
    }
}

public enum PlaybackEpisodeSelection {
    /// AniList owns the next episode for tracked titles; old local resume records cannot rewind or skip it.
    public static func initial(anime: Anime, entry: LibraryEntry?, resumeEpisode: Int?, requestedEpisode: Int? = nil) -> Int {
        guard anime.format != "MOVIE" else { return 1 }
        let limit = min(100_000, max(1, anime.episodes.flatMap { $0 > 0 ? $0 : nil } ?? 100_000))
        // An explicit episode-list choice is intentional; automatic resume still
        // follows AniList and never an unrelated local playback record.
        if let requestedEpisode { return min(limit, max(1, requestedEpisode)) }
        if let entry, entry.mediaId == anime.id { return min(limit, min(99_999, max(0, entry.progressValue)) + 1) }
        if let resumeEpisode, (1...limit).contains(resumeEpisode) { return resumeEpisode }
        return 1
    }
}

public enum AiringWatchlistGroup: String, CaseIterable, Identifiable, Sendable {
    case ready, caughtUp, upcoming, unverified
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .ready: return "Ready to watch"
        case .caughtUp: return "Caught up"
        case .upcoming: return "First episode upcoming"
        case .unverified: return "Release count unverified"
        }
    }
    public init(state: AiringCatchUpState) {
        switch state {
        case .behind: self = .ready
        case .caughtUp: self = .caughtUp
        case .waiting: self = .upcoming
        case .unknown: self = .unverified
        }
    }
}

/// The next unwatched episode is separate from a show's next broadcast or dub release.
public struct LibraryWatchProgress: Equatable, Sendable {
    public let nextEpisode: Int?
    public let label: String
    public init(anime: Anime, entry: LibraryEntry) {
        let watched = max(0, entry.progressValue)
        if anime.status == "NOT_YET_RELEASED" {
            nextEpisode = nil; label = "Not yet released"
        } else if anime.format == "MOVIE", watched >= 1 {
            nextEpisode = nil; label = "All episodes watched"
        } else if let total = anime.episodes, total > 0, watched >= total {
            nextEpisode = nil; label = "All episodes watched"
        } else if entry.status == .completed {
            nextEpisode = nil; label = "Completed"
        } else {
            let next = PlaybackEpisodeSelection.initial(anime: anime, entry: entry, resumeEpisode: nil)
            nextEpisode = next; label = anime.format == "MOVIE" ? "Ready to watch" : "Next: Ep \(next)"
        }
    }
}
