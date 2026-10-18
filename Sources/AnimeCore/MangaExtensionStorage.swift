import Foundation

public struct MangaExtensionState: Codable, Sendable {
    public var repositoryAdded = false
    public var installations: [InstalledMangaExtension] = []
    public init() {}
}
public struct CachedMangaCatalog: Codable, Sendable {
    public let catalog: MangaExtensionCatalog
    public let fetchedAt: Date
    public init(catalog: MangaExtensionCatalog, fetchedAt: Date = Date()) { self.catalog = catalog; self.fetchedAt = fetchedAt }
}

/// Only this actor mutates extension files. An update becomes visible after its
/// APK and state are durably written; failures retain the previous installation.
public actor MangaExtensionStorage {
    private let root: URL
    private var state: MangaExtensionState?
    public init(directory: URL) { root = directory }
    public func load() throws -> MangaExtensionState {
        if let state { return state }
        let url = root.appendingPathComponent("state.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            let value = MangaExtensionState(); state = value; return value
        }
        let data = try Data(contentsOf: url)
        guard data.count <= 4_000_000 else { throw MangaExtensionError.oversized }
        let value = try JSONDecoder().decode(MangaExtensionState.self, from: data)
        guard value.installations.count <= 64, Set(value.installations.map(\.id)).count == value.installations.count else { throw MangaExtensionError.invalidCatalog }
        for entry in value.installations { _ = try packageURL(entry) }
        state = value; return value
    }
    public func cachedCatalog() throws -> CachedMangaCatalog? {
        let path = root.appendingPathComponent("catalog.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path)
        guard data.count <= 16_000_000 else { throw MangaExtensionError.oversized }
        return try JSONDecoder().decode(CachedMangaCatalog.self, from: data)
    }
    public func saveCatalog(_ catalog: CachedMangaCatalog) throws -> MangaExtensionState {
        var updated = try load()
        try prepareDirectory()
        try JSONEncoder().encode(catalog).write(to: root.appendingPathComponent("catalog.json"), options: .atomic)
        updated.repositoryAdded = true
        return try save(updated)
    }
    public func removeRepository() throws -> MangaExtensionState {
        var updated = try load(); updated.repositoryAdded = false
        let value = try save(updated)
        try? FileManager.default.removeItem(at: root.appendingPathComponent("catalog.json"))
        return value
    }
    public func commit(_ installation: InstalledMangaExtension, apk: Data) throws -> MangaExtensionState {
        var updated = try load()
        let old = updated.installations.first { $0.id == installation.id }
        guard old != nil || updated.installations.count < 64, !apk.isEmpty, apk.count <= 32 * 1024 * 1024 else { throw MangaExtensionError.oversized }
        try prepareDirectory()
        let url = try packageURL(installation)
        try apk.write(to: url, options: .atomic)
        if let index = updated.installations.firstIndex(where: { $0.id == installation.id }) { updated.installations[index] = installation }
        else { updated.installations.append(installation) }
        do { _ = try save(updated) }
        catch {
            if old?.filename != installation.filename { try? FileManager.default.removeItem(at: url) }
            throw error
        }
        if let old, old.filename != installation.filename { try? FileManager.default.removeItem(at: packageURL(old)) }
        return updated
    }
    public func setEnabled(_ id: String, enabled: Bool) throws -> MangaExtensionState {
        var updated = try load()
        guard let index = updated.installations.firstIndex(where: { $0.id == id }) else { throw MangaExtensionError.sourceUnavailable }
        updated.installations[index].enabled = enabled; return try save(updated)
    }
    public func remove(_ id: String) throws -> MangaExtensionState {
        var updated = try load()
        guard let entry = updated.installations.first(where: { $0.id == id }) else { return updated }
        updated.installations.removeAll { $0.id == id }; let result = try save(updated)
        try? FileManager.default.removeItem(at: packageURL(entry)); return result
    }
    public func package(_ id: String) throws -> (InstalledMangaExtension, Data) {
        let value = try load()
        guard let entry = value.installations.first(where: { $0.id == id && $0.enabled }) else { throw MangaExtensionError.sourceUnavailable }
        return (entry, try Data(contentsOf: packageURL(entry), options: .mappedIfSafe))
    }
    private func packageURL(_ entry: InstalledMangaExtension) throws -> URL {
        guard let sha = entry.descriptor.sha256, sha.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw MangaExtensionError.checksumUnavailable }
        return root.appendingPathComponent(sha + ".apk")
    }
    private func prepareDirectory() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    private func save(_ value: MangaExtensionState) throws -> MangaExtensionState {
        try prepareDirectory()
        try JSONEncoder().encode(value).write(to: root.appendingPathComponent("state.json"), options: .atomic)
        state = value; return value
    }
}
