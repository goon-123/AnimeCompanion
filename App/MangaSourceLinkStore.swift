import SwiftUI
import AnimeCore

@MainActor
final class MangaSourceLinkStore: ObservableObject {
    @Published private(set) var state = MangaSourceLinkState()
    @Published private(set) var loading = true
    @Published private(set) var unreadable = false
    @Published private(set) var error: String?
    private let storage: MangaSourceLinkStorage
    private var loadTask: Task<Void, Never>?
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MangaReading", isDirectory: true)
        storage = MangaSourceLinkStorage(directory: directory)
    }
    func link(for target: MangaSourceLinkTarget) -> MangaSourceLink? { state.links[target.id] }
    func load() async {
        guard loading else { return }
        if let loadTask { await loadTask.value; return }
        let task = Task { [weak self] in
            guard let self else { return }
            defer { loading = false; loadTask = nil }
            do { apply(try await storage.load()) }
            catch { unreadable = true; self.error = error.localizedDescription }
        }
        loadTask = task; await task.value
    }
    @discardableResult
    func setSource(_ title: MangaTitleReference?, for target: MangaSourceLinkTarget) async -> Bool {
        await load()
        guard !unreadable else { return false }
        error = nil
        do { apply(try await storage.setSource(title, for: target)); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    private func apply(_ value: MangaSourceLinkState) {
        if value.revision >= state.revision { state = value }
    }
}

extension MangaBakaStore {
    func sourceLinkTarget(for series: MangaBakaSeries) -> MangaSourceLinkTarget? {
        guard connected, let accountID = profile?.id else { return nil }
        return MangaSourceLinkTarget(accountID: accountID, seriesID: series.id,
                                     title: series.displayTitle, searchTitles: series.searchTitles)
    }
}
