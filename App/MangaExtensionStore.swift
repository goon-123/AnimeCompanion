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
    @Published private var settingsVersions: [String: String] = [:]
    @Published var error: String?
    private let client = MangaRepositoryClient()
    private let storage: MangaExtensionStorage
    private let settingsVault = MangaSourceSettingsVault()
    private var settingsCache: [String: MangaSourceSettings] = [:]
    private var writingSettings = false
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
    var busy: Bool { loading || refreshing || installing != nil || unreadableState || writingSettings }
    func installed(_ id: String) -> InstalledMangaExtension? { state.installations.first { $0.id == id } }
    func update(for entry: InstalledMangaExtension) -> MangaExtensionDescriptor? {
        catalog?.extensions.first { $0.id == entry.id && $0.versionCode > entry.descriptor.versionCode }
    }
    func load() async {
        guard !loaded else { return }; loaded = true
        #if DEBUG
        if MangaReaderPreview.active { state = MangaReaderPreview.extensionState; loading = false; return }
        #endif
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
        #if DEBUG
        if MangaReaderPreview.owns(extensionID) { return MangaReaderPreview.browse(query: query, page: page) }
        #endif
        let (entry, apk) = try await storage.package(extensionID)
        guard let source = entry.sources.first(where: { $0.id == sourceID }) else { throw MangaExtensionError.sourceUnavailable }
        try verify(apk, descriptor: entry.descriptor)
        let reference = MangaSourceReference(installation: entry, source: source)
        let settings = try await sourceConfiguration(reference)
        return try await MangaRuntime.browse(apk, source: source, modern: entry.descriptor.modernAPI, mode: mode, query: query, page: page, settings: settings)
    }
    func book(_ title: MangaTitleReference) async throws -> MangaBook {
        #if DEBUG
        if MangaReaderPreview.owns(title.source.extensionID) { return MangaReaderPreview.book(title.manga) }
        #endif
        let (entry, source, apk) = try await context(title.source)
        let settings = try await sourceConfiguration(title.source)
        return try await MangaRuntime.book(apk, source: source, modern: entry.descriptor.modernAPI, manga: title.manga, settings: settings)
    }
    func pages(_ source: MangaSourceReference, chapter: SourceMangaChapter) async throws -> [SourceMangaImage] {
        #if DEBUG
        if MangaReaderPreview.owns(source.extensionID) { return MangaReaderPreview.pages(chapter) }
        #endif
        let (entry, runtimeSource, apk) = try await context(source)
        let settings = try await sourceConfiguration(source)
        return try await MangaRuntime.pages(apk, source: runtimeSource, modern: entry.descriptor.modernAPI, chapter: chapter, settings: settings)
    }
    func imageData(_ source: MangaSourceReference, image: SourceMangaImage) async throws -> Data {
        #if DEBUG
        if MangaReaderPreview.owns(source.extensionID) { return try MangaReaderPreview.image(image) }
        #endif
        let (entry, runtimeSource, apk) = try await context(source)
        let settings = try await sourceConfiguration(source)
        return try await MangaRuntime.image(apk, source: runtimeSource, modern: entry.descriptor.modernAPI, image: image, settings: settings)
    }
    func imageVersion(_ source: MangaSourceReference) -> String {
        (installed(source.extensionID)?.descriptor.sha256 ?? "unavailable") + ":" + (settingsVersions[source.id] ?? "unloaded")
    }
    func sourceConfiguration(_ source: MangaSourceReference) async throws -> MangaSourceSettings {
        if let value = settingsCache[source.id] { return value }
        #if DEBUG
        if MangaReaderPreview.owns(source.extensionID) {
            let value = try MangaReaderPreview.loadSourceSettings()
            try cacheSettings(value, source: source)
            return value
        }
        #endif
        let value = try await settingsVault.load(source.id)
        if let cached = settingsCache[source.id] { return cached }
        try cacheSettings(value, source: source)
        return value
    }
    func sourceSettings(_ source: MangaSourceReference) async throws -> MangaSourceSettingsSchema {
        #if DEBUG
        if MangaReaderPreview.owns(source.extensionID) { return MangaReaderPreview.sourceSettings }
        #endif
        let (entry, runtimeSource, apk) = try await context(source)
        let settings = try await sourceConfiguration(source)
        let schema = try await MangaRuntime.sourceSettings(apk, source: runtimeSource, modern: entry.descriptor.modernAPI, settings: settings)
        guard schema.sourceID == source.sourceID else { throw MangaExtensionError.invalidSourceSettings }
        return schema
    }
    func saveSourceSettings(_ settings: MangaSourceSettings, source: MangaSourceReference, expectedVersion: String) async throws {
        guard !busy else { throw ServiceError.message("This extension is busy. Try saving source settings again in a moment.") }
        writingSettings = true
        defer { writingSettings = false }
        guard installed(source.extensionID)?.descriptor.sha256 == expectedVersion else {
            throw ServiceError.message("This extension changed while settings were open. Reopen source settings and try again.")
        }
        _ = try await sourceConfiguration(source)
        _ = try settings.encoded()
        #if DEBUG
        if MangaReaderPreview.owns(source.extensionID) {
            try MangaReaderPreview.saveSourceSettings(settings)
            try cacheSettings(settings, source: source)
            return
        }
        #endif
        try await settingsVault.save(settings, sourceID: source.id)
        try cacheSettings(settings, source: source)
    }
    private func cacheSettings(_ settings: MangaSourceSettings, source: MangaSourceReference) throws {
        let data = try settings.encoded()
        settingsCache[source.id] = settings
        settingsVersions[source.id] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func context(_ source: MangaSourceReference) async throws -> (InstalledMangaExtension, MangaRuntimeSource, Data) {
        let (entry, apk) = try await storage.package(source.extensionID)
        guard let runtimeSource = entry.sources.first(where: { $0.id == source.sourceID }) else { throw MangaExtensionError.sourceUnavailable }
        try verify(apk, descriptor: entry.descriptor)
        return (entry, runtimeSource, apk)
    }
    private func verify(_ data: Data, descriptor: MangaExtensionDescriptor) throws {
        guard let expected = descriptor.sha256 else { throw MangaExtensionError.checksumUnavailable }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw MangaExtensionError.checksumMismatch }
    }
}
