import Foundation

/// Two visually identical boundary pages let the native pager settle normally.
/// Rebase only when idle, without animation, onto the same prepared title.
public struct SpotlightLoop: Sendable {
    public let count: Int
    public init(count: Int) { self.count = max(0, count) }
    public var slots: [Int] { count > 1 ? Array(-1...count) : (count == 1 ? [0] : []) }
    public func index(for slot: Int?) -> Int? {
        guard count > 0, let slot, slots.contains(slot) else { return nil }
        return (slot % count + count) % count
    }
    public func rebase(_ slot: Int?) -> Int? {
        guard count > 1, let slot else { return nil }
        return slot == -1 ? count - 1 : (slot == count ? 0 : nil)
    }
    public func neighbors(of index: Int) -> [Int] {
        guard count > 0 else { return [] }
        var seen = Set<Int>()
        return [index, index + 1, index - 1].map { ($0 % count + count) % count }.filter { seen.insert($0).inserted }
    }
}
