import SwiftUI
import AnimeCore

struct ExploreView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @EnvironmentObject private var dubFilters: DiscoveryFilterStore
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.animeSplitPresentation) private var usesSplit
    @Environment(\.animeBrowseViewportHeight) private var browseViewportHeight
    @State private var spotlightViewportOffset: CGFloat?
    @State private var posterBackground = PosterAccent.fallback.backdrop
    @State private var selection = SeasonSelection.current()
    @StateObject private var catalog = ExploreCatalogModel()
    @AppStorage(ExploreSurface.anime.storageKey) private var savedLayout = ""
    @State private var widgetRefreshID = 0
    @Binding var showSeasons: Bool
    @State private var showSettings = false
    @Binding var showDisplay: Bool
    @Binding var showDubFilters: Bool
    private var posters = PosterPreferences(.explore)
    private var seasonal: [Anime] { catalog.state.response?.seasonal.media ?? [] }
    private var trending: [Anime] { catalog.state.response?.trending.media ?? [] }
    private var upcoming: [Anime] { catalog.state.response?.upcoming.media ?? [] }
    private var loading: Bool { catalog.state.loading }
    private var error: String? { catalog.state.error }
    private var loadedKey: ExploreCatalogState.Key? { catalog.state.loadedKey }
    private var savedCatalogDate: Date? { catalog.state.savedAt }

    init(showSeasons: Binding<Bool>, showDisplay: Binding<Bool>, showDubFilters: Binding<Bool>) {
        _showSeasons = showSeasons
        _showDisplay = showDisplay
        _showDubFilters = showDubFilters
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if hasCatalogNotices { catalogNotices }
                    ExploreRows(surface: .anime, refreshID: widgetRefreshID, widgetInset: 16) { row in
                        catalogRow(row, geometry: geometry)
                    }
                    if let savedCatalogDate {
                        HStack(spacing: 6) {
                            if loading { ProgressView().controlSize(.mini) }
                            Text("Saved catalog · Updated \(savedCatalogDate.formatted(.relative(presentation: .named)))")
                        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    }
                    DiscoveryDataNote().padding(.horizontal)
                }.padding(.top, spotlightLeadsPage ? 0 : 12).padding(.bottom, 24)
                    .readableContent(width: 1280).frame(maxWidth: .infinity)
            }.accessibilityIdentifier("explore-scroll")
                .ignoresSafeArea(.container, edges: spotlightLeadsPage ? .top : [])
        }.onGeometryChange(for: CGFloat?.self) { viewport in
            guard viewport.size.width > 0, viewport.size.height > 0, let browseViewportHeight else { return nil }
            let localHeight = viewport.size.height + viewport.safeAreaInsets.top
            return localHeight - browseViewportHeight
        } action: { offset in
            // Keep the initial usable height, including its dock clearance. Only
            // real window changes should resize the hero after this first layout.
            if spotlightViewportOffset == nil, let offset { spotlightViewportOffset = offset }
        }.background(Theme.background.ignoresSafeArea())
            .navigationTitle("Explore").navigationBarTitleDisplayMode(.inline).animeNavigation()
            .toolbar(.hidden, for: .navigationBar)
            .environment(\.posterArtworkBadgesEnabled, false)
            .modifier(ExploreWidgetSupport(surface: .anime, refreshID: widgetRefreshID))
            .appSettingsSheet(isPresented: $showSettings)
            .sheet(isPresented: $showDisplay) { DisplayOptionsView(scope: .explore) }
            .sheet(isPresented: $showDubFilters) { DubFiltersView() }
            .sheet(isPresented: $showSeasons) { seasonPicker }
            .task(id: "\(selection.label)-\(store.includeAdult)") { await load() }
            .task { await dubs.load(using: store.dubs) }
            .refreshable {
                widgetRefreshID += 1
                async let metadata: Void = load(refresh: true)
                async let dubInfo: Void = dubs.load(using: store.dubs, refresh: true)
                _ = await (metadata, dubInfo)
            }
    }
    private var hasCatalogNotices: Bool {
        let checkingDubs = dubFilters.selection.isActive && !dubs.loaded
        let unavailableDubs = dubFilters.selection.dub != .all && dubs.loaded && dubs.unavailable
        return checkingDubs || error != nil || unavailableDubs
    }
    private var spotlightLeadsPage: Bool {
        !hasCatalogNotices && ExplorePreferences(surface: .anime, saved: savedLayout).visible.first == .catalog(.spotlight)
    }
    private var catalogNotices: some View {
        VStack(alignment: .leading, spacing: 10) {
            if dubFilters.selection.isActive && !dubs.loaded { ProgressView("Checking English dubs…").frame(maxWidth: .infinity) }
            if let error { NoticeView(message: error) { Task { await load(refresh: true) } }.padding(.horizontal) }
            if dubFilters.selection.dub != .all && dubs.loaded && dubs.unavailable {
                NoticeView(message: "Dub information is temporarily incomplete. Existing matches are shown; adjust your dub filters to browse all anime.") {
                    Task { await dubs.load(using: store.dubs, refresh: true) }
                }.padding(.horizontal)
            }
        }
    }
    @ViewBuilder private func catalogRow(_ row: ExploreCatalogRow, geometry: GeometryProxy) -> some View {
        if row == .spotlight {
            if !featured.isEmpty {
                FeaturedAnimeCarousel(anime: featured, height: featuredHeight(in: geometry),
                    topInset: spotlightLeadsPage ? geometry.safeAreaInsets.top : 0, background: $posterBackground)

            } else if loading {
                RoundedRectangle(cornerRadius: 24).fill(Theme.surface).frame(height: featuredHeight(in: geometry))
                    .overlay { ProgressView("Loading anime…") }
            }
        } else if row == .topTen {
            TopTrendingAnimeWidget(anime: trending.filter { store.isVisible($0) && dubFilters.includes($0, dubs: dubs, library: store) }, selection: selection).padding(.horizontal, 16)
        } else if row == .studios {
            AnimeStudioCollectionsWidget(refreshID: widgetRefreshID).padding(.horizontal, 16)
        } else if row == .animeGenres {
            AnimeGenreCollectionsWidget(anime: trending + seasonal + upcoming).padding(.horizontal, 16)
        } else if let category = row.discoveryCategory {
            shelf(category, anime: catalog.state.response?.media(for: category) ?? [], availableWidth: geometry.size.width)
        }
    }
    private func featuredHeight(in geometry: GeometryProxy) -> CGFloat {
        let viewportHeight: CGFloat
        if let browseViewportHeight, let spotlightViewportOffset {
            viewportHeight = browseViewportHeight + spotlightViewportOffset
        } else {
            viewportHeight = geometry.size.height + geometry.safeAreaInsets.top
        }
        return CGFloat(PosterLayout.featuredHeight(preferred: posters.featuredHeight,
            viewportHeight: Double(viewportHeight),
            fillScreen: posters.fillFeaturedScreen, balanced: posters.balancedFeatured,
            splitColumnWidth: usesSplit ? Double(geometry.size.width) : nil)) + (textSize.isAccessibilitySize ? 240 : 0)
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
        AppNavigationStack {
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
