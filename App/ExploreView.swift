import SwiftUI
import AnimeCore

struct ExploreView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection = SeasonSelection.current()
    @State private var seasonal: [Anime] = []
    @State private var trending: [Anime] = []
    @State private var upcoming: [Anime] = []
    @State private var personalizedDub: [ReleaseEvent] = []
    @State private var loading = false
    @State private var loadingMore = false
    @State private var page = 1
    @State private var hasMore = false
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var loadedSelection: SeasonSelection?
    @State private var showSeasons = false
    @State private var showSettings = false
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                HStack {
                    Button { showSeasons = true } label: { Label(selection.label, systemImage: "chevron.down").font(.headline) }
                    Spacer()
                    NavigationLink { SearchView() } label: { Image(systemName: "magnifyingglass").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Search anime")
                }.padding(.horizontal)
                if !store.watching.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Continue watching").font(.title3.bold()).padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(store.watching) { entry in
                                    if let anime = entry.media {
                                        VStack(alignment: .leading, spacing: 6) {
                                            AnimeCard(anime: anime)
                                            Text("Episode \(entry.progressValue) / \(anime.episodes.map(String.init) ?? "?")").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }.padding(.horizontal)
                        }
                    }
                    if !comingUp.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Coming up for you").font(.title3.bold())
                            ForEach(Array(comingUp.prefix(4))) { ReleaseRow(event: $0) }
                        }.padding(.horizontal)
                    }
                }
                if let error { NoticeView(message: error) { Task { await load(refresh: true) } }.padding(.horizontal) }
                if loading && seasonal.isEmpty { ProgressView("Finding your season…").frame(maxWidth: .infinity).padding(40) }
                AnimeShelf(title: "Airing now", anime: seasonal.filter { $0.status == "RELEASING" })
                AnimeShelf(title: "Popular · \(selection.label)", anime: seasonal)
                if hasMore {
                    Button { Task { await loadMore() } } label: {
                        if loadingMore { ProgressView() } else { Text("More from this season") }
                    }.buttonStyle(.bordered).disabled(loadingMore).padding(.horizontal)
                }
                AnimeShelf(title: "Trending", anime: trending)
                AnimeShelf(title: "Upcoming · \(selection.advanced(by: 1).label)", anime: upcoming)
                if !loading && error == nil && seasonal.isEmpty {
                    ContentUnavailableView("No seasonal entries yet", systemImage: "sparkles", description: Text("Try another season or search for an anime."))
                }
                Text("Metadata from AniList").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }.padding(.vertical)
        }.background(Theme.background).navigationTitle("Explore").animeNavigation()
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showSettings = true } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel("Account and settings") } }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showSeasons) { seasonPicker }
            .task(id: selection) { await load() }
            .task(id: store.watching.map(\.mediaId)) { await loadPersonalizedDubs() }
            .refreshable { await load(refresh: true); await loadPersonalizedDubs() }
    }
    private var seasonPicker: some View {
        NavigationStack {
            Form {
                Picker("Season", selection: $selection.season) { ForEach(AnimeSeason.allCases, id: \.self) { Text($0.label).tag($0) } }
                Picker("Year", selection: $selection.year) { ForEach(Array((1970...SeasonSelection.current().year + 2).reversed()), id: \.self) { Text(String($0)).tag($0) } }
                Button("Current season") { selection = .current(); showSeasons = false }
            }.navigationTitle("Browse seasons").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSeasons = false } } }
        }.presentationDetents([.medium])
    }
    private var comingUp: [ReleaseEvent] {
        let original = store.watching.compactMap { entry -> ReleaseEvent? in
            guard let media = entry.media, let next = media.nextAiringEpisode else { return nil }
            return ReleaseEvent(anime: media, episode: next.episode, kind: .sub, date: next.date, certainty: .broadcast)
        }
        return (original + personalizedDub).filter { event in
            guard let date = event.date else { return false }
            return date >= Date() && date < Date().addingTimeInterval(7 * 86400)
        }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
    private func load(refresh: Bool = false) async {
        let attempt = UUID(); requestID = attempt; let selected = selection
        if loadedSelection != selected { seasonal = []; trending = []; upcoming = []; hasMore = false }
        loading = true; error = nil
        defer { if requestID == attempt { loading = false } }
        do {
            let result = try await store.aniList.explore(selected, refresh: refresh)
            try Task.checkCancellation(); guard requestID == attempt else { return }
            seasonal = result.seasonal.media ?? []; trending = result.trending.media ?? []; upcoming = result.upcoming.media ?? []
            hasMore = result.seasonal.pageInfo?.hasNextPage == true; page = 1
            loadedSelection = selected
        } catch is CancellationError {} catch { if requestID == attempt { self.error = error.localizedDescription } }
    }
    private func loadMore() async {
        guard !loadingMore else { return }; loadingMore = true
        let attempt = requestID; let nextPage = page + 1
        defer { loadingMore = false }
        do {
            let result = try await store.aniList.seasonal(selection, page: nextPage)
            guard requestID == attempt else { return }
            let existing = Set(seasonal.map(\.id))
            seasonal += (result.media ?? []).filter { !existing.contains($0.id) }
            page = nextPage; hasMore = result.pageInfo?.hasNextPage == true
        } catch { if requestID == attempt { self.error = error.localizedDescription } }
    }
    private func loadPersonalizedDubs() async {
        let entries = store.watching; let ids = Set(entries.map(\.mediaId))
        guard !ids.isEmpty else { personalizedDub = []; return }
        do {
            let snapshot = try await store.dubs.snapshot()
            try Task.checkCancellation()
            let known = Dictionary(uniqueKeysWithValues: entries.compactMap { $0.media.map { ($0.id, $0) } })
            personalizedDub = snapshot.events(knownMedia: known).filter { ids.contains($0.anime.id) }
        } catch { personalizedDub = [] }
    }
}

struct SearchView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var results: [Anime] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        List {
            if let error { NoticeView(message: error) }
            if loading { ProgressView("Searching…") }
            ForEach(results) { anime in
                NavigationLink(value: AnimeRoute(id: anime.id)) {
                    HStack(spacing: 12) {
                        AnimeCover(anime: anime, width: 50)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(anime.displayTitle).font(.headline)
                            Text([anime.format?.replacingOccurrences(of: "_", with: " "), anime.seasonYear.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !query.isEmpty && !loading && error == nil && results.isEmpty { Text("No anime found.").foregroundStyle(.secondary) }
        }.navigationTitle("Search").searchable(text: $query, prompt: "Anime title").animeNavigation()
            .task(id: query) {
                let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
                results = []; error = nil
                guard text.count >= 2 else { loading = false; return }
                loading = true
                do {
                    try await Task.sleep(for: .milliseconds(500))
                    let page = try await store.aniList.search(text)
                    try Task.checkCancellation()
                    guard query.trimmingCharacters(in: .whitespacesAndNewlines) == text else { return }
                    results = page.media ?? []; loading = false
                } catch is CancellationError {} catch { if query.trimmingCharacters(in: .whitespacesAndNewlines) == text { self.error = error.localizedDescription; loading = false } }
            }
    }
}
