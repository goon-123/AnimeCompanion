import SwiftUI
import AnimeCore

struct ExploreView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @EnvironmentObject private var dubFilters: DiscoveryFilterStore
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.animeSplitPresentation) private var usesSplit
    @State private var posterBackground = PosterAccent.fallback.backdrop
    @State private var selection = SeasonSelection.current()
    @StateObject private var catalog = ExploreCatalogModel()
    @State private var showSeasons = false
    @State private var showSettings = false
    @State private var showDisplay = false
    @State private var showDubFilters = false
    @State private var liveChartPage: URL?
    private var posters = PosterPreferences(.explore)
    private var seasonal: [Anime] { catalog.state.response?.seasonal.media ?? [] }
    private var trending: [Anime] { catalog.state.response?.trending.media ?? [] }
    private var upcoming: [Anime] { catalog.state.response?.upcoming.media ?? [] }
    private var loading: Bool { catalog.state.loading }
    private var error: String? { catalog.state.error }
    private var loadedKey: ExploreCatalogState.Key? { catalog.state.loadedKey }
    private var savedCatalogDate: Date? { catalog.state.savedAt }

    var body: some View {
        GeometryReader { geometry in
          if store.metadataSource == .liveChart {
            LiveChartBrowserView(startURL: liveChartPage ?? LiveChartURL.season(selection))
                .id(liveChartPage ?? LiveChartURL.season(selection))
          } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !featured.isEmpty {
                    FeaturedAnimeCarousel(anime: featured,
                        height: CGFloat(PosterLayout.featuredHeight(preferred: posters.featuredHeight,
                            viewportHeight: Double(geometry.size.height + geometry.safeAreaInsets.top),
                            fillScreen: posters.fillFeaturedScreen, balanced: posters.balancedFeatured,
                            splitColumnWidth: usesSplit ? Double(geometry.size.width) : nil)) + (textSize.isAccessibilitySize ? 240 : 0),
                        topInset: geometry.safeAreaInsets.top, background: $posterBackground)
                }
                LazyVStack(alignment: .leading, spacing: 26) {
                if dubFilters.selection.isActive && !dubs.loaded {
                    ProgressView("Checking English dubs…").frame(maxWidth: .infinity)
                }
                if let error { NoticeView(message: error) { Task { await load(refresh: true) } }.padding(.horizontal) }
                if dubFilters.selection.dub != .all && dubs.loaded && dubs.unavailable {
                    NoticeView(message: "Dub information is temporarily incomplete. Existing matches are shown; adjust your dub filters to browse all anime.") {
                        Task { await dubs.load(using: store.dubs, refresh: true) }
                    }.padding(.horizontal)
                }
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
                }.padding(.top, 20)
                    .padding(.bottom, 24).readableContent(width: 1280)
                    .frame(maxWidth: .infinity).background(Theme.background)
            }
          }.accessibilityIdentifier("explore-scroll")
              .ignoresSafeArea(.container, edges: .top)
          }
        }.background(Theme.background.ignoresSafeArea())
            .navigationTitle("Explore").navigationBarTitleDisplayMode(.inline).animeNavigation()
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) { floatingSearch.padding(.trailing, 20).padding(.bottom, 16) }
            .appSettingsSheet(isPresented: $showSettings)
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
    private var floatingSearch: some View {
        Group {
            if store.metadataSource == .aniList {
                NavigationLink(value: DiscoveryRoute(category: .trending, selection: selection, titleOverride: "Search")) {
                    searchIcon
                }
            } else {
                Button { liveChartPage = LiveChartURL.search("") } label: { searchIcon }
            }
        }.buttonStyle(.plain).accessibilityLabel("Search anime").accessibilityIdentifier("explore-search")
            .accessibilityHint("Touch and hold for seasons, filters, display options and settings.")
            .contextMenu {
                Button { showSeasons = true } label: { Label("Browse seasons", systemImage: "calendar") }
                    .accessibilityIdentifier("explore-season")
                Button { showDubFilters = true } label: { Label("Dub filters", systemImage: "line.3.horizontal.decrease") }
                    .accessibilityIdentifier("explore-dub-filter-toolbar")
                Button { showDisplay = true } label: { Label("Display options", systemImage: "slider.horizontal.3") }
                    .accessibilityIdentifier("explore-display-options")
                Button { showSettings = true } label: { Label("Account and settings", systemImage: "gearshape") }
                    .accessibilityIdentifier("explore-settings")
            }
    }
    private var searchIcon: some View {
        Image(systemName: "magnifyingglass").font(.title3.weight(.semibold))
            .frame(width: 56, height: 56).silverGlass(in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
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
            } else if !loading && loadedKey != nil && error == nil && (dubFilters.selection.dub == .all || dubs.loaded) {
                Text(dubFilters.selection.isActive ? "No matches in this preview. Open See all to browse more titles or adjust your dub filters." : "No titles listed yet.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("explore-shelf-\(category.rawValue)")
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
        await catalog.load(selection: selection, includeAdult: store.includeAdult,
                           api: store.aniList, cache: store.exploreCache, refresh: refresh)
    }
}
