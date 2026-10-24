import Foundation

/// Private, in-memory recommendations outlive the scroll view's section lifecycle.
/// Refreshes keep the last result; account changes invalidate every old completion.
public struct MangaBakaRecommendationsState: Sendable {
    public struct Key: Equatable, Sendable {
        let account: UUID
        let revision: UUID
        let includeAdult: Bool
    }
    public struct Attempt: Equatable, Sendable {
        let key: Key
        private let id = UUID()
    }
    public private(set) var items: [MangaBakaSeries] = []
    public private(set) var loading = false
    public private(set) var error: String?
    private var key: Key?
    private var loadedKey: Key?
    private var attempt: Attempt?

    public init() {}

    public mutating func begin(account: UUID, revision: UUID, includeAdult: Bool, refresh: Bool = false) -> Attempt? {
        let requested = Key(account: account, revision: revision, includeAdult: includeAdult)
        guard attempt?.key != requested, refresh || loadedKey != requested else { return nil }
        if key?.account != account { items = [] }
        else { items = items.filter { $0.isVisible(includeAdult: includeAdult) } }
        let next = Attempt(key: requested)
        key = requested; loadedKey = nil; attempt = next; loading = true; error = nil
        return next
    }

    public func isCurrent(_ requested: Attempt) -> Bool { attempt == requested }

    @discardableResult
    public mutating func complete(_ records: [MangaBakaSeries], for requested: Attempt) -> Bool {
        guard isCurrent(requested) else { return false }
        var seen = Set<Int>()
        items = records.filter { $0.isVisible(includeAdult: requested.key.includeAdult) && seen.insert($0.id).inserted }
        loadedKey = requested.key
        return true
    }

    public mutating func fail(_ message: String, for requested: Attempt) {
        if isCurrent(requested) { error = message }
    }

    public mutating func finish(_ requested: Attempt) {
        if isCurrent(requested) { loading = false; attempt = nil }
    }

    public mutating func reset() { self = Self() }
}
