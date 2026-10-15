import Foundation

/// Bound each scan to protect provider limits; the user can always request the next batch.
public enum DiscoveryScanPolicy {
    public static let maximumAdditionalPages = 5
    public static let targetMatches = 12
    public static func shouldContinue(matches: Int, hasMore: Bool, pagesScanned: Int, target: Int = targetMatches) -> Bool {
        hasMore && matches < target && pagesScanned < maximumAdditionalPages
    }
}

public enum DiscoveryCoverage: Equatable, Sendable {
    case loading, checkingDubs, unavailableDubs, searching, partial, complete

    public init(loaded: Bool, loading: Bool, scanning: Bool, hasMore: Bool,
                requiresDubs: Bool, dubsLoaded: Bool, dubsUnavailable: Bool) {
        if !loaded || loading { self = .loading }
        else if requiresDubs && !dubsLoaded { self = .checkingDubs }
        else if requiresDubs && dubsUnavailable { self = .unavailableDubs }
        else if scanning { self = .searching }
        else { self = hasMore ? .partial : .complete }
    }
    public var emptyTitle: String? {
        switch self {
        case .partial: return "No matches yet"
        case .complete: return "No matching titles"
        default: return nil
        }
    }
    public var emptyMessage: String? {
        switch self {
        case .partial: return "More titles are available. Keep searching or adjust your filters."
        case .complete: return "All titles for this search have been checked. Try changing the search or filters."
        default: return nil
        }
    }
}
