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
    case watching, reading, airing, shortcuts
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .watching: return "Continue watching"
        case .reading: return "Continue reading"
        case .airing: return "Up next"
        case .shortcuts: return "Your companion"
        }
    }
    public var symbol: String {
        switch self { case .watching: return "play.circle"; case .reading: return "book"
        case .airing: return "calendar"; case .shortcuts: return "square.grid.2x2" }
    }
}

/// A new preference namespace leaves every existing layout and account untouched.
public struct HomePreferences: Equatable, Sendable {
    public static let storageKey = "home.sections.v1"
    public var order: [HomeSection]
    public private(set) var hidden: Set<HomeSection>
    private struct Stored: Codable { let order: [String]; let hidden: [String] }
    public init(order: [HomeSection] = HomeSection.allCases, hidden: Set<HomeSection> = []) {
        var seen = Set<HomeSection>()
        self.order = (order + HomeSection.allCases).filter { seen.insert($0).inserted }
        self.hidden = hidden
        if self.order.allSatisfy(hidden.contains) { self.hidden.remove(.shortcuts) }
    }
    public init(saved: String?) {
        guard let data = saved?.data(using: .utf8), let value = try? JSONDecoder().decode(Stored.self, from: data) else {
            self.init(); return
        }
        self.init(order: value.order.compactMap(HomeSection.init(rawValue:)), hidden: Set(value.hidden.compactMap(HomeSection.init(rawValue:))))
    }
    public var visible: [HomeSection] { order.filter { !hidden.contains($0) } }
    public mutating func setVisible(_ section: HomeSection, _ shown: Bool) {
        if shown { hidden.remove(section) } else if visible.count > 1 { hidden.insert(section) }
    }
    public var saved: String {
        let value = Self(order: order, hidden: hidden)
        return String(data: try! JSONEncoder().encode(Stored(order: value.order.map(\.rawValue), hidden: value.order.filter(value.hidden.contains).map(\.rawValue))), encoding: .utf8)!
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
