import Foundation

public enum AnimeEpisodeFilter: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case all, unwatched, watched
    public static let storageKey = "episodes.defaultFilter.v1"
    public static func defaultValue(saved: String) -> Self { Self(rawValue: saved) ?? .unwatched }
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public func includes(episode: Int, watchedThrough: Int) -> Bool {
        switch self {
        case .all: return true
        case .unwatched: return episode > watchedThrough
        case .watched: return episode <= watchedThrough
        }
    }
}
