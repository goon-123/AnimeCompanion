import SwiftUI
import AnimeCore

@MainActor
final class ExploreCatalogModel: ObservableObject {
    @Published private(set) var state = ExploreCatalogState()

    func load(selection: SeasonSelection, includeAdult: Bool, api: AniListClient, cache: ExploreCache, refresh: Bool) async {
        guard !Task.isCancelled else { return }
        let needsRestore = state.loadedKey?.selection != selection || state.loadedKey?.includeAdult != includeAdult
        guard let attempt = state.begin(selection, includeAdult: includeAdult, refresh: refresh) else { return }
        defer { state.finish(attempt) }
        do {
            if needsRestore, let saved = await cache.load(selection, includeAdult: includeAdult) {
                try Task.checkCancellation()
                guard state.isCurrent(attempt) else { return }
                if state.restore(saved, for: attempt) { return }
            }
            let response = try await api.explore(selection, refresh: refresh, includeAdult: includeAdult)
            try Task.checkCancellation()
            guard state.complete(response, for: attempt) else { return }
            await cache.save(ExploreSnapshot(response: response, selection: selection, includeAdult: includeAdult))
        } catch is CancellationError {} catch {
            if !Task.isCancelled { state.fail(error.localizedDescription, for: attempt) }
        }
    }
}
