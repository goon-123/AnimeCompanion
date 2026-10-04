import SwiftUI
import AnimeCore

struct ExploreView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("discovery.matureOnly") private var matureOnly = false
    @AppStorage("discovery.matureGenre") private var matureGenre = "Thriller"
    @State private var selection = SeasonSelection.current()
    @State private var seasonal: [Anime] = []
    @State private var trending: [Anime] = []
    @State private var upcoming: [Anime] = []
    @State private var matureAnime: [Anime] = []
    @State private var matureManhwa: [Anime] = []
    @State private var loading = false
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var loadedKey: String?
    @State private var showSeasons = false
    @State private var showSettings = false
    private var requestKey: String { "\(selection.label)-\(matureOnly)-\(matureGenre)" }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                HStack {
                    if matureOnly {
                        Text("Mature stories · \(matureGenre)").font(.headline)
                    } else {
                        Button { showSeasons = true } label: { Label(selection.label, systemImage: "chevron.down").font(.headline) }
                    }
                    Spacer()
                    NavigationLink { DiscoveryBrowseView(category: matureOnly ? .matureAnime : .trending, selection: selection, matureGenre: matureGenre, titleOverride: "Search") }
                        label: { Image(systemName: "magnifyingglass").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Search anime")
                }.padding(.horizontal)
                if let error { NoticeView(message: error) { Task { await load(refresh: true) } }.padding(.horizontal) }
                if loading && loadedKey == nil { ProgressView("Finding your season…").frame(maxWidth: .infinity).padding(40) }
                if matureOnly {
                    Text("Non-explicit horror, thriller and psychological stories. Change this focus in Settings.").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    shelf(.matureAnime, anime: matureAnime)
                    shelf(.matureManhwa, anime: matureManhwa)
                } else {
                    shelf(.trending, anime: trending)
                    shelf(.seasonal, anime: seasonal)
                    shelf(.upcoming, anime: upcoming)
                }
                Text("Metadata from AniList").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }.padding(.vertical)
        }.background(Theme.background).navigationTitle("Explore").animeNavigation()
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showSettings = true } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel("Account and settings") } }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showSeasons) { seasonPicker }
            .task(id: requestKey) { await load() }
            .refreshable { await load(refresh: true) }
    }
    private func shelf(_ category: DiscoveryCategory, anime: [Anime]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                DiscoveryBrowseView(category: category, selection: selection, matureGenre: matureGenre)
            } label: {
                HStack {
                    Text(category.label(season: selection)).font(.title3.bold())
                    Spacer()
                    Text("See all").font(.caption)
                    Image(systemName: "chevron.right").font(.caption.bold())
                }.foregroundStyle(.primary).frame(minHeight: 44).padding(.horizontal)
            }.buttonStyle(.plain).accessibilityIdentifier("explore-category-\(category.rawValue)")
            if !anime.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) { ForEach(Array(anime.prefix(16))) { AnimeCard(anime: $0) } }.padding(.horizontal)
                }
            } else if !loading { Text("No titles listed yet.").font(.caption).foregroundStyle(.secondary).padding(.horizontal) }
        }
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
    private func load(refresh: Bool = false) async {
        let attempt = UUID(); requestID = attempt; let key = requestKey
        if loadedKey != key { seasonal = []; trending = []; upcoming = []; matureAnime = []; matureManhwa = []; loadedKey = nil }
        loading = true; error = nil
        defer { if requestID == attempt { loading = false } }
        do {
            if matureOnly {
                let animeFilters = DiscoveryFilters(category: .matureAnime, matureGenre: matureGenre)
                let manhwaFilters = DiscoveryFilters(category: .matureManhwa, matureGenre: matureGenre)
                async let animePage = store.aniList.browse(animeFilters, refresh: refresh)
                async let manhwaPage = store.aniList.browse(manhwaFilters, refresh: refresh)
                let (a, m) = try await (animePage, manhwaPage)
                try Task.checkCancellation(); guard requestID == attempt, requestKey == key else { return }
                matureAnime = a.media ?? []; matureManhwa = m.media ?? []
            } else {
                let result = try await store.aniList.explore(selection, refresh: refresh)
                try Task.checkCancellation(); guard requestID == attempt, requestKey == key else { return }
                seasonal = result.seasonal.media ?? []; trending = result.trending.media ?? []; upcoming = result.upcoming.media ?? []
            }
            loadedKey = key
        } catch is CancellationError {} catch { if requestID == attempt { self.error = error.localizedDescription } }
    }
}
