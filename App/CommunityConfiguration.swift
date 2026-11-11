import Foundation
import AnimeCore

enum CommunityConfiguration {
    static let offsetKey = "community.episodeOffsets.v1"
    static func offset(source: CommunitySource, animeID: Int, saved: String) -> Int {
        guard let data = saved.data(using: .utf8), let values = try? JSONDecoder().decode([String: Int].self, from: data) else { return 0 }
        return min(100_000, max(-100_000, values["\(source.rawValue)-\(animeID)"] ?? 0))
    }
    static func updatingOffset(_ offset: Int, source: CommunitySource, animeID: Int, saved: String) -> String {
        var values = saved.data(using: .utf8).flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]
        values["\(source.rawValue)-\(animeID)"] = offset == 0 ? nil : min(100_000, max(-100_000, offset))
        return (try? JSONEncoder().encode(values)).flatMap { String(data: $0, encoding: .utf8) } ?? saved
    }
}
