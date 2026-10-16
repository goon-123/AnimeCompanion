import Foundation

/// Uses the scroll view's measured content, including lazy rows and its footer.
public enum DiscoveryPaginationPolicy {
    public static func isNearEnd(offset: Double, viewport: Double, content: Double, bottomInset: Double = 0) -> Bool {
        guard offset.isFinite, viewport.isFinite, content.isFinite, bottomInset.isFinite,
              viewport > 0, content > 0 else { return false }
        return offset + viewport >= content + max(0, bottomInset) - 400
    }
    /// An empty local-filter batch must not drain the whole catalog automatically.
    public static func shouldPause(previousMatches: Int, currentMatches: Int) -> Bool {
        currentMatches <= previousMatches
    }
}
