import SwiftUI
import AnimeCore

struct CinematicHomeSpotlight: View {
    let refreshID: Int
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var books: MangaBakaStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @EnvironmentObject private var filters: DiscoveryFilterStore
    @State private var publicAnime: [Anime] = []
    @State private var publicBooks: [MangaBakaSeries] = []
    @State private var loading = false
    @State private var failed = false
    @State private var retry = 0
    private var stories: [ExploreStory] {
        let shows = (store.watching.compactMap(\.media) + publicAnime).filter {
            store.isVisible($0) && filters.includes($0, dubs: dubs, library: store)
        }
        let reading = books.library.filter { ["reading", "rereading"].contains($0.state) }.compactMap(\.series)
        return ExploreStory.mix(anime: shows, reading: reading + publicBooks,
            includeAdult: store.includeAdult, contentFilter: store.mangaBakaContent)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !stories.isEmpty { CinematicStorySpotlight(stories: stories, eyebrow: store.isSignedIn || books.connected ? "For you" : "Discover") }
            else if loading {
                RoundedRectangle(cornerRadius: 24).fill(Theme.surface).frame(height: 300).overlay { ProgressView("Finding your next story…") }
            } else {
                ContentUnavailableView("Your next story awaits", systemImage: "sparkles", description: Text("Explore titles or add something to your library."))
            }
            if failed {
                HStack {
                    Text(stories.isEmpty ? "Discoveries are unavailable right now." : "Showing saved discoveries.").font(.caption).foregroundStyle(.secondary)
                    Spacer(); Button("Retry") { retry += 1 }.font(.caption.weight(.semibold))
                }
            }
        }.task(id: "\(store.includeAdult)-\(store.mangaBakaContent)-\(refreshID)-\(retry)") { await load() }
    }
    private func load() async {
        loading = true; failed = false
        defer { if !Task.isCancelled { loading = false } }
        let adult = store.includeAdult, content = store.mangaBakaContent
        async let shows: Void = loadAnime(adult: adult)
        async let written: Void = loadBooks(content: content)
        _ = await (shows, written)
    }
    private func loadAnime(adult: Bool) async {
        let key = "home-trending-v1-\(adult)"
        let saved = await store.homeContentCache.load([Anime].self, key: key)
        guard !Task.isCancelled, adult == store.includeAdult else { return }
        if let saved { publicAnime = saved.value }
        if refreshID == 0 && retry == 0, let saved, !saved.needsRefresh() { return }
        do {
            let page = try await store.aniList.browse(DiscoveryFilters(category: .trending), page: 1,
                refresh: refreshID > 0 || retry > 0, includeAdult: adult)
            guard !Task.isCancelled, adult == store.includeAdult else { return }
            publicAnime = page.media ?? []
            await store.homeContentCache.save(HomeContentSnapshot(publicAnime), key: key)
        } catch is CancellationError {} catch { if !Task.isCancelled { failed = true } }
    }
    private func loadBooks(content: MangaBakaContentFilter) async {
        do {
            let page = try await books.api.browse(.init(shelf: .trending), limit: 12, contentFilter: content,
                refresh: refreshID > 0 || retry > 0)
            guard !Task.isCancelled, content == store.mangaBakaContent else { return }
            publicBooks = page.items
        } catch is CancellationError {} catch { if !Task.isCancelled { failed = true } }
    }
}
