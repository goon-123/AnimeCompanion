import Foundation

public enum ExploreSurface: String, CaseIterable, Sendable {
    case anime, discovery, grid, reading
    public var storageKey: String { "explore.layout.\(rawValue).v1" }
    public var catalog: [ExploreCatalogRow] {
        switch self {
        case .anime: return [.spotlight, .trending, .topTen, .studios, .animeGenres, .seasonal, .previousSeason, .topAnime, .upcoming]
        case .discovery: return [.directory, .spotlight, .trending, .topTen, .studios, .animeGenres, .seasonal, .previousSeason, .topAnime, .novels, .manga, .personal, .gems, .upcoming]
        case .grid: return [.directory, .posterWall, .trending, .topTen, .studios, .animeGenres, .seasonal, .previousSeason, .topAnime]
        case .reading: return [.spotlight, .personal, .formats, .genres, .readingTrending, .rising, .gems, .popular, .topReading, .newReleases, .recentlyAdded]
        }
    }
}

public enum ExploreCatalogRow: String, CaseIterable, Sendable {
    case spotlight, directory, trending, seasonal, previousSeason, topAnime, upcoming
    case novels, manga, personal, gems, posterWall, formats, genres
    case readingTrending, rising, popular, topReading, newReleases, recentlyAdded
    case studios, animeGenres, topTen
    public var title: String {
        switch self {
        case .spotlight: return "Spotlight"
        case .directory: return "Browse by format"
        case .trending: return "Trending anime"
        case .topTen: return "Top 10 trending anime"
        case .seasonal: return "This season"
        case .previousSeason: return "Previous season"
        case .topAnime: return "Top anime of all time"
        case .upcoming: return "Coming soon"
        case .novels: return "Novels"
        case .manga: return "Manga & manhwa"
        case .personal: return "For your next read"
        case .gems: return "Hidden gems"
        case .posterWall: return "A world of stories"
        case .formats: return "Reading formats"
        case .genres: return "Genres & tags"
        case .readingTrending: return "Trending reads"
        case .rising: return "Rising reads"
        case .popular: return "Popular reads"
        case .topReading: return "Top rated reads"
        case .newReleases: return "New releases"
        case .recentlyAdded: return "Recently added"
        case .studios: return "Animation Studios"
        case .animeGenres: return "Anime Genres"
        }
    }
    public var discoveryCategory: DiscoveryCategory? {
        switch self {
        case .trending, .topTen: return .trending
        case .seasonal: return .seasonal
        case .previousSeason: return .previousSeason
        case .topAnime: return .topRated
        case .upcoming: return .upcoming
        default: return nil
        }
    }
    public var readingShelf: MangaBakaShelf? {
        switch self {
        case .readingTrending: return .trending
        case .rising: return .rising
        case .gems: return .hiddenGems
        case .popular: return .popular
        case .topReading: return .topRated
        case .newReleases: return .newReleases
        case .recentlyAdded: return .recentlyAdded
        default: return nil
        }
    }
    public var supportsCardSize: Bool { self == .studios || self == .animeGenres }
}

