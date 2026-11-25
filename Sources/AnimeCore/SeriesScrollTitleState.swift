import Foundation

/// A small direction threshold ignores subpixel jitter without waiting for a
/// completed gesture. Layout changes establish a baseline but do not hide it.
public struct SeriesScrollTitleState: Equatable, Sendable {
    public private(set) var isVisible = true
    private var previous: Double?
    private var travel: Double = 0
    public init() {}
    public mutating func update(offset: Double, userScrolling: Bool) {
        guard offset.isFinite else { return }
        let offset = max(0, offset)
        defer { previous = offset }
        guard let previous, userScrolling else { travel = 0; return }
        if offset <= 1 { isVisible = true; travel = 0; return }
        let delta = offset - previous
        guard delta != 0 else { return }
        if (travel > 0 && delta < 0) || (travel < 0 && delta > 0) { travel = 0 }
        travel += delta
        if travel >= 3 { isVisible = false; travel = 0 }
        else if travel <= -3 { isVisible = true; travel = 0 }
    }
}
