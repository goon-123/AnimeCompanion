import Foundation

public enum AppTab: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case home, explore, library, manga, schedule, news
    /// Retired destinations remain decodable for old backups and shortcuts.
    public static let navigationTabs: [AppTab] = [.home, .explore, .library]
    public var belongsToHome: Bool { self == .schedule || self == .news }
    public var id: String { rawValue }
    public var title: String {
        switch self { case .home: return "Home"; case .explore: return "Explore"; case .library: return "My Library"
        case .manga: return "Manga"; case .schedule: return "Schedule"; case .news: return "News" }
    }
    public var symbol: String {
        switch self { case .home: return "house"; case .explore: return "safari"; case .library: return "books.vertical"
        case .manga: return "book.closed"; case .schedule: return "calendar"; case .news: return "newspaper" }
    }
}

/// Hiding a destination never deletes its data. Keep a reachable root even if
/// stored preferences contain duplicates, unknown tabs or no visible tabs.
public struct AppTabPreferences: Equatable, Sendable {
    public static let storageKey = "navigation.tabs.v1"
    public var order: [AppTab]
    public private(set) var hidden: Set<AppTab>
    public init(order: [AppTab] = AppTab.navigationTabs, hidden: Set<AppTab> = []) {
        var seen = Set<AppTab>()
        let movedReading = order.contains(.manga) && !hidden.contains(.manga)
        let mapped = order.map { $0 == .manga ? AppTab.explore : $0 }
        let upgraded = mapped.contains(.home) ? mapped : [.home] + mapped
        self.order = (upgraded + AppTab.navigationTabs).filter { AppTab.navigationTabs.contains($0) && seen.insert($0).inserted }
        self.hidden = hidden.intersection(Set(AppTab.navigationTabs)).subtracting([.home])
        if movedReading { self.hidden.remove(.explore) }
    }
    private struct Stored: Codable { let order: [String]; let hidden: [String] }
    public init(saved: String?) {
        guard let saved, let data = saved.data(using: .utf8), let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            self.init(); return
        }
        let hidden = Set(stored.hidden.compactMap(AppTab.init(rawValue:)))
        self.init(order: stored.order.compactMap(AppTab.init(rawValue:)), hidden: hidden)
    }
    public var visible: [AppTab] { order.filter { AppTab.navigationTabs.contains($0) && !hidden.contains($0) } }
    public var saved: String {
        let normalized = Self(order: order, hidden: hidden)
        let stored = Stored(order: normalized.order.map(\.rawValue), hidden: normalized.order.filter(normalized.hidden.contains).map(\.rawValue))
        return String(data: try! JSONEncoder().encode(stored), encoding: .utf8)!
    }
    public mutating func setVisible(_ tab: AppTab, _ shown: Bool) {
        guard tab != .home, AppTab.navigationTabs.contains(tab) else { return }
        if shown { hidden.remove(tab) }
        else if visible.count > 1 { hidden.insert(tab) }
    }
    public func selection(for requested: AppTab) -> AppTab {
        let destination: AppTab = requested == .manga ? .explore : requested
        return visible.contains(destination) ? destination : .home
    }
}
