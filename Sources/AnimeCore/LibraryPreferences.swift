import Foundation

public enum LibraryScope: String, CaseIterable, Identifiable, Sendable {
    case anime, reading, combined
    public var id: String { rawValue }
    public var label: String {
        switch self { case .anime: return "Anime"; case .reading: return "MangaBaka"; case .combined: return "All stories" }
    }
    public var defaultStatusKey: String { "library.\(rawValue).defaultStatus" }
    public var initialStatus: String {
        switch self { case .anime: return LibraryStatus.watching.rawValue; case .reading: return "reading"; case .combined: return "active" }
    }
    public struct Status: Identifiable, Sendable { public let id: String; public let label: String }
    public var statuses: [Status] {
        switch self {
        case .anime: return [.init(id: "all", label: "All")] + LibraryStatus.allCases.map { .init(id: $0.rawValue, label: $0.label) }
        case .reading: return [.init(id: "all", label: "All")] + MangaBakaReadingStatus.allCases.map { .init(id: $0.rawValue, label: $0.label) }
        case .combined: return CombinedLibraryStatus.allCases.map { .init(id: $0.rawValue, label: $0.label) }
        }
    }
    public func openingStatus(in defaults: UserDefaults = .standard) -> String {
        let saved = defaults.string(forKey: defaultStatusKey)
        return statuses.first { $0.id == saved }?.id ?? initialStatus
    }
}

public enum ReadingLibrarySort: String, CaseIterable, Identifiable, Sendable {
    case updated = "Last updated", title = "Title", score = "Your score", rating = "Community rating"
    case progress = "Progress", volumes = "Volumes read", completion = "Completion", year = "Publication year"
    public var id: String { rawValue }
    public var defaultAscending: Bool { self == .title }
    public func directionLabel(ascending: Bool) -> String {
        switch self {
        case .title: return ascending ? "A–Z" : "Z–A"
        case .updated: return ascending ? "Oldest first" : "Newest first"
        case .year: return ascending ? "Oldest first" : "Newest first"
        default: return ascending ? "Lowest first" : "Highest first"
        }
    }
    public func sorted(_ values: [CombinedLibraryItem], ascending: Bool) -> [CombinedLibraryItem] {
        let numbers = Dictionary(values.compactMap { item in number(item).map { (item.id, $0) } }, uniquingKeysWith: { first, _ in first })
        return values.sorted { first, second in
            if self != .title {
                let a = numbers[first.id], b = numbers[second.id]
                if (a == nil) != (b == nil) { return a != nil }
                if let a, let b, a != b { return ascending ? a < b : a > b }
            }
            let order = first.title.localizedStandardCompare(second.title)
            if order == .orderedSame { return first.id < second.id }
            return self == .title && !ascending ? order == .orderedDescending : order == .orderedAscending
        }
    }
    public func sorted(_ values: [MangaBakaLibraryEntry], ascending: Bool) -> [MangaBakaLibraryEntry] {
        sorted(values.map(CombinedLibraryItem.reading), ascending: ascending).compactMap {
            if case .reading(let value) = $0 { return value }; return nil
        }
    }
    private func number(_ item: CombinedLibraryItem) -> Double? {
        switch item {
        case .anime(let entry):
            switch self {
            case .updated: return entry.updatedAt.map(Double.init)
            case .score: return entry.score.flatMap { $0 > 0 ? $0 : nil }
            case .rating: return entry.media?.averageScore.map(Double.init)
            case .progress: return Double(entry.progressValue)
            case .volumes: return nil
            case .year: return entry.media?.seasonYear.map(Double.init)
            case .completion: return entry.media?.episodes.flatMap { $0 > 0 ? min(1, Double(entry.progressValue) / Double($0)) : nil }
            case .title: return nil
            }
        case .reading(let entry):
            switch self {
            case .updated: return entry.updatedAt.flatMap(Self.timestamp)
            case .score: return entry.rating.flatMap { $0 > 0 ? Double($0) : nil }
            case .rating: return entry.series?.rating
            case .progress: return entry.chapter
            case .volumes: return entry.volume
            case .year: return entry.series?.year.map(Double.init)
            case .completion: return entry.series?.totalChapters.flatMap { $0 > 0 ? min(1, max(0, entry.chapter ?? 0) / $0) : nil }
            case .title: return nil
            }
        }
    }
    private static func timestamp(_ value: String) -> Double? {
        if let numeric = Double(value), numeric.isFinite { return numeric }
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = format.date(from: value) { return date.timeIntervalSince1970 }
        format.formatOptions = [.withInternetDateTime]
        return format.date(from: value)?.timeIntervalSince1970
    }
}
