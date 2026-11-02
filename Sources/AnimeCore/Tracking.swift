import Foundation

public struct TrackingEdit: Equatable, Sendable {
    public var progress: Int
    public var status: LibraryStatus
    /// Canonical 100-point score; omitted unless the user edits their score.
    public var scoreRaw: Int?
    public var notes: String?
    public var repeatCount: Int?
    public init(progress: Int, status: LibraryStatus, scoreRaw: Int? = nil, notes: String? = nil, repeatCount: Int? = nil) {
        self.progress = progress; self.status = status; self.scoreRaw = scoreRaw
        self.notes = notes; self.repeatCount = repeatCount
    }
    public func validated(total: Int?) throws -> Self {
        guard progress >= 0, progress <= 100_000,
              total.map({ $0 <= 0 || progress <= $0 }) ?? true else {
            throw ServiceError.message("Enter an episode number within this anime’s AniList episode total.")
        }
        guard scoreRaw.map({ (0...100).contains($0) }) ?? true,
              repeatCount.map({ (0...10_000).contains($0) }) ?? true,
              notes.map({ $0.count <= 6000 }) ?? true else {
            throw ServiceError.message("Check your score, rewatch count, or notes (maximum 6,000 characters).")
        }
        var result = self
        if status == .completed, let total, total > 0 { result.progress = total }
        return result
    }
    public static func next(entry: LibraryEntry?, total: Int?, automaticallyComplete: Bool) -> Self {
        let oldProgress = entry?.progressValue ?? 0
        let progress = LibraryEntry.clampedProgress(oldProgress + 1, total: total)
        var status: LibraryStatus = entry?.status == .rewatching ? .rewatching : .watching
        var repeats: Int?
        if automaticallyComplete, let total, total > 0, progress == total, oldProgress < total {
            status = .completed
            if entry?.status == .rewatching { repeats = (entry?.repeatCount ?? 0) + 1 }
        }
        return Self(progress: progress, status: status, repeatCount: repeats)
    }
    /// AniList stores cumulative progress. Marking a row watched means watched
    /// through that episode; it never moves confirmed progress backwards.
    public static func watched(through episode: Int, entry: LibraryEntry?, total: Int?, automaticallyComplete: Bool) throws -> Self {
        guard (1...100_000).contains(episode), total.map({ $0 <= 0 || episode <= $0 }) ?? true else {
            throw ServiceError.message("Choose an episode within this anime's episode total.")
        }
        let old = entry?.progressValue ?? 0
        guard episode > old else { return Self(progress: old, status: entry?.status ?? .watching) }
        var status: LibraryStatus = entry?.status == .rewatching ? .rewatching : .watching
        var repeats: Int?
        if automaticallyComplete, let total, total > 0, episode == total {
            status = .completed
            if entry?.status == .rewatching { repeats = min(9_999, max(0, entry?.repeatCount ?? 0)) + 1 }
        }
        return Self(progress: episode, status: status, repeatCount: repeats)
    }
    /// AniList has a single watched-through number, not independent episode
    /// flags. Unwatching N resets progress to N-1, also unwatching later rows.
    public static func unwatched(from episode: Int, entry: LibraryEntry?, total: Int?) throws -> Self {
        guard (1...100_000).contains(episode), total.map({ $0 <= 0 || episode <= $0 }) ?? true else {
            throw ServiceError.message("Choose an episode within this anime's episode total.")
        }
        guard let entry, episode <= entry.progressValue else {
            throw ServiceError.message("This episode is no longer marked watched.")
        }
        let status = entry.status == .completed ? LibraryStatus.watching : (entry.status ?? .watching)
        return Self(progress: episode - 1, status: status)
    }
}

extension LibraryEntry {
    /// Metadata refreshes may change broadcast dates without changing the user's confirmed tracking.
    public func hasSameTracking(as other: LibraryEntry) -> Bool {
        id == other.id && mediaId == other.mediaId && progressValue == other.progressValue && status == other.status
            && (score ?? 0) == (other.score ?? 0) && (notes ?? "") == (other.notes ?? "")
            && (repeatCount ?? 0) == (other.repeatCount ?? 0)
    }
}
