import Foundation

public enum CombinedLibraryStatus: String, CaseIterable, Identifiable, Sendable {
    case all, active, planned, completed, paused, dropped
    public var id: String { rawValue }
    public var label: String {
        switch self { case .all: return "All"; case .active: return "In progress"; case .planned: return "Planned"
        case .completed: return "Completed"; case .paused: return "Paused"; case .dropped: return "Dropped" }
    }
}

/// Provider-scoped identities and original progress units remain distinct in a
/// single browsing view. An adaptation and its written series are separate rows.
public enum CombinedLibraryItem: Identifiable, Sendable {
    case anime(LibraryEntry), reading(MangaBakaLibraryEntry)
    public var id: String {
        switch self { case .anime(let value): return "anilist:\(value.mediaId)"
        case .reading(let value): return "mangabaka:\(value.id)" }
    }
    public var title: String {
        switch self { case .anime(let value): return value.media?.displayTitle ?? "Untitled anime"
        case .reading(let value): return value.series?.displayTitle ?? "Untitled series" }
    }
    public var status: CombinedLibraryStatus? {
        switch self {
        case .anime(let value):
            switch value.status { case .watching, .rewatching: return .active; case .planning: return .planned
            case .completed: return .completed; case .paused: return .paused; case .dropped: return .dropped; case nil: return nil }
        case .reading(let value):
            switch value.state { case "reading", "rereading": return .active; case "plan_to_read": return .planned
            case "completed": return .completed; case "paused": return .paused; case "dropped": return .dropped; default: return nil }
        }
    }
    public static func merge(anime: [LibraryEntry], reading: [MangaBakaLibraryEntry], includeAdult: Bool,
        query: String = "", status: CombinedLibraryStatus = .all) -> [Self] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        let entries = anime.map(Self.anime) + reading.map(Self.reading)
        return entries.filter { item in
            guard seen.insert(item.id).inserted, status == .all || status == item.status else { return false }
            let titles: [String]
            switch item {
            case .anime(let entry):
                guard let media = entry.media, includeAdult || media.isAdult != true else { return false }
                titles = [media.displayTitle, media.title?.english ?? "", media.title?.romaji ?? "", media.title?.native ?? ""]
            case .reading(let entry):
                guard let series = entry.series, series.isVisible(includeAdult: includeAdult) else { return false }
                titles = [series.displayTitle, series.title, series.nativeTitle ?? ""] + series.titles.map(\.title)
            }
            return text.isEmpty || titles.contains { $0.localizedStandardContains(text) }
        }.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
