import Foundation

/// Explore's loading lifecycle is independent of view recreation and testable
/// without SwiftUI. Only the newest season/content-policy attempt can publish.
public struct ExploreCatalogState: Sendable {
    public struct Key: Hashable, Sendable {
        public let selection: SeasonSelection
        public let includeAdult: Bool
    }
    public struct Attempt: Equatable, Sendable {
        public let key: Key
        public let refresh: Bool
        private let id = UUID()
    }
    public private(set) var response: ExploreResponse?
    public private(set) var loadedKey: Key?
    public private(set) var savedAt: Date?
    public private(set) var loading = false
    public private(set) var error: String?
    private var needsRefresh = true
    private var attempt: Attempt?
    public init() {}

    public mutating func begin(_ selection: SeasonSelection, includeAdult: Bool, refresh: Bool) -> Attempt? {
        let key = Key(selection: selection, includeAdult: includeAdult)
        guard refresh || loadedKey != key || needsRefresh else { return nil }
        if loadedKey != key { response = nil; loadedKey = nil; savedAt = nil }
        let next = Attempt(key: key, refresh: refresh)
        attempt = next; loading = true; error = nil; needsRefresh = true
        return next
    }
    public func isCurrent(_ requested: Attempt) -> Bool { attempt == requested }
    /// Returns true when a fresh saved catalog satisfies this attempt.
    @discardableResult
    public mutating func restore(_ saved: ExploreSnapshot, for requested: Attempt, now: Date = Date()) -> Bool {
        guard isCurrent(requested), saved.isUsable(for: requested.key.selection, at: now, includeAdult: requested.key.includeAdult) else { return false }
        response = saved.response; loadedKey = requested.key; savedAt = saved.savedAt
        if !requested.refresh && !saved.needsRefresh(at: now) { needsRefresh = false; return true }
        return false
    }
    @discardableResult
    public mutating func complete(_ response: ExploreResponse, for requested: Attempt) -> Bool {
        guard isCurrent(requested) else { return false }
        self.response = response; loadedKey = requested.key; savedAt = nil; needsRefresh = false
        return true
    }
    public mutating func fail(_ message: String, for requested: Attempt) {
        if isCurrent(requested) { error = message }
    }
    public mutating func finish(_ requested: Attempt) {
        if isCurrent(requested) { loading = false; attempt = nil }
    }
}
