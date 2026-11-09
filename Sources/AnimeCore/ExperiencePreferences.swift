import Foundation

public enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    public static let storageKey = "appearance.scheme.v1"
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}

/// Rotation and fractional grid widths share decoded posters instead of
/// retaining a different bitmap for every one-pixel layout variation.
public enum ArtworkDecodeSize {
    public static func pixels(for requested: Int) -> Int {
        let bounded = min(3200, max(128, requested))
        return [128, 192, 256, 384, 512, 768, 1024, 1536, 2048, 2560, 3200].first { $0 >= bounded } ?? 3200
    }
}

public enum HomeSection: String, CaseIterable, Identifiable, Sendable {
    case greeting, cinematicSpotlight, search, featureLinks, welcome, syncStatus
    case weekly, news, community, watching, reading, airing, shortcuts
    case today, catchUp, libraryStats, planned, randomPick, savedNews
    case seasonSpotlight, nextEpisode, watchlistBanners
    case seasonCountdown, nextSeason, returningSeries, tonightPick, hallOfFame
    case trendingAnime, trendingAnimePlain
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .greeting: return "Greeting & date"
        case .cinematicSpotlight: return "Cinematic Spotlight"
        case .search: return "Search"
        case .featureLinks: return "Quick access"
        case .welcome: return "Welcome & setup"
        case .syncStatus: return "Library sync status"
        case .weekly: return "Airing this week"
        case .news: return "Headlines"
        case .community: return "Community"
        case .watching: return "Continue watching"
        case .reading: return "Continue reading"
        case .airing: return "Up next"
        case .shortcuts: return "Your companion"
        case .today: return "Airing today"
        case .catchUp: return "Catch up"
        case .libraryStats: return "Library snapshot"
        case .planned: return "Plan to watch"
        case .randomPick: return "Pick something for me"
        case .savedNews: return "Saved stories"
        case .seasonSpotlight: return "Seasonal spotlight"
        case .nextEpisode: return "Next episode countdown"
        case .watchlistBanners: return "From your watchlist"
        case .seasonCountdown: return "Next season countdown"
        case .nextSeason: return "Next season premieres"
        case .returningSeries: return "Returning favorites"
        case .tonightPick: return "Tonight’s pick"
        case .hallOfFame: return "Your hall of fame"
        case .trendingAnime: return "Top 10 trending anime"
        case .trendingAnimePlain: return "Trending anime"
        }
    }
    public var symbol: String {
        switch self {
        case .greeting: return "sun.max"
        case .cinematicSpotlight: return "sparkles.rectangle.stack"
        case .search: return "magnifyingglass"
        case .featureLinks: return "square.grid.2x2"
        case .welcome: return "sparkles"
        case .syncStatus: return "arrow.triangle.2.circlepath"
        case .today: return "calendar.badge.clock"
        case .catchUp: return "play.rectangle.on.rectangle"
        case .libraryStats: return "chart.bar"
        case .planned: return "bookmark"
        case .randomPick: return "shuffle"
        case .savedNews: return "bookmark.square"
        case .seasonSpotlight: return "sparkles.rectangle.stack"
        case .nextEpisode: return "timer"
        case .watchlistBanners: return "rectangle.stack"
        case .seasonCountdown: return "calendar.badge.clock"
        case .nextSeason: return "sunrise.fill"
        case .returningSeries: return "arrow.clockwise"
        case .tonightPick: return "moon.stars.fill"
        case .hallOfFame: return "trophy.fill"
        case .trendingAnime: return "chart.line.uptrend.xyaxis"
        case .trendingAnimePlain: return "flame"
        case .watching: return "play.circle"; case .reading: return "book"
        case .weekly, .airing: return "calendar"; case .news: return "newspaper"; case .community: return "bubble.left.and.bubble.right"; case .shortcuts: return "square.grid.2x2" }
    }
    public var detail: String {
        switch self {
        case .greeting: return "Today's date and your Home greeting."
        case .cinematicSpotlight: return "Artwork-led watching, reading and discovery picks. Shown in Cinematic Home; hide or move it like any widget."
        case .search: return "Jump into anime, manga and novel search."
        case .featureLinks: return "Three shortcuts you can replace, swap or hide individually."
        case .welcome: return "Account setup when no library is connected."
        case .syncStatus: return "Library loading, sync errors and retry actions."
        case .weekly: return "Seven days of releases from your library."
        case .news: return "Latest headlines from your selected publishers."
        case .community: return "Anime conversations and episode discussions."
        case .watching: return "Resume anime from your watching list."
        case .reading: return "Your saved chapters, pages and reading library."
        case .airing: return "Your next original broadcasts in time order."
        case .shortcuts: return "Reading sources, recommendations and settings."
        case .today: return "Today's original and English dub releases for your shows."
        case .catchUp: return "Confirmed aired episodes you still have to watch."
        case .libraryStats: return "A quick look at your anime and reading libraries."
        case .planned: return "Titles saved to your AniList plan-to-watch list."
        case .randomPick: return "Shuffle your released plan-to-watch titles for an idea."
        case .savedNews: return "Return to articles you bookmarked in News."
        case .seasonSpotlight: return "Wide artwork banners for this season's popular anime."
        case .nextEpisode: return "A live countdown and artwork for your next original broadcast."
        case .watchlistBanners: return "A cinematic shelf of the shows you're currently watching."
        case .seasonCountdown: return "A cinematic countdown to the next anime season, with a live clock and lineup artwork."
        case .nextSeason: return "Discover next season’s popular premieres and their announced dates."
        case .returningSeries: return "Next-season sequels connected to your library, plus premieres you already saved."
        case .tonightPick: return "An artwork-led daily pick from released episodes and your plan-to-watch list."
        case .hallOfFame: return "Celebrate completed anime, ranked by your own AniList scores."
        case .trendingAnime: return "Ten trending anime with small ranking badges below the artwork."
        case .trendingAnimePlain: return "The original anime poster shelf, without ranking numbers."
        }
    }
    public static let optionalWidgets: Set<Self> = [.today, .catchUp, .libraryStats, .planned, .randomPick, .savedNews, .seasonSpotlight, .nextEpisode, .watchlistBanners, .seasonCountdown, .nextSeason, .returningSeries, .tonightPick, .hallOfFame, .trendingAnime, .trendingAnimePlain]
    public var supportsLayout: Bool { [.seasonSpotlight, .nextEpisode, .watchlistBanners, .seasonCountdown, .nextSeason, .returningSeries, .tonightPick, .hallOfFame, .news].contains(self) }
    public var supportsItemLimit: Bool { [.watching, .reading, .airing, .today, .catchUp, .planned, .savedNews, .seasonSpotlight, .watchlistBanners, .nextSeason, .returningSeries, .hallOfFame].contains(self) }
}

