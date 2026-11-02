import Foundation

public enum SeriesDetailPage: String, CaseIterable, Hashable, Sendable {
    case anime, manga, reader
    public var storageKey: String { "series.layout.\(rawValue).v1" }
    public var title: String {
        switch self {
        case .anime: return "Anime sections"
        case .manga: return "Manga & novel sections"
        case .reader: return "Reader sections"
        }
    }
    public var explanation: String {
        switch self {
        case .anime: return "Drag the handles to arrange the Info tab for all anime. Episodes keep their own tab."
        case .manga: return "Drag the handles to arrange all manga and novel series pages."
        case .reader: return "Drag the handles to arrange all reading-source detail pages."
        }
    }
    public var sections: [SeriesDetailSection] {
        switch self {
        case .anime:
            return [.watchlist, .synopsis, .information, .broadcast, .related, .recommendations,
                    .dubSchedule, .news, .discussions, .reviews, .artwork, .trailer, .links]
        case .manga:
            return [.watchlist, .reading, .synopsis, .publication, .tags, .adaptations,
                    .coverage, .related, .artwork, .links]
        case .reader:
            return [.reading, .synopsis, .chapters, .genres, .sourceLink]
        }
    }
}

public enum SeriesDetailSection: String, Identifiable, Codable, Hashable, Sendable {
    case watchlist, synopsis, information, broadcast, related, recommendations, artwork, trailer
    case dubSchedule, news, discussions, reviews, links, reading, publication, adaptations, coverage
    case tags, chapters, genres, sourceLink
    public var id: String { rawValue }
    public func title(on page: SeriesDetailPage) -> String {
        switch self {
        case .watchlist: return page == .anime ? "Watchlist & progress" : "Library & progress"
        case .synopsis: return page == .manga ? "The story" : "Synopsis"
        case .information: return "Information"
        case .broadcast: return "Original broadcast"
        case .related: return page == .manga ? "Related & recommendations" : "Related entries"
        case .recommendations: return "You may also like"
        case .artwork: return page == .manga ? "Artwork & covers" : "Artwork"
        case .trailer: return "Trailer"
        case .dubSchedule: return "English dub"
        case .news: return "Headlines"
        case .discussions: return "Discussions"
        case .reviews: return "Reviews"
        case .links: return "Links"
        case .reading: return page == .reader ? "Continue reading" : "Reading source"
        case .publication: return "Publication & ratings"
        case .adaptations: return "Related anime"
        case .coverage: return "Anime chapter coverage"
        case .tags: return "Tags"
        case .chapters: return "Chapters"
        case .genres: return "Genres"
        case .sourceLink: return "Library link"
        }
    }
}

/// Page-scoped, device-local preferences. Unknown/removed sections are ignored;
/// newly introduced sections are appended without disturbing a saved order.
public struct SeriesDetailLayout: Equatable, Sendable {
    public let page: SeriesDetailPage
    public private(set) var order: [SeriesDetailSection]
    public init(page: SeriesDetailPage, saved: String = "") {
        self.page = page
        let values = saved.utf8.count <= 16_384
            ? (try? JSONDecoder().decode([String].self, from: Data(saved.utf8))) ?? [] : []
        let allowed = Set(page.sections)
        var seen = Set<SeriesDetailSection>()
        order = values.compactMap(SeriesDetailSection.init(rawValue:))
            .filter { allowed.contains($0) && seen.insert($0).inserted }
        order += page.sections.filter { seen.insert($0).inserted }
    }
    public var saved: String {
        (try? JSONEncoder().encode(order.map(\.rawValue))).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    /// Uses the same original-array destination indices as SwiftUI's onMove.
    public mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard !offsets.isEmpty, offsets.allSatisfy({ order.indices.contains($0) }),
              (0...order.count).contains(destination) else { return }
        let moving = offsets.map { order[$0] }
        var remaining = order.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertion = destination - offsets.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: insertion)
        order = remaining
    }
}

public enum SeriesDetailSizing {
    public static func posterWidth(availableWidth: Double, isTablet: Bool) -> Double {
        let preferred = isTablet ? 200.0 : 128.0
        guard availableWidth.isFinite, availableWidth > 0 else { return preferred }
        return min(preferred, max(80, availableWidth * 0.42), availableWidth)
    }
}
