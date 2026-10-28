import Foundation

/// The foreground library is a preference, independent of either saved login.
public enum TrackingAccount: String, CaseIterable, Identifiable, Sendable {
    case aniList = "anilist"
    case mangaBaka = "mangabaka"

    public static let storageKey = "accounts.selectedProvider"
    public var id: String { rawValue }
    public var title: String { self == .aniList ? "AniList" : "MangaBaka" }
    public var librarySection: String { self == .aniList ? "anime" : "written" }

    public static func preferred(saved: String?, librarySection: String?, connected: Set<Self>) -> Self? {
        let previous = saved.flatMap(Self.init(rawValue:))
            ?? allCases.first { $0.librarySection == librarySection }
        if let previous, connected.contains(previous) { return previous }
        return allCases.first { connected.contains($0) }
    }
}