public enum HomeShortcut: String, CaseIterable, Identifiable, Sendable {
    case calendar, airing, news, community, library, explore, reading, savedNews
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .calendar: return "Calendar"
        case .airing: return "Airing Now"
        case .news: return "News"
        case .community: return "Community"
        case .library: return "My Library"
        case .explore: return "Explore"
        case .reading: return "Reading"
        case .savedNews: return "Saved stories"
        }
    }
    public var symbol: String {
        switch self {
        case .calendar: return "calendar"
        case .airing: return "play.rectangle"
        case .news: return "newspaper"
        case .community: return "bubble.left.and.bubble.right"
        case .library: return "books.vertical"
        case .explore: return "safari"
        case .reading: return "book"
        case .savedNews: return "bookmark"
        }
    }
    public var detail: String {
        switch self {
        case .calendar: return "Your week"
        case .airing: return "Catch up"
        case .news: return "Your briefing"
        case .community: return "Join the conversation"
        case .library: return "Your collection"
        case .explore: return "Find a new favorite"
        case .reading: return "Sources & chapters"
        case .savedNews: return "Read later"
        }
    }
}

public enum HomeWidgetSize: String, CaseIterable, Codable, Identifiable, Sendable {
    case compact, standard, expanded
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var itemLimit: Int { switch self { case .compact: return 3; case .standard: return 6; case .expanded: return 10 } }
}

public enum HomeWidgetLayout: String, CaseIterable, Codable, Identifiable, Sendable {
    case compact, poster, banner
    public var id: String { rawValue }
    public var title: String {
        switch self { case .compact: return "Small · Compact row"; case .poster: return "Medium · Poster card"; case .banner: return "Large · Cinematic banner" }
    }
}

