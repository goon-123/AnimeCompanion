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
}
