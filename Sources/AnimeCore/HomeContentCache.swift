import Foundation

public struct HomeContentSnapshot<Value: Codable & Sendable>: Codable, Sendable {
    public let value: Value
    public let savedAt: Date
    private let version: Int
    public init(_ value: Value, savedAt: Date = Date()) { self.value = value; self.savedAt = savedAt; version = 1 }
    public func needsRefresh(at now: Date = Date()) -> Bool { now.timeIntervalSince(savedAt) >= 300 }
    public func isUsable(at now: Date = Date()) -> Bool {
        version == 1 && now.timeIntervalSince(savedAt) >= -300 && now.timeIntervalSince(savedAt) < 7 * 86400
    }
}

/// Bounded public Home metadata only. Account snapshots use a separate encrypted store.
public actor HomeContentCache {
    public static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("AnimeCompanion-Home", isDirectory: true)
    }
    private let directory: URL?
    private var memory = BoundedCache<String, Data>(maximumCount: 16, maximumCost: 16_000_000)
    public init(directory: URL? = HomeContentCache.defaultDirectory) { self.directory = directory }
    private func file(_ key: String) -> URL? {
        guard !key.isEmpty, key.count <= 120, key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        return directory?.appendingPathComponent(key + ".json")
    }
    public func load<Value>(_ type: Value.Type, key: String, now: Date = Date()) -> HomeContentSnapshot<Value>? where Value: Codable & Sendable {
        let data: Data
        if let cached = memory.value(for: key) { data = cached }
        else {
            guard let file = file(key), let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 4_000_000, let bytes = try? Data(contentsOf: file) else { return nil }
            data = bytes
        }
        guard let snapshot = try? JSONDecoder().decode(HomeContentSnapshot<Value>.self, from: data), snapshot.isUsable(at: now) else { return nil }
        memory.insert(data, for: key, cost: data.count, expiresAt: now.addingTimeInterval(300))
        return snapshot
    }
    @discardableResult public func save<Value>(_ snapshot: HomeContentSnapshot<Value>, key: String) -> Bool where Value: Codable & Sendable {
        guard let data = try? JSONEncoder().encode(snapshot), data.count <= 4_000_000 else { return false }
        memory.insert(data, for: key, cost: data.count, expiresAt: Date().addingTimeInterval(300))
        guard let file = file(key), let directory else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.pathExtension == "json" }.sorted {
                    ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >
                    ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                }
            for old in files.dropFirst(16) { try? FileManager.default.removeItem(at: old) }
            return true
        } catch { return false }
    }
}

/// All seasonal Home widgets share one request, including when they appear together.
public actor HomeCatalogClient {
    private let api: AniListClient
    public let cache: HomeContentCache
    private let requests = RequestCoalescer<String, HomeContentSnapshot<[Anime]>>()
    public init(api: AniListClient, cache: HomeContentCache = HomeContentCache()) { self.api = api; self.cache = cache }
    private func key(_ selection: SeasonSelection, adult: Bool) -> String { "season-v1-\(selection.year)-\(selection.season.rawValue)-\(adult)" }
    public func cached(_ selection: SeasonSelection, includeAdult: Bool) async -> HomeContentSnapshot<[Anime]>? {
        await cache.load([Anime].self, key: key(selection, adult: includeAdult))
    }
    public func season(_ selection: SeasonSelection, includeAdult: Bool, refresh: Bool = false) async throws -> HomeContentSnapshot<[Anime]> {
        if !refresh, let saved = await cached(selection, includeAdult: includeAdult), !saved.needsRefresh() { return saved }
        let key = key(selection, adult: includeAdult)
        return try await requests.value(for: key) {
            let page = try await self.api.homeSeason(selection, includeAdult: includeAdult, refresh: refresh)
            let snapshot = HomeContentSnapshot(page.media ?? [])
            await self.cache.save(snapshot, key: key)
            return snapshot
        }
    }
}

public actor HomeCommunityClient {
    private let api: AniListClient
    private let cache: HomeContentCache
    private let requests = RequestCoalescer<String, HomeContentSnapshot<CommunityThreadPage>>()
    private let key = "community-general-v1"
    public init(api: AniListClient, cache: HomeContentCache = HomeContentCache()) { self.api = api; self.cache = cache }
    public func cached() async -> HomeContentSnapshot<CommunityThreadPage>? { await cache.load(CommunityThreadPage.self, key: key) }
    public func feed(refresh: Bool = false) async throws -> HomeContentSnapshot<CommunityThreadPage> {
        if !refresh, let saved = await cached(), !saved.needsRefresh() { return saved }
        return try await requests.value(for: key) {
            // Disk age controls refresh; an expired snapshot must also bypass the public memory cache.
            let page = try await self.api.communityThreads(refresh: true)
            let result = HomeContentSnapshot(page)
            await self.cache.save(result, key: self.key)
            return result
        }
    }
}
