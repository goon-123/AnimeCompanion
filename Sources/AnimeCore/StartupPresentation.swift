import Foundation

/// A cached launch can finish quickly; unavailable services cannot hold the logo
/// indefinitely. Use a monotonic elapsed duration rather than wall-clock time.
public enum StartupPresentation {
    public static let minimumDuration: TimeInterval = 0.45
    public static let maximumDuration: TimeInterval = 2
    public static func shouldReveal(elapsed: TimeInterval, localReady: Bool, contentReady: Bool) -> Bool {
        elapsed >= maximumDuration - 0.3 || (elapsed >= minimumDuration && localReady && contentReady)
    }
}