/// All content is optional. Toolbar controls remain available even on an empty Home.
public struct HomePreferences: Equatable, Sendable {
    public static let storageKey = "home.sections.v1"
    public var order: [HomeSection]
    public private(set) var hidden: Set<HomeSection>
    private var sizes: [HomeSection: HomeWidgetSize]
    private var layouts: [HomeSection: HomeWidgetLayout]
    public private(set) var shortcuts: [HomeShortcut?]
    private struct Stored: Codable {
        var version: Int?
        let order: [String]
        let hidden: [String]
        var sizes: [String: String]?
        var layouts: [String: String]?
        var shortcuts: [String]?
    }
    public init(order: [HomeSection] = HomeSection.allCases, hidden: Set<HomeSection> = HomeSection.optionalWidgets,
                sizes: [HomeSection: HomeWidgetSize] = [:], layouts: [HomeSection: HomeWidgetLayout] = [:], shortcuts: [HomeShortcut?] = [.calendar, .airing, .news]) {
        var seen = Set<HomeSection>()
        self.order = (order + HomeSection.allCases).filter { seen.insert($0).inserted }
        self.hidden = hidden.union(HomeSection.optionalWidgets.subtracting(order))
        self.sizes = sizes.filter { $0.key.supportsItemLimit }
        self.layouts = layouts.filter { $0.key.supportsLayout }
        var used = Set<HomeShortcut>()
        self.shortcuts = (Array(shortcuts.prefix(3)) + Array(repeating: nil, count: max(0, 3 - shortcuts.count))).map {
            guard let value = $0, used.insert(value).inserted else { return nil }
            return value
        }
    }
    public init(saved: String?) {
        guard let data = saved?.data(using: .utf8), let value = try? JSONDecoder().decode(Stored.self, from: data) else {
            self.init(); return
        }
        var order = value.order.compactMap(HomeSection.init(rawValue:))
        if value.version == nil {
            // Preserve the old editable order and visibility. Previously fixed
            // content becomes editable in its original position on this upgrade.
            if !order.contains(.weekly) { order.insert(.weekly, at: 0) }
            if !order.contains(.news) { order.insert(.news, at: (order.firstIndex(of: .weekly) ?? 0) + 1) }
            if !order.contains(.community) { order.insert(.community, at: (order.firstIndex(of: .news) ?? 0) + 1) }
            order = [.greeting, .search, .featureLinks, .welcome, .syncStatus] + order
        }
        var hidden = Set(value.hidden.compactMap(HomeSection.init(rawValue:)))
        if !order.contains(.cinematicSpotlight) {
            let wasEmpty = !order.isEmpty && order.allSatisfy(hidden.contains)
            order.insert(.cinematicSpotlight, at: order.firstIndex(of: .greeting).map { $0 + 1 } ?? order.count)
            if wasEmpty { hidden.insert(.cinematicSpotlight) }
        }
        let sizes = (value.sizes ?? [:]).reduce(into: [HomeSection: HomeWidgetSize]()) { result, pair in
            if let section = HomeSection(rawValue: pair.key), let size = HomeWidgetSize(rawValue: pair.value) { result[section] = size }
        }
        let layouts = (value.layouts ?? [:]).reduce(into: [HomeSection: HomeWidgetLayout]()) { result, pair in
            if let section = HomeSection(rawValue: pair.key), let layout = HomeWidgetLayout(rawValue: pair.value) { result[section] = layout }
        }
        self.init(order: order, hidden: hidden, sizes: sizes, layouts: layouts,
                  shortcuts: value.shortcuts.map { $0.map(HomeShortcut.init(rawValue:)) } ?? [.calendar, .airing, .news])
    }
    public var visible: [HomeSection] { order.filter { !hidden.contains($0) } }
    public mutating func setVisible(_ section: HomeSection, _ shown: Bool) {
        if shown { hidden.remove(section) } else { hidden.insert(section) }
    }
    public mutating func setAllVisible(_ shown: Bool) { hidden = shown ? [] : Set(HomeSection.allCases) }
    /// Selecting an existing shortcut swaps its slot, preserving both destinations.
    public mutating func setShortcut(_ shortcut: HomeShortcut?, at index: Int) {
        guard shortcuts.indices.contains(index) else { return }
        if let shortcut, let other = shortcuts.firstIndex(of: shortcut), other != index { shortcuts[other] = shortcuts[index] }
        shortcuts[index] = shortcut
    }
    public func size(for section: HomeSection) -> HomeWidgetSize { sizes[section] ?? .standard }
    public mutating func setSize(_ size: HomeWidgetSize, for section: HomeSection) {
        guard section.supportsItemLimit else { return }
        sizes[section] = size
    }
    public func layout(for section: HomeSection) -> HomeWidgetLayout { layouts[section] ?? .banner }
    public mutating func setLayout(_ layout: HomeWidgetLayout, for section: HomeSection) {
        guard section.supportsLayout else { return }; layouts[section] = layout
    }
    /// Move relative to visible neighbors without disturbing hidden widget order.
    public mutating func move(_ section: HomeSection, before target: HomeSection) {
        guard section != target, order.contains(section), order.contains(target) else { return }
        order.removeAll { $0 == section }
        order.insert(section, at: order.firstIndex(of: target)!)
    }
    public mutating func move(_ section: HomeSection, after target: HomeSection) {
        guard section != target, order.contains(section), order.contains(target) else { return }
        order.removeAll { $0 == section }
        order.insert(section, at: order.firstIndex(of: target)! + 1)
    }
    public var saved: String {
        let value = Self(order: order, hidden: hidden, sizes: sizes, layouts: layouts, shortcuts: shortcuts)
        let storedSizes = Dictionary(uniqueKeysWithValues: value.sizes.map { ($0.key.rawValue, $0.value.rawValue) })
        let storedLayouts = Dictionary(uniqueKeysWithValues: value.layouts.map { ($0.key.rawValue, $0.value.rawValue) })
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return String(data: try! encoder.encode(Stored(version: 4, order: value.order.map(\.rawValue), hidden: value.order.filter(value.hidden.contains).map(\.rawValue), sizes: storedSizes, layouts: storedLayouts, shortcuts: value.shortcuts.map { $0?.rawValue ?? "" })), encoding: .utf8)!
    }
}

