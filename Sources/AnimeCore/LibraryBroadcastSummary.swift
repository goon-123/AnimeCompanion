import Foundation

/// Library catch-up always follows the original broadcast, independently of
/// the user's schedule/audio preference and the number of dubbed releases.
public struct LibraryBroadcastSummary: Equatable, Sendable {
    public let aired: Int?
    public let state: AiringCatchUpState
    public let next: AiringEpisode?

    public init(anime: Anime, watched: Int, now: Date = Date()) {
        if let broadcast = LibraryAiringProgress(anime: anime, watched: watched, source: .broadcast, now: now) {
            aired = broadcast.released
            state = broadcast.state
            next = broadcast.nextDate == nil ? nil : anime.nextAiringEpisode
        } else {
            aired = ["FINISHED", "NOT_YET_RELEASED"].contains(anime.status ?? "") ? anime.releasedEpisodeCount(at: now) : nil
            if let aired {
                state = aired == 0 ? .waiting : (max(0, watched) >= aired ? .caughtUp : .behind)
            } else { state = .unknown }
            next = nil
        }
    }

    public func countdown(at now: Date) -> String? {
        guard let next else { return nil }
        let interval = next.date.timeIntervalSince(now)
        guard interval > 0 else { return "Airing time updating" }
        let minutes = max(1, Int(ceil(interval / 60)))
        if minutes < 60 { return "Airs in \(minutes)min" }
        let hours = minutes / 60
        if hours < 24 { return "Airs in \(hours)hrs" }
        let days = hours / 24, remainder = hours % 24
        return "Airs in \(days)d" + (remainder > 0 ? " \(remainder)hrs" : "")
    }
}

extension LibraryDubProgress {
    /// Announcements and inferred dates alone do not establish availability.
    public var hasAvailableDub: Bool {
        discoveryStatus == .available || discoveryStatus == .partial
    }
}
