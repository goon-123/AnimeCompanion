import SwiftUI
import UIKit
import AnimeCore

struct HomeView: View {
    @AppStorage(HomeArtworkSize.storageKey) private var artworkSize = HomeArtworkSize.large.rawValue
    var body: some View {
        GeometryReader { geometry in
            HomeDashboardView()
                .environment(\.homeVisuals, HomeVisualMetrics(isPad: UIDevice.current.userInterfaceIdiom == .pad,
                    availableWidth: max(0, min(geometry.size.width, 1180) - 40),
                    artworkSize: HomeArtworkSize(rawValue: artworkSize) ?? .large))
        }
    }
}

private struct HomeDashboardView: View {
    @AppStorage(ScreenPresentationScope.home.storageKey) private var savedPresentation = ScreenPresentation.cinematic.rawValue
    @State private var backdrop: URL?
    @State private var screenAppearance = false
    private var cinematic: Bool { ScreenPresentation(preference: savedPresentation) == .cinematic }
    @EnvironmentObject private var anime: AppStore
    @EnvironmentObject private var books: MangaBakaStore
    @EnvironmentObject private var reading: MangaReadingStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @EnvironmentObject private var sourceLinks: MangaSourceLinkStore
    @EnvironmentObject private var extensions: MangaExtensionStore
    @EnvironmentObject private var weeklySchedule: WeeklyScheduleStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.homeVisuals) private var visuals
    @AppStorage(HomePreferences.storageKey) private var sections = ""
    @AppStorage(HomeArtworkSize.storageKey) private var artworkSize = HomeArtworkSize.large.rawValue
    @AppStorage("manga.showMatureSources") private var matureSources = false
    @State private var customize = false
    @State private var pickingWidgets = false
    @State private var editing = false
    @State private var dragging: HomeSection?
    @State private var settings = false
    @State private var newsRefreshID = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var appeared = false
    @State private var homeVisitID = 0
    private var preferences: HomePreferences { HomePreferences(saved: sections) }
    private var recent: [MangaReadingRecord] {
        guard !extensions.loading else { return [] }
        return Array(reading.state.records.filter { record in
            let mature = record.title.source.adult || extensions.installed(record.title.source.extensionID)?.descriptor.adult == true
            return record.lastReadAt != nil && (matureSources || !mature)
        }
            .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }.prefix(preferences.size(for: .reading).itemLimit))
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if editing { editorBar }
                ForEach(preferences.visible) { section in
                    if shouldDisplay(section) {
                        HomeWidgetFrame(section: section, saved: $sections, editing: $editing, dragging: $dragging) {
                            HomeWidgetContent(section: section, saved: $sections, editing: editing, refreshID: newsRefreshID, activationID: homeVisitID)
                        }.id(section)
                    }
                }
                if preferences.visible.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.stack.badge.plus").font(.largeTitle).foregroundStyle(Theme.accent)
                        Text("A fresh start.").font(.headline)
                        Text("Add only what you want on Home.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Add widgets", systemImage: "plus") { editing = true; pickingWidgets = true }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("home-empty-add")
                    }.frame(maxWidth: .infinity).padding(.vertical, 44).accessibilityIdentifier("home-empty-layout")
                }
            }.environment(\.cinematicCards, cinematic)
                .padding(20).padding(.bottom, 20).frame(maxWidth: 1180, alignment: .leading).frame(maxWidth: .infinity)
        }.background { if cinematic { CinematicScreenBackground(url: backdrop) } else { Theme.background } }
            .onPreferenceChange(CinematicBackdropKey.self) { backdrop = $0 }
            .navigationTitle("Home").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(cinematic ? .hidden : .automatic, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AccountSwitcherButton() }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if editing {
                        Button { pickingWidgets = true } label: { Image(systemName: "plus").font(visuals.toolbarIconFont) }
                            .accessibilityLabel("Add widgets").accessibilityIdentifier("home-add-widgets")
                    }
                    if editing { Button("Done") {
                        withAnimation(.easeInOut(duration: 0.18)) { editing = false; dragging = nil }
                    }.fontWeight(.semibold).accessibilityLabel("Finish editing Home").accessibilityIdentifier("home-finish-editing") }
                    Menu {
                        Button("Screen appearance", systemImage: "sparkles.rectangle.stack") { screenAppearance = true }
                        Button("Customize Home", systemImage: "slider.horizontal.3") { editing = true }.accessibilityIdentifier("home-customize")
                        Button("Add widgets", systemImage: "plus") { editing = true; pickingWidgets = true }
                        Button("Manage widgets", systemImage: "slider.horizontal.3") { customize = true }
                        Divider()
                        Button("Search", systemImage: "magnifyingglass") { navigation.openSearch() }
                        Button("Calendar", systemImage: "calendar") { navigation.openSchedule() }
                        Button("Airing Now", systemImage: "play.rectangle") { navigation.openSchedule(page: .airing) }
                        Button("News", systemImage: "newspaper") { navigation.openNews() }
                        NavigationLink { CommunityFeedView() } label: { Label("Community", systemImage: "bubble.left.and.bubble.right") }
                        Button("My Library", systemImage: "books.vertical") { navigation.open(.library) }
                        NavigationLink { SourcesSettingsView() } label: { Label("Sources & playback", systemImage: "puzzlepiece.extension") }
                        Button("Settings", systemImage: "gearshape") { settings = true }
                    } label: { Image(systemName: "ellipsis").font(visuals.toolbarIconFont) }
                        .accessibilityLabel("Home actions").accessibilityIdentifier("home-actions")
                }
            }
            .onDrop(of: [HomeWidgetDrag.type], delegate: HomeWidgetDropDelegate(target: nil, saved: $sections, dragging: $dragging, enabled: editing))
            .animeNavigation().mangaBakaNavigation()
            .navigationDestination(for: ExploreSearchRoute.self) { _ in UnifiedExploreSearchView().animeNavigation().mangaBakaNavigation() }
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .schedule(let route):
                    if route.page == .airing { HomeAiringNowView().environment(\.animeSplitPresentation, false) }
                    else { ScheduleView(landing: route).environment(\.animeSplitPresentation, false) }
                case .news(let collection): NewsView(initialCollection: collection).environment(\.animeSplitPresentation, false)
                }
            }
            .onAppear {
                if appeared { homeVisitID += 1 }
                appeared = true
                Task { await anime.refreshLibraryIfNeeded() }
            }
            .onChange(of: scenePhase) { previous, current in
                if current == .active && previous != .active { homeVisitID += 1 }
            }
            .task {
                await reading.load(); await sourceLinks.load()
                if !reading.state.records.isEmpty { await extensions.load() }
            }
            .task(id: "\(books.connected)-\(books.connectionID)-\(books.revision)") { if books.connected { await books.loadLibrary(state: nil) } }
            .refreshable {
                newsRefreshID += 1
                async let shows: Void = refreshAnime()
                async let titles: Void = refreshBooks()
                async let week: Void = refreshWeek()
                _ = await (shows, titles, week)
            }
            .appSettingsSheet(isPresented: $settings)
            .sheet(isPresented: $screenAppearance) {
                AppNavigationStack { ScreenAppearanceSettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { screenAppearance = false } } } }
            }
            .sheet(isPresented: $customize) {
                AppNavigationStack {
                    HomeCustomizationView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { customize = false } } }
                }
            }
            .sheet(isPresented: $pickingWidgets) { AppNavigationStack { HomeWidgetPicker() } }
            .accessibilityIdentifier("home-dashboard")
    }
    private func refreshAnime() async { if anime.isSignedIn { await anime.reloadLibrary() } }
    private func refreshWeek() async {
        guard anime.isSignedIn, (preferences.visible.contains(.weekly) || preferences.visible.contains(.today)) else { return }
        async let original: Void = weeklySchedule.load(in: ScheduleWeek(containing: ScheduleClock.now, firstWeekday: 1).window, using: anime.aniList, refresh: true)
        async let dubbed: Void = dubs.load(using: anime.dubs, refresh: true)
        _ = await (original, dubbed)
    }
    private func refreshBooks() async { if books.connected { await books.loadLibrary(state: nil, refresh: true) } }
    private func shouldDisplay(_ section: HomeSection) -> Bool {
        if section == .cinematicSpotlight { return cinematic }
        if editing { return true }
        if section == .welcome { return !anime.isSignedIn && !books.connected && recent.isEmpty }
        if section == .syncStatus { return anime.loadingLibrary || books.loadingLibrary || anime.libraryError != nil || books.libraryError != nil || reading.error != nil }
        return true
    }
    private var editorBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Make Home yours").font(.headline)
            Text("Drag a handle to rearrange. Use − to hide a widget, or its menu to move it and change preview items.")
                .font(.caption).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { editorActions }
                VStack(alignment: .leading, spacing: 4) { editorActions }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).companionPanel(padding: 14).accessibilityIdentifier("home-editor")
    }
    @ViewBuilder private var editorActions: some View {
        Button("Add widgets", systemImage: "plus") { pickingWidgets = true }
        Button("Manage widgets", systemImage: "slider.horizontal.3") { customize = true }.accessibilityIdentifier("home-manage-widgets")
        if UIDevice.current.userInterfaceIdiom == .pad {
            Menu {
                Picker("Artwork size", selection: $artworkSize) {
                    ForEach(HomeArtworkSize.allCases) { size in Text(size.title).tag(size.rawValue) }
                }
            } label: { Label("Artwork size", systemImage: "photo.on.rectangle.angled") }
                .accessibilityIdentifier("home-artwork-size-menu")
        }
    }
}
