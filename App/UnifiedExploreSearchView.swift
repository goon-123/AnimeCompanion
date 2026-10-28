import SwiftUI
import AnimeCore

private struct UnifiedSearchKey: Equatable {
    let text: String
    let adult: Bool
    let contentFilter: MangaBakaContentFilter
    let scope: StorySearchScope
}

@MainActor
private final class UnifiedExploreSearchModel: ObservableObject {
    enum Provider: String, CaseIterable { case anime, reading }
    @Published var anime: [Anime] = []
    @Published var reading: [MangaBakaSeries] = []
    @Published var loading = Set<Provider>()
    @Published var errors: [Provider: String] = [:]
    @Published var more = Set<Provider>()
    private var pages: [Provider: Int] = [:]
    private var key: UnifiedSearchKey?
    private var generation = UUID()
    func prepare(_ key: UnifiedSearchKey) {
        guard self.key != key else { return }
        self.key = key; generation = UUID()
        anime = []; reading = []; pages = [:]; loading = []; more = []; errors = [:]
    }
    func load(_ provider: Provider, key: UnifiedSearchKey, api: AniListClient, books: MangaBakaClient, next: Bool = false, refresh: Bool = false) async {
        guard self.key == key, !key.text.isEmpty, !Task.isCancelled, !loading.contains(provider),
              !next || more.contains(provider), next || refresh || pages[provider] == nil else { return }
        let attempt = generation, page = next ? (pages[provider] ?? 0) + 1 : 1
        loading.insert(provider); errors[provider] = nil
        defer { if generation == attempt { loading.remove(provider) } }
        do {
            let hasMore: Bool
            switch provider {
            case .anime:
                let response = try await api.search(key.text, page: page, includeAdult: key.adult, refresh: refresh)
                try Task.checkCancellation(); guard attempt == generation else { return }
                var known = Set(next ? anime.map(\.id) : [])
                let values = (response.media ?? []).filter { known.insert($0.id).inserted }
                hasMore = response.pageInfo?.hasNextPage == true
                guard !next || !values.isEmpty || !hasMore else { throw ServiceError.message("No new anime on this page. Retry or change your search.") }
                anime = next ? anime + values : values
            case .reading:
                let response = try await books.browse(.init(format: key.scope == .novels ? .novel : nil, text: key.text), page: page, limit: 24, contentFilter: key.contentFilter, refresh: refresh)
                try Task.checkCancellation(); guard attempt == generation else { return }
                var known = Set(next ? reading.map(\.id) : [])
                let values = response.items.filter { known.insert($0.id).inserted }
                hasMore = response.hasNext
                guard !next || !values.isEmpty || !hasMore else { throw ServiceError.message("No new books on this page. Retry or change your search.") }
                reading = next ? reading + values : values
            }
            pages[provider] = page
            if hasMore { more.insert(provider) } else { more.remove(provider) }
        } catch is CancellationError {} catch {
            if attempt == generation && !Task.isCancelled { errors[provider] = error.localizedDescription }
        }
    }
}

struct UnifiedExploreSearchView: View {
    @EnvironmentObject private var anime: AppStore
    @EnvironmentObject private var reading: MangaBakaStore
    @StateObject private var model = UnifiedExploreSearchModel()
    @State private var text = ""
    @State private var scope = StorySearchScope.all
    private var key: UnifiedSearchKey { .init(text: String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)), adult: anime.includeAdult, contentFilter: anime.mangaBakaContent, scope: scope) }
    private var results: [ExploreStory] { ExploreStory.mix(anime: model.anime, reading: model.reading, includeAdult: anime.includeAdult, contentFilter: anime.mangaBakaContent).filter(scope.includes) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(StorySearchScope.allCases) { value in
                            CompanionFilterChip(title: value.label, selected: scope == value) { scope = value }
                                .accessibilityIdentifier("search-scope-" + value.rawValue)
                        }
                    }
                }
                if !text.isEmpty {
                    Button { text = "" } label: { Label("Clear search", systemImage: "xmark.circle") }
                        .font(.caption).accessibilityLabel("Clear all-catalog search")
                }
                if key.text.isEmpty {
                    ContentUnavailableView("Find your next story", systemImage: "magnifyingglass",
                        description: Text("One search for anime, manga, manhwa, light novels and more. No account needed."))
                } else {
                    Text(scope == .all ? "\(model.anime.filter { anime.isVisible($0) }.count) anime · \(model.reading.filter { $0.isVisible(contentFilter: anime.mangaBakaContent) }.count) manga & novels loaded" : "\(results.count) \(scope.label.lowercased()) loaded")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("unified-search-counts")
                    ForEach(activeProviders, id: \.self) { provider in
                        if let error = model.errors[provider] {
                            NoticeView(message: (provider == .anime ? "Anime: " : "Manga & novels: ") + error) {
                                Task { await load(provider, next: model.more.contains(provider), refresh: true) }
                            }.accessibilityIdentifier("unified-search-error-" + provider.rawValue)
                        }
                    }
                    ExploreStoryGrid(items: results)
                    if !model.loading.isEmpty { ProgressView("Searching catalogs…").frame(maxWidth: .infinity).padding() }
                    if results.isEmpty && model.loading.isEmpty && model.errors.isEmpty && key == modelKey {
                        ContentUnavailableView.search(text: key.text)
                    }
                    ForEach(activeProviders, id: \.self) { provider in
                        if model.more.contains(provider) {
                            Button(provider == .anime ? "More anime" : "More manga & novels") { Task { await load(provider, next: true) } }
                                .buttonStyle(.bordered).disabled(model.loading.contains(provider)).frame(maxWidth: .infinity)
                                .accessibilityIdentifier("unified-search-more-" + provider.rawValue)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Full catalogs & advanced filters").font(.headline)
                    NavigationLink(value: DiscoveryRoute(category: .trending, titleOverride: "Anime search", initialQuery: key.text)) { Label("Browse anime", systemImage: "play.rectangle") }
                    NavigationLink(value: MangaBakaBrowseRoute(query: .init(text: key.text))) { Label("Browse manga & novels", systemImage: "books.vertical") }
                }.font(.subheadline).padding(.top, 10)
                MangaBakaAttribution()
            }.padding(20).frame(maxWidth: 1180).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Search stories").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).scrollDismissesKeyboard(.immediately)
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Anime, manga & novels")
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .accessibilityIdentifier("unified-search")
            .task(id: key) {
                let requested = key
                model.prepare(requested); modelKey = nil
                guard !requested.text.isEmpty else { return }
                do { try await Task.sleep(for: .milliseconds(350)); try Task.checkCancellation() } catch { return }
                modelKey = requested
                async let shows: Void = load(.anime)
                async let written: Void = load(.reading)
                _ = await (shows, written)
            }
            .refreshable {
                guard !key.text.isEmpty else { return }
                async let shows: Void = load(.anime, refresh: true)
                async let written: Void = load(.reading, refresh: true)
                _ = await (shows, written)
            }
    }
    @State private var modelKey: UnifiedSearchKey?
    private var activeProviders: [UnifiedExploreSearchModel.Provider] {
        UnifiedExploreSearchModel.Provider.allCases.filter { $0 == .anime ? scope.needsAnime : scope.needsReading }
    }
    private func load(_ provider: UnifiedExploreSearchModel.Provider, next: Bool = false, refresh: Bool = false) async {
        guard activeProviders.contains(provider) else { return }
        await model.load(provider, key: key, api: anime.aniList, books: reading.api, next: next, refresh: refresh)
    }
}
