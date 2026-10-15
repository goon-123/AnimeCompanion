import Foundation

/// An in-memory LRU cache with hard entry/cost limits. The owning actor supplies isolation.
public struct BoundedCache<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    private struct Entry: Sendable {
        let value: Value
        let expiresAt: Date
        let cost: Int
        var lastUse: UInt64
    }
    private let maximumCount: Int
    private let maximumCost: Int
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0
    public private(set) var totalCost = 0
    public var count: Int { entries.count }

    public init(maximumCount: Int, maximumCost: Int) {
        self.maximumCount = max(0, maximumCount)
        self.maximumCost = max(0, maximumCost)
    }
    public mutating func value(for key: Key, now: Date = Date()) -> Value? {
        guard var entry = entries[key] else { return nil }
        guard entry.expiresAt > now else { remove(key); return nil }
        clock &+= 1; entry.lastUse = clock; entries[key] = entry
        return entry.value
    }
    public mutating func insert(_ value: Value, for key: Key, cost: Int, expiresAt: Date, now: Date = Date()) {
        remove(key)
        guard maximumCount > 0, cost >= 0, cost <= maximumCost, expiresAt > now else { return }
        for key in Array(entries.keys) where entries[key]!.expiresAt <= now { remove(key) }
        // Subtract before comparing to avoid overflowing when a caller supplies a large cost.
        while entries.count >= maximumCount || totalCost > maximumCost - cost {
            guard let oldest = entries.min(by: { $0.value.lastUse < $1.value.lastUse })?.key else { break }
            remove(oldest)
        }
        clock &+= 1
        entries[key] = Entry(value: value, expiresAt: expiresAt, cost: cost, lastUse: clock)
        totalCost += cost
    }
    public mutating func remove(_ key: Key) {
        if let old = entries.removeValue(forKey: key) { totalCost -= old.cost }
    }
    public mutating func remove(where predicate: (Key) -> Bool) {
        for key in Array(entries.keys) where predicate(key) { remove(key) }
    }
    public mutating func removeAll() { entries.removeAll(); totalCost = 0 }
}