public enum StorySearchScope: String, CaseIterable, Identifiable, Sendable {
    case all, anime, manga, novels
    public var id: String { rawValue }
    public var label: String { self == .all ? "All stories" : rawValue.capitalized }
    public var needsAnime: Bool { self == .all || self == .anime }
    public var needsReading: Bool { self != .anime }
    public func includes(_ story: ExploreStory) -> Bool {
        switch story {
        case .anime: return needsAnime
        case .reading(let value): return needsReading && (self == .all || (self == .novels ? value.type == "novel" : value.type != "novel"))
        }
    }
}

public struct LibraryViewPreset: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public let query: String
    public let status: String
    public let sort: String
    public let ascending: Bool
    public let layout: String
    public init(id: UUID = UUID(), name: String, query: String, status: String, sort: String, ascending: Bool, layout: String) {
        self.id = id; self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        self.query = String(query.prefix(300))
        self.status = CombinedLibraryStatus(rawValue: status)?.rawValue ?? CombinedLibraryStatus.active.rawValue
        self.sort = ReadingLibrarySort(rawValue: sort)?.rawValue ?? ReadingLibrarySort.title.rawValue
        self.ascending = ascending; self.layout = layout == "list" ? "list" : "grid"
    }
}

public struct LibraryViewPresets: Equatable, Sendable {
    public static let storageKey = "library.savedViews.v1"
    public static let limit = 12
    public private(set) var items: [LibraryViewPreset]
    public init(saved: String? = nil) {
        let values: [LibraryViewPreset]
        if let data = saved?.data(using: .utf8), let decoded = try? JSONDecoder().decode([LibraryViewPreset].self, from: data) { values = decoded }
        else { values = [] }
        var seen = Set<UUID>()
        items = Array(values.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0.id).inserted }.prefix(Self.limit)).map {
            LibraryViewPreset(id: $0.id, name: $0.name, query: $0.query, status: $0.status, sort: $0.sort, ascending: $0.ascending, layout: $0.layout)
        }
    }
    @discardableResult public mutating func add(_ preset: LibraryViewPreset) -> Bool {
        guard !preset.name.isEmpty, items.count < Self.limit else { return false }
        items.append(preset); return true
    }
    public mutating func remove(_ id: UUID) { items.removeAll { $0.id == id } }
    public var saved: String { String(data: try! JSONEncoder().encode(items), encoding: .utf8)! }
}
