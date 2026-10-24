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
    public private(set) var hasResult = false
    public private(set) var receivedCount = 0
    public private(set) var unverifiedCount = 0
    public private(set) var status: MangaBakaRecommendationStatus?
    private var expiresAt = Date.distantPast
    private var key: Key?
    private var loadedKey: Key?
    private var attempt: Attempt?

    public init() {}

    public mutating func begin(account: UUID, revision: UUID, includeAdult: Bool, refresh: Bool = false, now: Date = Date()) -> Attempt? {
        let requested = Key(account: account, revision: revision, includeAdult: includeAdult)
        guard attempt?.key != requested, refresh || loadedKey != requested || now >= expiresAt else { return nil }
        if key?.account != account { items = []; hasResult = false; status = nil; receivedCount = 0; unverifiedCount = 0 }
        else { items = items.filter { $0.isVisible(includeAdult: includeAdult) } }
        let next = Attempt(key: requested)
        key = requested; loadedKey = nil; attempt = next; loading = true; error = nil
        return next
    }

    public func isCurrent(_ requested: Attempt) -> Bool { attempt == requested }

    @discardableResult
    public mutating func complete(_ records: [MangaBakaSeries], for requested: Attempt,
        status: MangaBakaRecommendationStatus? = nil, now: Date = Date()) -> Bool {
        guard isCurrent(requested) else { return false }
        var seen = Set<Int>()
        items = records.filter { $0.isVisible(includeAdult: requested.key.includeAdult) && seen.insert($0.id).inserted }
        receivedCount = records.count
        unverifiedCount = records.filter { MangaBakaContentRating(rawValue: $0.contentRating ?? "") == nil }.count
        self.status = status; hasResult = true
        // A temporarily empty service response must not freeze the rail for
        // the rest of this account session. Loaded cards still survive scrolls.
        expiresAt = now.addingTimeInterval(items.isEmpty ? 30 : 300)
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

    public var canRetryEmptyResult: Bool {
        hasResult && items.isEmpty && error == nil && status?.coldStart != true
            && (receivedCount == 0 || unverifiedCount > 0)
    }

    public var emptyMessage: String {
        if !hasResult { return "Recommendations haven’t loaded yet. Tap Refresh to try again." }
        if unverifiedCount > 0 { return "Some recommended series are missing content details. Tap Refresh to try loading them again." }
        if receivedCount > 0 { return "No recommended titles match your current content settings." }
        if status?.coldStart == true {
            let count = status?.libraryCount.map { " (\($0.formatted()) titles in your MangaBaka library)" } ?? ""
            return "MangaBaka is still building your recommendation profile\(count). Add or rate titles in My Library, then check again."
        }
        if status?.profileStale == true { return "MangaBaka is updating your recommendation profile. Check again shortly." }
        return "MangaBaka returned no recommendations right now. Try Refresh, or check your recommendations on the website."
    }
}
