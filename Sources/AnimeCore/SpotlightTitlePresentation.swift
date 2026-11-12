import Foundation

/// Resolve the first title from cache; promote a fallback only after it leaves view.
public struct SpotlightTitlePresentation: Equatable, Sendable {
    public enum Title: Equatable, Sendable { case checkingCache, text, logo }
    private var checked = Set<Int>()
    private var prepared = Set<Int>()
    private var presented = Set<Int>()
    public init() {}
    public func title(for id: Int) -> Title {
        !checked.contains(id) ? .checkingCache : (presented.contains(id) ? .logo : .text)
    }
    public mutating func checkedCache(for id: Int, hasLogo: Bool) {
        guard checked.insert(id).inserted else { return }
        if hasLogo { prepared.insert(id); presented.insert(id) }
    }
    public mutating func preparedLogo(for id: Int, protected: Set<Int>) {
        prepared.insert(id); revealOffscreen(protected: protected)
    }
    public mutating func revealOffscreen(protected: Set<Int>) {
        presented.formUnion(prepared.subtracting(protected).intersection(checked))
    }
    public mutating func retain(_ ids: Set<Int>) {
        checked.formIntersection(ids); prepared.formIntersection(ids); presented.formIntersection(ids)
    }
    public mutating func leaveViewport() {
        presented.formUnion(prepared); checked = presented
    }
    /// The caller commits a completely decoded background/logo together while
    /// the pager is idle. It never promotes an asset during a gesture.
    public mutating func presentPrepared() { presented.formUnion(prepared.intersection(checked)) }
}
