import SwiftUI
import AnimeCore

struct StudioAnimeView: View {
    let studio: Studio
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var sort = DiscoverySort.popularity
    @State private var items: [Anime] = []
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?
    @State private var requestID = UUID()
    private var visible: [Anime] { items.filter { store.isVisible($0) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Anime credited to this studio").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Picker("Sort studio anime", selection: $sort) {
                        Text("Popular").tag(DiscoverySort.popularity)
                        Text("Top rated").tag(DiscoverySort.rating)
                        Text("Newest").tag(DiscoverySort.newest)
                    }.pickerStyle(.menu)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 210 : 160), spacing: 14, alignment: .top)], alignment: .leading, spacing: 20) {
                    ForEach(visible) { AnimeCard(anime: $0, posterWidth: 150) }
                }
                if let error { NoticeView(message: error) { Task { await load(reset: page == 0, refresh: true) } } }
                if loading { ProgressView("Loading studio anime…").frame(maxWidth: .infinity, minHeight: 60) }
                else if hasMore { Button("Load more anime") { Task { await load(reset: false) } }.buttonStyle(.bordered).frame(maxWidth: .infinity) }
                else if visible.isEmpty && error == nil {
                    ContentUnavailableView("No anime to show", systemImage: "film", description: Text("No titles match your content preferences."))
                }
            }.padding(16).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle(studio.name).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).toolbar(.hidden, for: .tabBar).animeNavigation()
            .task(id: "\(studio.id)-\(sort.rawValue)-\(store.includeAdult)") { await load(reset: true) }
            .refreshable { await load(reset: true, refresh: true) }
            .accessibilityIdentifier("studio-anime-page")
    }
    @MainActor private func load(reset: Bool, refresh: Bool = false) async {
        guard reset || (!loading && hasMore) else { return }
        let attempt = UUID(); requestID = attempt; loading = true; error = nil
        if reset { items = []; page = 0; hasMore = false }
        let nextPage = reset ? 1 : page + 1
        defer { if requestID == attempt { loading = false } }
        do {
            let result = try await store.aniList.studioAnime(id: studio.id, page: nextPage, sort: sort, includeAdult: store.includeAdult, refresh: refresh)
            try Task.checkCancellation()
            guard requestID == attempt else { return }
            var seen = Set(items.map(\.id))
            items += (result.media ?? []).filter { seen.insert($0.id).inserted }
            page = nextPage; hasMore = result.pageInfo?.hasNextPage == true
        } catch is CancellationError {} catch { if requestID == attempt, !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
