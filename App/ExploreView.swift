import SwiftUI
import AnimeCore

struct ExploreView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @EnvironmentObject private var dubFilters: DiscoveryFilterStore
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var posterBackground = PosterAccent.fallback.backdrop
    @State private var selection = SeasonSelection.current()
    @State private var seasonal: [Anime] = []
    @State private var trending: [Anime] = []
    @State private var upcoming: [Anime] = []
    @State private var loading = false
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var loadedKey: String?
    @State private var savedCatalogDate: Date?
    @State private var needsCatalogRefresh = true
    @State private var showSeasons = false
    @State private var showSettings = false
    @State private var showDisplay = false
    @State private var showDubFilters = false
    @State private var liveChartPage: URL?
    private var posters = PosterPreferences(.explore)

    var body: some View {
        GeometryReader { geometry in
          if store.metadataSource == .liveChart {
            VStack(spacing: 0) {
                HStack {
                    Button { showSeasons = true } label: { Label(selection.label, systemImage: "calendar") }
                    Spacer()
                    Text("LiveChart listings").font(.caption).foregroundStyle(.secondary)
                }.padding(12)
                LiveChartBrowserView(startURL: liveChartPage ?? LiveChartURL.season(selection))
                    .id(liveChartPage ?? LiveChartURL.season(selection))
            }
          } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !featured.isEmpty {
                    FeaturedAnimeCarousel(anime: featured,
                        height: CGFloat(PosterLayout.featuredHeight(preferred: posters.featuredHeight,
                            viewportHeight: Double(geometry.size.height + geometry.safeAreaInsets.top),
                            fillScreen: posters.fillFeaturedScreen)) + (textSize.isAccessibilitySize ? 240 : 0),
                        topInset: geometry.safeAreaInsets.top, background: $posterBackground)
                }
                LazyVStack(alignment: .leading, spacing: 26) {
                HStack {
                    Button { showSeasons = true } label: {
                        Label(selection.label, systemImage: "chevron.down").font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 11).silverGlass(in: Capsule())
                    }
                    Spacer()
                    DubFilterButton { showDubFilters = true }
                }.padding(.horizontal)
                if dubFilters.selection.isActive && !dubs.loaded {
                    ProgressView("Checking English dubs…").frame(maxWidth: .infinity)
                }
                if let error { NoticeView(message: error) { Task { await load(refresh: true) } }.padding(.horizontal) }
                shelf(.trending, anime: trending, availableWidth: geometry.size.width)
                shelf(.seasonal, anime: seasonal, availableWidth: geometry.size.width)
                shelf(.upcoming, anime: upcoming, availableWidth: geometry.size.width)
                if loading && loadedKey == nil { ProgressView("Loading Explore…").frame(maxWidth: .infinity).padding(40) }
                if let savedCatalogDate {
                    HStack(spacing: 6) {
                        if loading { ProgressView().controlSize(.mini) }
                        Text("Saved catalog · Updated \(savedCatalogDate.formatted(.relative(presentation: .named)))")
                    }.font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                }
                DiscoveryDataNote().padding(.horizontal)
                }.padding(.top, featured.isEmpty ? geometry.safeAreaInsets.top + 20 : 20)
                    .padding(.bottom, 24).readableContent(width: 1280)
                    .frame(maxWidth: .infinity).background(Theme.background)
            }
          }.ignoresSafeArea(.container, edges: .top).accessibilityIdentifier("explore-scroll")
          }
        }.background(Theme.background.ignoresSafeArea())
            .navigationTitle("Explore").navigationBarTitleDisplayMode(.inline).animeNavigation()
            .toolbarBackground(.automatic, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Metadata source", selection: $store.metadataSource) {
                            ForEach(MetadataSource.allCases) { Text($0.label).tag($0) }
                        }
                    } label: { Image(systemName: "globe").frame(width: 44, height: 44) }
                        .accessibilityLabel("Metadata source: \(store.metadataSource.label)").accessibilityIdentifier("explore-metadata-source")
                }
                if store.metadataSource == .aniList {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showDubFilters = true } label: { Image(systemName: "line.3.horizontal.decrease") }
                        .accessibilityLabel("Dub filters").accessibilityIdentifier("explore-dub-filter-toolbar")
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(value: DiscoveryRoute(category: .trending, selection: selection, titleOverride: "Search")) {
                        Image(systemName: "magnifyingglass").frame(minWidth: 44, minHeight: 44)
                    }.accessibilityLabel("Search anime").accessibilityIdentifier("explore-search")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showDisplay = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Explore display options").accessibilityIdentifier("explore-display-options")
                }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { liveChartPage = LiveChartURL.search("") } label: { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }
                            .accessibilityLabel("Search LiveChart")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button { showSettings = true } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel("Account and settings") }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showDisplay) { DisplayOptionsView(scope: .explore) }
            .sheet(isPresented: $showDubFilters) { DubFiltersView() }
            .sheet(isPresented: $showSeasons) { seasonPicker }
            .task(id: "\(selection.label)-\(store.includeAdult)-\(store.metadataSource.rawValue)") {
                if store.metadataSource == .aniList { await load() }
            }
            .onChange(of: selection) { _, _ in liveChartPage = nil }
            .task { await dubs.load(using: store.dubs) }
            .refreshable {
                async let metadata: Void = load(refresh: true)
                async let dubInfo: Void = dubs.load(using: store.dubs, refresh: true)
                _ = await (metadata, dubInfo)
            }
    }
    private var featured: [Anime] {
        var ids = Set<Int>()
        return Array((trending + seasonal + upcoming).filter {
            store.isVisible($0) && ids.insert($0.id).inserted && dubFilters.includes($0, dubs: dubs, library: store)
        }.prefix(5))
    }
    private func shelf(_ category: DiscoveryCategory, anime: [Anime], availableWidth: CGFloat) -> some View {
        let visible = anime.filter { store.isVisible($0) && dubFilters.includes($0, dubs: dubs, library: store) }
        return VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: DiscoveryRoute(category: category, selection: selection)) {
                HStack {
                    Text(category.label(season: selection)).font(.title3.bold())
                    Spacer()
                    Text("See all").font(.caption)
                    Image(systemName: "chevron.right").font(.caption.bold())
                }.foregroundStyle(.primary).frame(minHeight: 44).padding(.horizontal).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("explore-category-\(category.rawValue)")
            if !visible.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(visible.prefix(16))) {
                            AnimeCard(anime: $0, posterWidth: min(CGFloat(min(360, max(120, posters.shelfWidth))), availableWidth * 0.85))
                        }
                    }.padding(.horizontal)
                }
            } else if !loading {
                Text(dubFilters.selection.isActive ? "No matches in this preview. Open See all to browse more titles or adjust your dub filters." : "No titles listed yet.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }
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
        let requestedAdult = store.includeAdult
        let desiredKey = "\(selection.label)-\(requestedAdult)"
        guard !Task.isCancelled, refresh || loadedKey != desiredKey || needsCatalogRefresh else { return }
        let attempt = UUID(); requestID = attempt; let requestedSelection = selection; let key = desiredKey
        let needsRestore = loadedKey != key
        if needsRestore { seasonal = []; trending = []; upcoming = []; loadedKey = nil; savedCatalogDate = nil }
        loading = true; error = nil; needsCatalogRefresh = true
        defer { if requestID == attempt { loading = false } }
        do {
            if needsRestore, let saved = await store.exploreCache.load(requestedSelection, includeAdult: requestedAdult) {
                try Task.checkCancellation(); guard requestID == attempt, selection == requestedSelection, store.includeAdult == requestedAdult else { return }
                show(saved.response, key: key)
                savedCatalogDate = saved.savedAt
                if !refresh && !saved.needsRefresh() { needsCatalogRefresh = false; return }
            }
            let result = try await store.aniList.explore(requestedSelection, refresh: refresh, includeAdult: requestedAdult)
            try Task.checkCancellation(); guard requestID == attempt, selection == requestedSelection, store.includeAdult == requestedAdult else { return }
            show(result, key: key); savedCatalogDate = nil; needsCatalogRefresh = false
            await store.exploreCache.save(ExploreSnapshot(response: result, selection: requestedSelection, includeAdult: requestedAdult))
        } catch is CancellationError {} catch { if requestID == attempt { self.error = error.localizedDescription } }
    }
    private func show(_ result: ExploreResponse, key: String) {
        seasonal = result.seasonal.media ?? []; trending = result.trending.media ?? []; upcoming = result.upcoming.media ?? []
        loadedKey = key
    }
}
