import Foundation

/// A season boundary is a calendar marker, not a promise that every show premieres that day.
public struct HomeSeasonCountdown: Sendable {
    public let current: SeasonSelection
    public let next: SeasonSelection
    public let startsAt: Date
    public let days: Int
    public let hours: Int
    public let minutes: Int
    public let progress: Double

    public init(now: Date = Date(), calendar: Calendar = .current) {
        var clock = Calendar(identifier: .gregorian); clock.timeZone = calendar.timeZone
        current = .current(at: now, calendar: clock); next = current.advanced(by: 1)
        let currentMonth = (AnimeSeason.allCases.firstIndex(of: current.season) ?? 0) * 3 + 1
        let nextMonth = (AnimeSeason.allCases.firstIndex(of: next.season) ?? 0) * 3 + 1
        let start = clock.date(from: DateComponents(year: current.year, month: currentMonth, day: 1))!
        startsAt = clock.date(from: DateComponents(year: next.year, month: nextMonth, day: 1))!
        let remaining = clock.dateComponents([.day, .hour, .minute], from: now, to: startsAt)
        days = max(0, remaining.day ?? 0); hours = max(0, remaining.hour ?? 0); minutes = max(0, remaining.minute ?? 0)
        progress = min(1, max(0, now.timeIntervalSince(start) / startsAt.timeIntervalSince(start)))
    }
}

public enum HomeSeasonContent {
    /// PREQUEL is provider evidence; similar titles are never treated as the same franchise.
    public static func returning(_ lineup: [Anime], library: [LibraryEntry]) -> [Anime] {
        let ids = Set(library.map(\.mediaId))
        return lineup.filter { anime in
            ids.contains(anime.id) || (anime.relations?.edges ?? []).contains {
                $0.relationType == "PREQUEL" && $0.node.map { $0.type == "ANIME" && ids.contains($0.id) } == true
            }
        }
    }
    public static func tonightCandidates(_ entries: [LibraryEntry], now: Date = Date()) -> [Anime] {
        HomeLibraryContent.unique(entries).compactMap { entry in
            guard let status = entry.status, [.watching, .rewatching, .planning].contains(status), let anime = entry.media,
                  let aired = anime.releasedEpisodeCount(at: now), aired > entry.progressValue else { return nil }
            return anime
        }.sorted { $0.id < $1.id }
    }
    public static func favorites(_ entries: [LibraryEntry]) -> [LibraryEntry] {
        HomeLibraryContent.unique(entries).filter { $0.status == .completed && $0.media != nil }.sorted {
            if ($0.score ?? 0) != ($1.score ?? 0) { return ($0.score ?? 0) > ($1.score ?? 0) }
            return ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0)
        }
    }
}
