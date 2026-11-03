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
                    .news, .reviews, .artwork, .trailer, .links]
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
        case .news: return "Series news"
        case .discussions: return "Discussions"
        case .reviews: return "Reviews & discussions"
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

/// Page-scoped, device-local order and visibility. The original array-only
/// format migrates without losing its order. Hiding never deletes content.
public struct SeriesDetailLayout: Equatable, Sendable {
    public let page: SeriesDetailPage
    public private(set) var order: [SeriesDetailSection]
    public private(set) var hidden: Set<SeriesDetailSection>
    public var visible: [SeriesDetailSection] { order.filter { !hidden.contains($0) } }
    private struct Saved: Codable {
        let order: [String]
        let hidden: [String]?
    }
    public init(page: SeriesDetailPage, saved: String = "") {
        self.page = page
        let data = Data(saved.utf8.prefix(16_385))
        let snapshot = data.count <= 16_384 ? (try? JSONDecoder().decode(Saved.self, from: data)) : nil
        let legacy = data.count <= 16_384 ? (try? JSONDecoder().decode([String].self, from: data)) : nil
        let values = snapshot?.order ?? legacy ?? []
        let allowed = Set(page.sections)
        var seen = Set<SeriesDetailSection>()
        order = values.compactMap(SeriesDetailSection.init(rawValue:)).map { page == .anime && $0 == .discussions ? .reviews : $0 }
            .filter { allowed.contains($0) && seen.insert($0).inserted }
        order += page.sections.filter { seen.insert($0).inserted }
        hidden = Set((snapshot?.hidden ?? []).compactMap(SeriesDetailSection.init(rawValue:))).intersection(allowed)
        if page == .anime, values.contains(SeriesDetailSection.discussions.rawValue),
           !(snapshot?.hidden ?? []).contains(SeriesDetailSection.discussions.rawValue) {
            hidden.remove(.reviews)
        }
    }
    public var saved: String {
        let value = Saved(order: order.map(\.rawValue), hidden: hidden.map(\.rawValue).sorted())
        return (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    public mutating func setVisible(_ section: SeriesDetailSection, _ visible: Bool) {
        guard order.contains(section) else { return }
        if visible { hidden.remove(section) } else { hidden.insert(section) }
    }
    public mutating func setAllVisible(_ visible: Bool) {
        hidden = visible ? [] : Set(order)
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
