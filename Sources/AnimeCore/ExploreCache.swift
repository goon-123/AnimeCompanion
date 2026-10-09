import Foundation

/// Only public discovery metadata is stored here; account and playback data are excluded.
public struct ExploreSnapshot: Codable, Sendable {
    public let response: ExploreResponse
    public let savedAt: Date
    public let season: AnimeSeason
    public let year: Int
    public let version: Int
    public let includesAdult: Bool?

    public init(response: ExploreResponse, selection: SeasonSelection, savedAt: Date = Date(), includeAdult: Bool = false) {
        self.response = response; self.savedAt = savedAt
        season = selection.season; year = selection.year; version = 1
        includesAdult = includeAdult
    }
    public func needsRefresh(at now: Date = Date()) -> Bool { now.timeIntervalSince(savedAt) >= 300 }
    public func isUsable(for selection: SeasonSelection, at now: Date = Date(), includeAdult: Bool = false) -> Bool {
        let age = now.timeIntervalSince(savedAt)
        return version == 1 && season == selection.season && year == selection.year &&
            (includesAdult ?? false) == includeAdult && age >= -300 && age < 7 * 86400
    }
}

/// Disk I/O stays off the main actor. A failed or corrupt cache never prevents live browsing.
public actor ExploreCache {
    public static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AnimeCompanion-Explore", isDirectory: true)
    }
    private let directory: URL?
    private var memory: [String: ExploreSnapshot] = [:]
    public init(directory: URL? = ExploreCache.defaultDirectory) { self.directory = directory }

    public func load(_ selection: SeasonSelection, now: Date = Date(), includeAdult: Bool = false) -> ExploreSnapshot? {
        let key = key(for: selection, includeAdult: includeAdult)
        if let snapshot = memory[key], snapshot.isUsable(for: selection, at: now, includeAdult: includeAdult) { return snapshot }
        guard let file = directory?.appendingPathComponent(key),
              let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4 * 1024 * 1024,
              let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(ExploreSnapshot.self, from: data),
              snapshot.isUsable(for: selection, at: now, includeAdult: includeAdult) else { return nil }
        remember(snapshot, key: key)
        return snapshot
    }
    @discardableResult
    public func save(_ snapshot: ExploreSnapshot) -> Bool {
        let selection = SeasonSelection(season: snapshot.season, year: snapshot.year)
        let key = key(for: selection, includeAdult: snapshot.includesAdult ?? false)
        remember(snapshot, key: key)
        guard let directory else { return false }
        do {
            let data = try JSONEncoder().encode(snapshot)
            guard data.count <= 4 * 1024 * 1024 else { return false }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(key), options: .atomic)
            let files = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey]).filter { $0.lastPathComponent.hasPrefix("explore-v1-") && $0.pathExtension == "json" }
            let newest = files.sorted {
                ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >
                ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }
            for old in newest.dropFirst(6) { try? FileManager.default.removeItem(at: old) }
            return true
        } catch { return false }
    }
    private func remember(_ snapshot: ExploreSnapshot, key: String) {
        memory[key] = snapshot
        if memory.count > 6, let oldest = memory.min(by: { $0.value.savedAt < $1.value.savedAt })?.key {
            memory.removeValue(forKey: oldest)
        }
    }
    private func key(for selection: SeasonSelection, includeAdult: Bool) -> String {
        "explore-v1-\(selection.year)-\(selection.season.rawValue)\(includeAdult ? "-adult" : "").json"
    }
}
