import SwiftUI
import AnimeCore

@MainActor
final class MangaReadingStore: ObservableObject {
    @Published private(set) var state = MangaReadingState()
    @Published private(set) var loading = true
    @Published private(set) var unreadable = false
    @Published var error: String?
    private let storage: MangaReadingStorage
    private var loadTask: Task<Void, Never>?
    init() {
        var directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MangaReading", isDirectory: true)
        #if DEBUG
        if MangaReaderPreview.active {
            let args = ProcessInfo.processInfo.arguments
            let index = args.firstIndex(of: "--ui-webtoon-session").map { $0 + 1 }
            let proposed = index.flatMap { $0 < args.count ? args[$0] : nil } ?? "default"
            let session = proposed.range(of: "^[a-zA-Z0-9-]{1,80}$", options: .regularExpression) != nil ? proposed : "default"
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("WebtoonPreview-\(session)", isDirectory: true)
        }
        #endif
        storage = MangaReadingStorage(directory: directory)
    }
    func load() async {
        guard loading else { return }
        if let loadTask { await loadTask.value; return }
        let task = Task { [weak self] in
            guard let self else { return }
            defer { loading = false; loadTask = nil }
            do { state = try await storage.load() }
            catch { unreadable = true; self.error = "Saved reading data could not be opened. Your existing data has been kept." }
        }
        loadTask = task; await task.value
    }
    func record(_ id: String) -> MangaReadingRecord? { state.record(id) }
    func save(_ title: MangaTitleReference, saved: Bool) async { await change { $0.save(title, saved: saved) } }
    func metadata(_ title: MangaTitleReference) async {
        guard state.record(title.id) != nil else { return }
        await change { $0.updateMetadata(title) }
    }
    func progress(_ title: MangaTitleReference, position: MangaReadingPosition) async {
        await change { $0.record(title, position: position) }
    }
    func mark(_ title: MangaTitleReference, chapter: SourceMangaChapter, read: Bool) async {
        await change { $0.mark(title, chapter: chapter, read: read) }
    }
    func mark(_ title: MangaTitleReference, chapters: [SourceMangaChapter], read: Bool) async {
        guard !loading, !unreadable else { return }
        let existing = Set((record(title.id)?.positions ?? []).map(\.chapterURL))
        let selected = Set(chapters.map(\.url).filter { !$0.isEmpty })
        guard existing.union(selected).count <= 10000 else {
            error = "This selection contains too many chapter records. Mark a smaller group instead."; return
        }
        await change { $0.mark(title, chapters: chapters, read: read) }
    }
    func visit(_ source: MangaSourceReference) async { await change { $0.visitSource(source.id) } }
    func pin(_ source: MangaSourceReference) async {
        await change { value in
            if value.pinnedSources.contains(source.id) { value.pinnedSources.remove(source.id) }
            else { value.pinnedSources.insert(source.id) }
        }
    }
    func preferences(_ preferences: WebtoonPreferences) async { await change { $0.preferences = preferences } }
    func clearHistory() async { await change { $0.clearHistory() } }
    func applyDeviceSync(expected: [String: Data], desired: [String: Data]) async throws {
        guard !loading, !unreadable else { throw MangaReadingStorageError.unreadable }
        let value = try await storage.update { state in
            // The actor reads its latest state, including reader saves that
            // arrived while the external file provider was downloading.
            let current = try DeviceSyncPayload.readingValues(state)
            let payload = try DeviceSyncPayload(values: DeviceSyncPayload.patch(current: current,
                expected: expected.filter { Self.isReadingKey($0.key) }, desired: desired.filter { Self.isReadingKey($0.key) }))
            let revision = state.revision; state = payload.reading; state.revision = revision
        }
        if value.revision >= state.revision { state = value }
    }
    nonisolated private static func isReadingKey(_ key: String) -> Bool { key.hasPrefix("reader.") || key.hasPrefix("book.") }
    private func change(_ mutation: @escaping @Sendable (inout MangaReadingState) -> Void) async {
        guard !unreadable else { return }
        do {
            let value = try await storage.update(mutation)
            if value.revision >= state.revision { state = value }
        } catch { self.error = "Your reading changes could not be saved. Try again." }
    }
}

enum MangaStyle {
    static let accent = Theme.accent
    static let surface = Theme.surface
}
