import SwiftUI
import AnimeCore

@MainActor
final class MangaReadingStore: ObservableObject {
    @Published private(set) var state = MangaReadingState()
    @Published private(set) var loading = true
    @Published private(set) var unreadable = false
    @Published var error: String?
    private let storage: MangaReadingStorage
    private var loaded = false
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
        guard !loaded else { return }; loaded = true
        do { state = try await storage.load() }
        catch { unreadable = true; self.error = "Saved reading data could not be opened. Your existing data has been kept." }
        loading = false
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
    func visit(_ source: MangaSourceReference) async { await change { $0.visitSource(source.id) } }
    func pin(_ source: MangaSourceReference) async {
        await change { value in
            if value.pinnedSources.contains(source.id) { value.pinnedSources.remove(source.id) }
            else { value.pinnedSources.insert(source.id) }
        }
    }
    func preferences(_ preferences: WebtoonPreferences) async { await change { $0.preferences = preferences } }
    func clearHistory() async { await change { $0.clearHistory() } }
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
