import Foundation

/// The account owns its weekly result and request. Library edits, scrolling and
/// content filters do not invalidate it; only expiry or an explicit refresh do.
public struct MangaBakaRecommendationsState: Sendable {
    public struct Attempt: Equatable, Sendable {
        let account: UUID
        private let id = UUID()
    }
    public private(set) var items: [MangaBakaSeries] = []
    public private(set) var loading = false
    public private(set) var error: String?
    public private(set) var hasResult = false
    public private(set) var receivedCount = 0
    public private(set) var unverifiedCount = 0
    public private(set) var status: MangaBakaRecommendationStatus?
    public private(set) var fetchedAt: Date?
    public var refreshAt: Date? { fetchedAt?.addingTimeInterval(MangaBakaRecommendationSnapshot.lifetime) }
    private var records: [MangaBakaSeries] = []
    private var retryAfter = Date.distantPast
    private var account: UUID?
    private var contentFilter = MangaBakaContentFilter()
    private var attempt: Attempt?

    public init() {}

    public mutating func begin(account: UUID, includeAdult: Bool, refresh: Bool = false, now: Date = Date()) -> Attempt? {
        begin(account: account, contentFilter: .legacy(includeAdult: includeAdult), refresh: refresh, now: now)
    }
    public mutating func begin(account: UUID, contentFilter: MangaBakaContentFilter, refresh: Bool = false, now: Date = Date()) -> Attempt? {
        if self.account != account { reset(); self.account = account }
        self.contentFilter = contentFilter
        applyFilter()
        guard attempt == nil else { return nil }
        guard refresh || (now >= (refreshAt ?? .distantPast) && now >= retryAfter) else { return nil }
        let next = Attempt(account: account)
        attempt = next; loading = true; error = nil
        return next
    }

    public func isCurrent(_ requested: Attempt) -> Bool { attempt == requested }

    @discardableResult
    public mutating func restore(_ snapshot: MangaBakaRecommendationSnapshot, account: UUID,
        includeAdult: Bool, now: Date = Date()) throws -> Bool {
        try restore(snapshot, account: account, contentFilter: .legacy(includeAdult: includeAdult), now: now)
    }
    @discardableResult
    public mutating func restore(_ snapshot: MangaBakaRecommendationSnapshot, account: UUID,
        contentFilter: MangaBakaContentFilter, now: Date = Date()) throws -> Bool {
        guard attempt == nil, !hasResult, snapshot.fetchedAt <= now.addingTimeInterval(60) else { return false }
        let values = try snapshot.payload.records()
        self.account = account; self.contentFilter = contentFilter
        receive(values, status: snapshot.status, at: snapshot.fetchedAt)
        return true
    }

    @discardableResult
    public mutating func complete(_ records: [MangaBakaSeries], for requested: Attempt,
        status: MangaBakaRecommendationStatus? = nil, now: Date = Date()) -> Bool {
        guard isCurrent(requested) else { return false }
        receive(records, status: status, at: now)
        return true
    }

    private mutating func receive(_ values: [MangaBakaSeries], status: MangaBakaRecommendationStatus?, at date: Date) {
        var seen = Set<Int>()
        records = values.filter { seen.insert($0.id).inserted }
        receivedCount = records.count
        unverifiedCount = records.filter { MangaBakaContentRating(rawValue: $0.contentRating ?? "") == nil }.count
        self.status = status; hasResult = true; fetchedAt = date; retryAfter = .distantPast
        applyFilter()
    }

    private mutating func applyFilter() { items = records.filter { $0.isVisible(contentFilter: contentFilter) } }

    public mutating func fail(_ message: String, for requested: Attempt, now: Date = Date()) {
        if isCurrent(requested) {
            error = message
            // Failed weekly loads keep the saved timestamp and cards. Avoid a
            // request storm on repeated appearances; Refresh bypasses the delay.
            retryAfter = now.addingTimeInterval(300)
        }
    }

    public mutating func finish(_ requested: Attempt) {
        if isCurrent(requested) { loading = false; attempt = nil }
    }

    public mutating func reset() { self = Self() }

    public var emptyMessage: String {
        if !hasResult { return "Recommendations haven’t loaded yet. Tap Refresh to try again." }
        if unverifiedCount > 0 { return "Some recommended series are missing content details. Tap Refresh to try loading them again." }
        if receivedCount > 0 { return "No recommended titles match your current content settings. Refresh to request a new selection." }
        if status?.coldStart == true {
            let count = status?.libraryCount.map { " (\($0.formatted()) titles in your MangaBaka library)" } ?? ""
            return "MangaBaka is still building your recommendation profile\(count). Add or rate titles in My Library, then tap Refresh."
        }
        if status?.profileStale == true { return "MangaBaka is updating your recommendation profile. Tap Refresh to check again." }
        return "MangaBaka returned no recommendations right now. Try Refresh, or check your recommendations on the website."
    }
}
