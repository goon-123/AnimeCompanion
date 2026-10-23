import Foundation

/// Keeps fractional motion when a scroll view rounds its position to pixels.
public struct WebtoonScrollMotion {
    private var previousTime: Double?
    private var target: Double?
    public init() {}
    public mutating func reset() { previousTime = nil; target = nil }
    public mutating func next(timestamp: Double, offset: Double, speed: Double, maximum: Double) -> Double {
        let elapsed = previousTime.map { min(0.25, max(0, timestamp - $0)) } ?? 0
        previousTime = timestamp
        if target == nil || abs((target ?? offset) - offset) > 1 { target = offset }
        let next = min(maximum, max(0, (target ?? offset) + elapsed * speed))
        target = next
        return next
    }
}
