import Foundation

public enum AppTab: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case explore, library, manga, schedule, news
    public var id: String { rawValue }
    public var title: String {
        switch self { case .explore: return "Explore"; case .library: return "My Library"
        case .manga: return "Manga"; case .schedule: return "Schedule"; case .news: return "News" }
    }
    public var symbol: String {
        switch self { case .explore: return "safari"; case .library: return "books.vertical"
        case .manga: return "book.closed"; case .schedule: return "calendar"; case .news: return "newspaper" }
    }
}

/// Hiding a destination never deletes its data. Keep a reachable root even if
/// stored preferences contain duplicates, unknown tabs or no visible tabs.
public struct AppTabPreferences: Equatable, Sendable {
    public static let storageKey = "navigation.tabs.v1"
    public var order: [AppTab]
    public private(set) var hidden: Set<AppTab>
    public init(order: [AppTab] = AppTab.allCases, hidden: Set<AppTab> = [.manga]) {
        var seen = Set<AppTab>()
        self.order = (order + AppTab.allCases).filter { seen.insert($0).inserted }
        self.hidden = hidden
        if self.order.allSatisfy(hidden.contains) { self.hidden.remove(self.order[0]) }
    }
    private struct Stored: Codable { let order: [String]; let hidden: [String] }
    public init(saved: String?) {
        guard let saved, let data = saved.data(using: .utf8), let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            self.init(); return
        }
        self.init(order: stored.order.compactMap(AppTab.init(rawValue:)), hidden: Set(stored.hidden.compactMap(AppTab.init(rawValue:))))
    }
    public var visible: [AppTab] { order.filter { !hidden.contains($0) } }
    public var saved: String {
        let normalized = Self(order: order, hidden: hidden)
        let stored = Stored(order: normalized.order.map(\.rawValue), hidden: normalized.order.filter(hidden.contains).map(\.rawValue))
        return String(data: try! JSONEncoder().encode(stored), encoding: .utf8)!
    }
    public mutating func setVisible(_ tab: AppTab, _ shown: Bool) {
        if shown { hidden.remove(tab) }
        else if visible.count > 1 { hidden.insert(tab) }
    }
    public func selection(for requested: AppTab) -> AppTab { visible.contains(requested) ? requested : visible.first ?? .explore }
}
