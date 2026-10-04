import SwiftUI
import AnimeCore

struct ExploreView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @State private var selection = SeasonSelection.current()
    @State private var seasonal: [Anime] = []
    @State private var trending: [Anime] = []
    @State private var upcoming: [Anime] = []
    @State private var loading = false
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var loadedKey: String?
    @State private var showSeasons = false
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                HStack {
                    Button { showSeasons = true } label: { Label(selection.label, systemImage: "chevron.down").font(.headline) }
                    Spacer()
                    NavigationLink(value: DiscoveryRoute(category: .trending, selection: selection, titleOverride: "Search")) {
                        Image(systemName: "magnifyingglass").frame(minWidth: 44, minHeight: 44)
                    }.accessibilityLabel("Search anime").accessibilityIdentifier("explore-search")
                }.padding(.horizontal)
                if let error { NoticeView(message: error) { Task { await load(refresh: true) } }.padding(.horizontal) }
                shelf(.trending, anime: trending)
                shelf(.seasonal, anime: seasonal)
                shelf(.upcoming, anime: upcoming)
                if loading && loadedKey == nil { ProgressView("Finding your season…").frame(maxWidth: .infinity).padding(40) }
                DiscoveryDataNote().padding(.horizontal)
            }.padding(.vertical)
        }.background(Theme.background).navigationTitle("Explore").animeNavigation()
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showSettings = true } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel("Account and settings") } }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showSeasons) { seasonPicker }
            .task(id: selection) { await load() }
            .task { await dubs.load(using: store.dubs) }
            .refreshable {
                async let metadata: Void = load(refresh: true)
                async let dubInfo: Void = dubs.load(using: store.dubs, refresh: true)
                _ = await (metadata, dubInfo)
            }
    }
    private func shelf(_ category: DiscoveryCategory, anime: [Anime]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: DiscoveryRoute(category: category, selection: selection)) {
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
        let attempt = UUID(); requestID = attempt; let key = selection.label
        if loadedKey != key { seasonal = []; trending = []; upcoming = []; loadedKey = nil }
        loading = true; error = nil
        defer { if requestID == attempt { loading = false } }
        do {
            let result = try await store.aniList.explore(selection, refresh: refresh)
            try Task.checkCancellation(); guard requestID == attempt, selection.label == key else { return }
            seasonal = result.seasonal.media ?? []; trending = result.trending.media ?? []; upcoming = result.upcoming.media ?? []
            loadedKey = key
        } catch is CancellationError {} catch { if requestID == attempt { self.error = error.localizedDescription } }
    }
}