public enum ExploreCollectionSize: String, CaseIterable, Codable, Identifiable, Sendable {
    case small, medium, large
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum ExploreRow: Hashable, Identifiable, Sendable {
    case catalog(ExploreCatalogRow), widget(HomeSection)
    public var id: String {
        switch self { case .catalog(let row): return "catalog." + row.rawValue; case .widget(let section): return "widget." + section.rawValue }
    }
    public var title: String {
        switch self { case .catalog(let row): return row.title; case .widget(let section): return section.title }
    }
    public init?(id: String) {
        let parts = id.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        if parts[0] == "catalog", let row = ExploreCatalogRow(rawValue: parts[1]) { self = .catalog(row) }
        else if parts[0] == "widget", let section = HomeSection(rawValue: parts[1]) { self = .widget(section) }
        else { return nil }
    }
}

/// Explore keeps its own arrangement and widget options. Home is never written.
/// Unadded widgets stay out of the reorder list until the user chooses them.
public struct ExplorePreferences: Equatable, Sendable {
    public let surface: ExploreSurface
    public private(set) var order: [ExploreRow]
    public private(set) var hidden: Set<ExploreRow>
    private var cardSizes: [ExploreCatalogRow: ExploreCollectionSize]
    public var widgetOptions: HomePreferences
    public var visible: [ExploreRow] { order.filter { !hidden.contains($0) } }
    public var hasWidgets: Bool { visible.contains { if case .widget = $0 { return true }; return false } }
    private struct Saved: Codable {
        let order: [String]; let hidden: [String]; let widgets: String?
        let cardSizes: [String: String]?
    }
    public init(surface: ExploreSurface, saved: String = "") {
        self.surface = surface
        let data = Data(saved.utf8.prefix(65_537))
        let value = data.count <= 65_536 ? (try? JSONDecoder().decode(Saved.self, from: data)) : nil
        var seen = Set<ExploreRow>()
        order = (value?.order ?? []).compactMap(ExploreRow.init(id:)).filter { row in
            if case .catalog(let catalog) = row, !surface.catalog.contains(catalog) { return false }
            return seen.insert(row).inserted
        }
        let addsRanking = !order.contains(.catalog(.topTen)) && surface.catalog.contains(.topTen)
        if addsRanking, let index = order.firstIndex(of: .catalog(.trending)) {
            order.insert(.catalog(.topTen), at: index + 1)
            seen.insert(.catalog(.topTen))
        }
        order += surface.catalog.map(ExploreRow.catalog).filter { seen.insert($0).inserted }
        hidden = Set((value?.hidden ?? []).compactMap(ExploreRow.init(id:))).intersection(order)
        // A previously hidden ranked Trending row stays hidden on upgrade.
        if addsRanking, value?.hidden.contains("catalog.trending") == true { hidden.insert(.catalog(.topTen)) }
        cardSizes = (value?.cardSizes ?? [:]).reduce(into: [:]) { result, entry in
            if let row = ExploreCatalogRow(rawValue: entry.key), row.supportsCardSize, surface.catalog.contains(row),
               let size = ExploreCollectionSize(rawValue: entry.value) { result[row] = size }
        }
        widgetOptions = HomePreferences(saved: value?.widgets)
    }
    public func cardSize(for row: ExploreCatalogRow) -> ExploreCollectionSize { cardSizes[row] ?? .small }
    public mutating func setCardSize(_ size: ExploreCollectionSize, for row: ExploreCatalogRow) {
        guard row.supportsCardSize, surface.catalog.contains(row) else { return }
        cardSizes[row] = size
    }
    public mutating func setVisible(_ row: ExploreRow, _ shown: Bool) {
        if !order.contains(row) {
            guard shown, case .widget = row else { return }
            order.append(row)
        }
        if shown { hidden.remove(row) } else { hidden.insert(row) }
    }
    public mutating func addWidget(_ section: HomeSection, copying home: HomePreferences) {
        let row = ExploreRow.widget(section)
        if !order.contains(row) {
            widgetOptions.setSize(home.size(for: section), for: section)
            widgetOptions.setLayout(home.layout(for: section), for: section)
            if section == .featureLinks {
                for (index, shortcut) in home.shortcuts.enumerated() { widgetOptions.setShortcut(shortcut, at: index) }
            }
        }
        setVisible(row, true)
    }
    public mutating func setAllVisible(_ shown: Bool) { hidden = shown ? [] : Set(order) }
    public mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard !offsets.isEmpty, offsets.allSatisfy({ order.indices.contains($0) }), (0...order.count).contains(destination) else { return }
        let moving = offsets.map { order[$0] }
        var remaining = order.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        remaining.insert(contentsOf: moving, at: destination - offsets.filter { $0 < destination }.count)
        order = remaining
    }
    public mutating func move(_ row: ExploreRow, by offset: Int) {
        guard let index = visible.firstIndex(of: row), visible.indices.contains(index + offset),
              let from = order.firstIndex(of: row), let target = order.firstIndex(of: visible[index + offset]) else { return }
        move(fromOffsets: IndexSet(integer: from), toOffset: offset < 0 ? target : target + 1)
    }
    public var saved: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let sizes = Dictionary(uniqueKeysWithValues: cardSizes.map { ($0.key.rawValue, $0.value.rawValue) })
        let value = Saved(order: order.map(\.id), hidden: hidden.map(\.id).sorted(), widgets: widgetOptions.saved, cardSizes: sizes)
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
