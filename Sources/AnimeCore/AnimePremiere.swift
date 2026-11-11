import Foundation

/// A planned season total is not evidence that episode metadata exists yet.
/// Exact episode-one times take precedence; partial dates stay partial in UI.
public enum AnimePremiere {
    public static func exactAiring(for anime: Anime) -> Date? {
        guard let next = anime.nextAiringEpisode, next.episode == 1 else { return nil }
        return next.date
    }
    public static func defersEpisodes(for anime: Anime, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if anime.status == "FINISHED" { return false }
        if let next = anime.nextAiringEpisode {
            if next.episode > 1 { return false }
            if next.episode == 1 { return next.date > now }
        }
        if anime.status == "NOT_YET_RELEASED" { return true }
        if let date = completeDate(anime.startDate, calendar: calendar), date <= calendar.startOfDay(for: now) { return false }
        if anime.status == "RELEASING" { return false }
        guard let start = anime.startDate, let year = start.year, year > 0 else { return false }
        let current = calendar.dateComponents([.year, .month], from: now)
        if year != current.year { return year > (current.year ?? year) }
        if let month = start.month, (1...12).contains(month), month != current.month {
            return month > (current.month ?? month)
        }
        return completeDate(start, calendar: calendar).map { $0 > calendar.startOfDay(for: now) } ?? false
    }
    public static func dateLabel(for anime: Anime) -> String {
        if let start = anime.startDate, let year = start.year, year > 0 { return start.label }
        if let season = anime.season, let year = anime.seasonYear { return "\(season.label) \(year)" }
        return "Date not announced"
    }
    private static func completeDate(_ value: AnimeDate?, calendar: Calendar) -> Date? {
        guard let value, let year = value.year, year > 0, let month = value.month,
              let day = value.day, (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let checked = calendar.dateComponents([.year, .month, .day], from: date)
        return checked.year == year && checked.month == month && checked.day == day ? date : nil
    }
}
