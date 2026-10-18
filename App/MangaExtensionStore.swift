import SwiftUI
import CryptoKit
import AnimeCore

@MainActor
final class MangaExtensionStore: ObservableObject {
    @Published private(set) var state = MangaExtensionState()
    @Published private(set) var catalog: MangaExtensionCatalog?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var refreshing = false
    @Published private(set) var installing: String?
    @Published private(set) var loading = true
    @Published private(set) var unreadableState = false
    @Published var error: String?
    private let client = MangaRepositoryClient()
    private let storage: MangaExtensionStorage
    private var loaded = false
    init() {
        var directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MangaExtensions", isDirectory: true)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-manga-extensions") {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("manga-ui-\(UUID().uuidString)", isDirectory: true)
        }
        #endif
        storage = MangaExtensionStorage(directory: directory)
    }
    var busy: Bool { loading || refreshing || installing != nil || unreadableState }
    func installed(_ id: String) -> InstalledMangaExtension? { state.installations.first { $0.id == id } }
    func update(for entry: InstalledMangaExtension) -> MangaExtensionDescriptor? {
        catalog?.extensions.first { $0.id == entry.id && $0.versionCode > entry.descriptor.versionCode }
    }
    func load() async {
        guard !loaded else { return }; loaded = true
        do {
            state = try await storage.load()
            if state.repositoryAdded, let cached = try? await storage.cachedCatalog() {
                catalog = cached.catalog; lastRefresh = cached.fetchedAt
            }
        } catch {
            unreadableState = true
            self.error = "Saved manga extensions could not be read. Existing files have been kept. Reopen the app before changing them."
        }
        loading = false
        if state.repositoryAdded && !unreadableState && Date().timeIntervalSince(lastRefresh ?? .distantPast) > 6 * 3600 { await refresh() }
    }
    func refresh(link: String = "https://keiyoushi.github.io") async {
        guard !refreshing, installing == nil, !unreadableState else { return }
        refreshing = true; error = nil
        defer { refreshing = false }
        do {
            let repository = try MangaRepository(link)
            let value = try await client.catalog(repository: repository)
            try Task.checkCancellation()
            let cached = CachedMangaCatalog(catalog: value)
            state = try await storage.saveCatalog(cached)
            catalog = value; lastRefresh = cached.fetchedAt
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    func install(_ entry: MangaExtensionDescriptor) async {
        guard !busy else { return }
        installing = entry.id; error = nil
        defer { installing = nil }
        do {
            let apk = try await client.package(entry)
            try verify(apk, descriptor: entry)
            let inspection = try await MangaRuntime.inspect(apk, modern: entry.modernAPI)
            try Task.checkCancellation()
            let installation = try InstalledMangaExtension(descriptor: entry, inspection: inspection, enabled: installed(entry.id)?.enabled ?? true)
            state = try await storage.commit(installation, apk: apk)
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    func setEnabled(_ id: String, _ enabled: Bool) async {
        guard !busy else { return }
        do { state = try await storage.setEnabled(id, enabled: enabled) } catch { self.error = error.localizedDescription }
    }
    func remove(_ id: String) async {
        guard !busy else { return }
        do { state = try await storage.remove(id) } catch { self.error = error.localizedDescription }
    }
    func removeRepository() async {
        guard !busy else { return }
        do { state = try await storage.removeRepository(); catalog = nil; lastRefresh = nil } catch { self.error = error.localizedDescription }
    }
    func browse(extensionID: String, sourceID: String, mode: String, query: String, page: Int) async throws -> SourceMangaPage {
        let (entry, apk) = try await storage.package(extensionID)
        guard let source = entry.sources.first(where: { $0.id == sourceID }) else { throw MangaExtensionError.sourceUnavailable }
        try verify(apk, descriptor: entry.descriptor)
        return try await MangaRuntime.browse(apk, source: source, modern: entry.descriptor.modernAPI, mode: mode, query: query, page: page)
    }
    private func verify(_ data: Data, descriptor: MangaExtensionDescriptor) throws {
        guard let expected = descriptor.sha256 else { throw MangaExtensionError.checksumUnavailable }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw MangaExtensionError.checksumMismatch }
    }
}
