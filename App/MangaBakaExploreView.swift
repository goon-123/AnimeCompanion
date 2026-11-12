import SwiftUI
import AnimeCore

struct MangaBakaSeriesRoute: Hashable { let series: MangaBakaSeries }
struct MangaBakaBrowseRoute: Hashable { let query: MangaBakaQuery }
struct ExploreSearchRoute: Hashable {}

private struct MangaBakaNavigation: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: MangaBakaSeriesRoute.self) { route in
            MangaBakaDetailView(series: route.series).id(route.series.id).toolbar(.visible, for: .navigationBar)
        }.navigationDestination(for: MangaBakaBrowseRoute.self) { route in
            Group {
                if route.query.shelf == .recommended { MangaBakaRecommendationsView() }
                else { MangaBakaBrowseView(initial: route.query).id(route.query) }
            }.toolbar(.visible, for: .navigationBar)
        }
    }
}
extension View { func mangaBakaNavigation() -> some View { modifier(MangaBakaNavigation()) } }

/// The two catalogs share a tab, not identities or tracking credentials.
struct MediaSectionPicker: View {
    @EnvironmentObject private var navigation: AppNavigationStore
    @AppStorage("app.mediaSection") private var mode = "anime"
    var body: some View {
        HStack(spacing: 3) {
            option("Anime", symbol: "play.rectangle", value: "anime")
            option("Manga & Novels", symbol: "book.closed", value: "written")
        }.padding(4).silverGlass(in: Capsule()).frame(maxWidth: 440)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("media-section-picker")
    }
    private func option(_ title: String, symbol: String, value: String) -> some View {
        Button {
            guard mode != value else { return }
            for state in [navigation.explore] {
                state.path = NavigationPath(); state.detailPath = NavigationPath()
                state.animeID = nil; state.column = .sidebar; state.visibility = .all
            }
            mode = value
        } label: {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity, minHeight: 44)
                .background(mode == value ? Theme.accent.opacity(0.12) : .clear, in: Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(mode == value ? .isSelected : [])
            .accessibilityIdentifier("media-section-" + value)
    }
}

struct MediaExploreView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var preferences: AppStore
    @EnvironmentObject private var reading: MangaBakaStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @State private var visitedCatalogs = Set<String>()
    @AppStorage("app.mediaSection") private var mode = "anime"
    @AppStorage(ExploreDesign.storageKey) private var designValue = ExploreDesign.classic.rawValue
    @State private var designs = false
    @State private var customizing = false
    @State private var accounts = false
    @State private var settings = false
    @State private var seasons = false
    @State private var filters = false
    @State private var display = false
    private var design: ExploreDesign { ExploreDesign(preference: designValue) }
    var body: some View {
        VStack(spacing: 0) {
            Group {
                if design != .classic { UnifiedExploreView(design: design, designs: $designs).id(design.rawValue) }
                else {
                    ZStack {
                        if mode == "anime" || visitedCatalogs.contains("anime") {
                            ExploreView(showSeasons: $seasons, showDisplay: $display, showDubFilters: $filters)
                                .opacity(mode == "anime" ? 1 : 0).allowsHitTesting(mode == "anime")
                                .accessibilityHidden(mode != "anime")
                                .environment(\.scenePhase, mode == "anime" ? scenePhase : .inactive)
                        }
                        if mode == "written" || visitedCatalogs.contains("written") {
                            MangaBakaExploreView()
                                .opacity(mode == "written" ? 1 : 0).allowsHitTesting(mode == "written")
                                .accessibilityHidden(mode != "written")
                                .environment(\.scenePhase, mode == "written" ? scenePhase : .inactive)
                        }
                    }.onAppear { visitedCatalogs.insert(mode) }
                        .onChange(of: mode) { _, value in visitedCatalogs.insert(value) }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
            if design == .classic { classicHeader }
        }.mangaBakaNavigation()
            .task(id: "\(design.rawValue)-\(preferences.mangaBakaContent.saved)", priority: .utility) {
                guard design == .classic else { return }
                do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
                await preferences.readingExplore.load(api: reading.api, contentFilter: preferences.mangaBakaContent)
            }
            .appAccountSwitcherSheet(isPresented: $accounts)
            .appSettingsSheet(isPresented: $settings)
            .navigationDestination(for: ExploreSearchRoute.self) { _ in
                UnifiedExploreSearchView().animeNavigation().mangaBakaNavigation()
            }
            .sheet(isPresented: $customizing) {
                AppNavigationStack {
                    ExploreCustomizationView(surface: mode == "written" ? .reading : .anime).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { customizing = false } } }
                }
            }
            .sheet(isPresented: $designs) {
                AppNavigationStack { ExploreDesignSettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { designs = false } } } }
            }
    }
    private var classicHeader: some View {
        HStack(spacing: 10) {
            AccountSwitcherButton().floatingHeaderGlass(in: Circle())
            Spacer()
            Button(action: switchMedia) {
                Image(systemName: mode == "anime" ? "book.closed" : "play.rectangle")
                    .font(.headline).frame(width: 44, height: 44).floatingHeaderGlass(in: Circle())
            }.buttonStyle(.plain)
                .accessibilityLabel(mode == "anime" ? "Switch to Manga & Novels" : "Switch to Anime")
                .accessibilityValue(mode == "anime" ? "Anime" : "Manga & Novels")
                .accessibilityIdentifier("explore-media-switch")
            Menu {
                NavigationLink(value: ExploreSearchRoute()) { Label("Search", systemImage: "magnifyingglass") }
                    .accessibilityIdentifier("explore-search")
                Button("Customize Explore", systemImage: "slider.horizontal.3") { customizing = true }
                Button("Settings", systemImage: "gearshape") { settings = true }
            } label: {
                Image(systemName: "ellipsis").font(.headline).frame(width: 44, height: 44).floatingHeaderGlass(in: Circle())
            }.accessibilityLabel("Explore options").accessibilityIdentifier("explore-customize")
        }.padding(.horizontal, 16).padding(.vertical, 6).frame(maxWidth: .infinity)
            .background(Color.clear)
    }
    private func switchMedia() {
        var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
        withTransaction(transaction) {
            let state = navigation.explore
            state.path = NavigationPath(); state.detailPath = NavigationPath()
            state.animeID = nil; state.column = .sidebar; state.visibility = .all
            mode = mode == "anime" ? "written" : "anime"
        }
    }

}

struct MediaLibraryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var navigation: AppNavigationStore
    @AppStorage("library.mediaSection") private var mode = "all"
    var body: some View {
        Group {
            if mode == "written" { MangaBakaLibraryView() }
            else if mode == "anime" { LibraryView() }
            else { CombinedLibraryView() }
        }.safeAreaInset(edge: .top, spacing: 0) {
            Picker("Library media", selection: $mode) {
                Text("All").tag("all")
                Text("Anime").tag("anime")
                Text("Manga & Novels").tag("written")
            }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 8)
                .accessibilityIdentifier("library-media-picker")
        }.background(Theme.background).mangaBakaNavigation()
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarLeading) { AccountSwitcherButton() } }
            .onChange(of: mode) { _, value in
                if let account = TrackingAccount.allCases.first(where: { $0.librarySection == value }) {
                    UserDefaults.standard.set(account.rawValue, forKey: TrackingAccount.storageKey)
                }
                let state = navigation.library
                state.path = NavigationPath(); state.detailPath = NavigationPath()
                state.animeID = nil; state.column = .sidebar; state.visibility = .all
            }
    }
}

struct MangaBakaCover: View {
    let series: MangaBakaSeries
    var width: CGFloat = 142
    var body: some View {
        ArtworkImage(url: series.coverURL, pointSize: width) { image in image.resizable().scaledToFill() } placeholder: {
            ZStack {
                LinearGradient(colors: [Color.teal.opacity(0.3), Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: series.type == "novel" ? "text.book.closed" : "book.closed").font(.largeTitle).foregroundStyle(.white.opacity(0.3))
            }
        }.frame(width: width, height: width * 1.45).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }
}

struct MangaBakaCard: View {
    let series: MangaBakaSeries
    var width: CGFloat = 142
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MangaBakaCover(series: series, width: width)
                .overlay(alignment: .bottomLeading) {
                    Text(series.formatLabel).font(.caption2.bold()).padding(.horizontal, 8).padding(.vertical, 5)
                        .background(.black.opacity(0.72), in: Capsule()).padding(7)
                }
            Text(series.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2).frame(minHeight: 40, alignment: .topLeading)
            if let rating = series.rating, rating > 0 {
                Label("\(rating, specifier: "%.0f")%", systemImage: "star.fill").font(.caption).foregroundStyle(.yellow)
            } else { Text(series.status.capitalized).font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 5) {
                if let year = series.year { Text(String(year)) }
                if let chapters = series.totalChapters { Text(chapters.formatted() + " ch.") }
            }.font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(series.status.capitalized + " · " + (series.contentRating?.capitalized ?? "Unrated"))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }.frame(width: width, alignment: .leading).contentShape(Rectangle())
    }
}

struct MangaBakaShelfView: View {
    let shelf: MangaBakaShelf
    let items: [MangaBakaSeries]
    var loading = false
    var error: String?
    var retry: (() -> Void)?
    var emptyMessage: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                NavigationLink(value: MangaBakaBrowseRoute(query: .init(shelf: shelf))) {
                    Text(shelf.label).font(.title2.bold())
                }.buttonStyle(.plain).accessibilityLabel("Open " + shelf.label + " list")
                Spacer()
                if shelf == .recommended {
                    if loading { ProgressView().controlSize(.small) }
                    else if let retry {
                        Button(action: retry) { Image(systemName: "arrow.clockwise").frame(width: 36, height: 36) }
                            .accessibilityLabel("Refresh manga recommendations")
                    }
                }
                NavigationLink(value: MangaBakaBrowseRoute(query: .init(shelf: shelf))) {
                    Label("See all", systemImage: "chevron.right").font(.subheadline).labelStyle(.titleAndIcon)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.padding(.horizontal, 20)
            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(items) { series in
                            NavigationLink(value: MangaBakaSeriesRoute(series: series)) { MangaBakaCard(series: series) }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 20)
                }
            } else if loading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(0..<5) { _ in RoundedRectangle(cornerRadius: 14).fill(Theme.surface).frame(width: 142, height: 300) }
                    }.padding(.horizontal, 20)
                }.disabled(true).accessibilityLabel("Loading " + shelf.label)
            } else if error == nil {
                Text(emptyMessage ?? "No titles match your content settings.")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 20)
                if shelf == .recommended {
                    Link("View recommendations on MangaBaka", destination: URL(string: "https://mangabaka.org/my/recommendations")!)
                        .font(.subheadline).padding(.horizontal, 20)
                }
            }
            if let error { NoticeView(message: error, action: retry).padding(.horizontal, 20) }
        }
    }
}

@MainActor
final class MangaBakaHomeModel: ObservableObject {
    static let shelves: [MangaBakaShelf] = [.trending, .rising, .hiddenGems, .popular, .topRated, .newReleases, .recentlyAdded]
    struct State {
        var items: [MangaBakaShelf: [MangaBakaSeries]] = [:]
        var errors: [MangaBakaShelf: String] = [:]
        var loading = Set<MangaBakaShelf>()
    }
    @Published private(set) var state = State()
    var items: [MangaBakaShelf: [MangaBakaSeries]] { state.items }
    var errors: [MangaBakaShelf: String] { state.errors }
    var loading: Set<MangaBakaShelf> { state.loading }
    private var generation = UUID()
    private var contentFilter: MangaBakaContentFilter?
    private var loadedAt: Date?
    private var flight: (id: UUID, filter: MangaBakaContentFilter, task: Task<Void, Never>)?
    func cancel() {
        generation = UUID(); flight?.task.cancel(); flight = nil
        state = State(); contentFilter = nil; loadedAt = nil
    }
    func load(api: MangaBakaClient, contentFilter: MangaBakaContentFilter, refresh: Bool = false, now: Date = Date()) async {
        guard !Task.isCancelled else { return }
        if !refresh, let pending = flight, pending.filter == contentFilter {
            await pending.task.value; return
        }
        if !refresh, self.contentFilter == contentFilter, errors.isEmpty,
           let loadedAt, now.timeIntervalSince(loadedAt) < 300 { return }
        flight?.task.cancel()
        let attempt = UUID()
        // The session owns the request. Disappearing UI may stop awaiting it,
        // but it must not leave a partially loaded shared catalog stuck forever.
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.fetch(api: api, contentFilter: contentFilter, refresh: refresh, now: now, attempt: attempt)
        }
        flight = (attempt, contentFilter, task)
        await task.value
        if flight?.id == attempt { flight = nil }
    }
    private func fetch(api: MangaBakaClient, contentFilter: MangaBakaContentFilter, refresh: Bool, now: Date, attempt: UUID) async {
        guard !Task.isCancelled else { return }
        let sameFilter = self.contentFilter == contentFilter
        generation = attempt
        if !sameFilter { state = State(); loadedAt = nil }
        self.contentFilter = contentFilter
        var initial = state; initial.loading = Set(Self.shelves); initial.errors = [:]; state = initial
        defer { if generation == attempt, !state.loading.isEmpty { var final = state; final.loading = []; state = final } }
        await withTaskGroup(of: (MangaBakaShelf, [MangaBakaSeries]?, String?).self) { group in
            for shelf in Self.shelves {
                group.addTask {
                    do {
                        let page = try await api.browse(.init(shelf: shelf), limit: 16, contentFilter: contentFilter, refresh: refresh)
                        return (shelf, page.items.filter { $0.isVisible(contentFilter: contentFilter) }, nil)
                    } catch { return (shelf, nil, error is CancellationError ? nil : error.localizedDescription) }
                }
            }
            for await (shelf, records, error) in group {
                guard generation == attempt, !Task.isCancelled else { continue }
                // One publication per completed rail, not three whole-page updates.
                var next = state
                if let records { next.items[shelf] = records }
                next.errors[shelf] = error; next.loading.remove(shelf); state = next
            }
        }
        guard generation == attempt, !Task.isCancelled, errors.isEmpty, Self.shelves.allSatisfy({ items[$0] != nil }) else { return }
        loadedAt = now
        // MangaBakaClient already persists public response bytes off-main.
        // This session keeps the decoded, filtered rows for instant revisits.
    }
}

/// The session owns the typed catalog snapshot; revisiting the page reuses it.
struct MangaBakaExploreView: View {
    var showsNavigationBar = false
    @EnvironmentObject private var preferences: AppStore
    var body: some View { MangaBakaExploreContent(showsNavigationBar: showsNavigationBar, model: preferences.readingExplore) }
}
private struct MangaBakaExploreContent: View {
    var showsNavigationBar = false
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var preferences: AppStore
    @State private var widgetRefreshID = 0
    @State private var customizing = false
    @ObservedObject var model: MangaBakaHomeModel
    init(showsNavigationBar: Bool, model: MangaBakaHomeModel) {
        self.showsNavigationBar = showsNavigationBar; self.model = model
    }
    @Environment(\.scenePhase) private var scenePhase
    private var allSeries: [MangaBakaSeries] {
        MangaBakaHomeModel.shelves.flatMap { model.items[$0] ?? [] }.filter { $0.isVisible(contentFilter: preferences.mangaBakaContent) }
    }
    var body: some View {
        ScrollView {
            // This is a bounded set of sections. Keep their layout alive while
            // scrolling; the long horizontal title rows still load cards lazily.
            VStack(alignment: .leading, spacing: 30) {
                header
                ExploreRows(surface: .reading, refreshID: widgetRefreshID, widgetInset: 20) { row in catalogRow(row) }
                MangaBakaAttribution().padding(.horizontal, 20)
            }.padding(.top, 14).padding(.bottom, 28).frame(maxWidth: 1180).frame(maxWidth: .infinity)
        }.background(Theme.background).toolbar(showsNavigationBar ? .visible : .hidden, for: .navigationBar)
            .modifier(ExploreWidgetSupport(surface: .reading, refreshID: widgetRefreshID))
            .sheet(isPresented: $customizing) {
                AppNavigationStack {
                    ExploreCustomizationView(surface: .reading).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { customizing = false } } }
                }
            }
            .toolbar {
                if showsNavigationBar {
                    ToolbarItem(placement: .topBarTrailing) { Button("Customize", systemImage: "slider.horizontal.3") { customizing = true } }
                }
            }
            .task(id: preferences.mangaBakaContent) { await model.load(api: account.api, contentFilter: preferences.mangaBakaContent) }
            .task(id: "\(account.connected)-\(account.connectionID)-\(preferences.mangaBakaContent)") {
                await account.loadRecommendations(contentFilter: preferences.mangaBakaContent)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await account.loadRecommendations(contentFilter: preferences.mangaBakaContent) } }
            }
            .task { await account.loadTaxonomy() }
            .refreshable {
                widgetRefreshID += 1
                async let catalog: Void = model.load(api: account.api, contentFilter: preferences.mangaBakaContent, refresh: true)
                async let personal: Void = account.loadRecommendations(contentFilter: preferences.mangaBakaContent, refresh: true)
                _ = await (catalog, personal)
            }
    }
    @ViewBuilder private func catalogRow(_ row: ExploreCatalogRow) -> some View {
        switch row {
        case .spotlight:
            VStack(spacing: 0) {
                if let featured = (model.items[.trending] ?? []).first(where: { $0.isVisible(contentFilter: preferences.mangaBakaContent) }) {
                    NavigationLink(value: MangaBakaSeriesRoute(series: featured)) { hero(featured) }.buttonStyle(.plain)
                } else { hero(nil).accessibilityLabel(model.loading.isEmpty ? "No spotlight titles available" : "Loading manga spotlight") }
            }.padding(.horizontal, 20).accessibilityElement(children: .contain).accessibilityIdentifier("reading-spotlight")
                .accessibilityValue((model.items[.trending] ?? []).isEmpty ? (model.loading.isEmpty ? "Empty" : "Loading") : "Ready")
        case .personal: if account.connected { MangaBakaPersonalShelf() }
        case .formats: formats
        case .genres: genres
        default:
            if let shelf = row.readingShelf {
                MangaBakaShelfView(shelf: shelf, items: (model.items[shelf] ?? []).filter { $0.isVisible(contentFilter: preferences.mangaBakaContent) },
                    loading: model.loading.contains(shelf), error: model.errors[shelf], retry: {
                        Task { await model.load(api: account.api, contentFilter: preferences.mangaBakaContent, refresh: true) }
                    })
            }
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("A story for every mood.").font(.largeTitle.bold())
            Text("Manga, manhwa, light novels & beyond.").foregroundStyle(.secondary)
            MangaBakaContentButton().font(.subheadline)
            NavigationLink(value: MangaBakaBrowseRoute(query: .init())) {
                HStack { Image(systemName: "magnifyingglass"); Text("Search MangaBaka"); Spacer(); Image(systemName: "slider.horizontal.3") }
                    .font(.subheadline).foregroundStyle(.secondary).padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 17))
            }.buttonStyle(.plain).accessibilityIdentifier("mangabaka-search")
        }.padding(.horizontal, 20)
    }
    private var genres: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink { MangaBakaTaxonomyView() } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Explore genres & tags").font(.title2.bold())
                        Text("Explore every genre, tag & content rating").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(); Image(systemName: "tag").font(.title2)
                }.padding(18).background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain).padding(.horizontal, 20)
            if !account.catalogGenres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 9) {
                        ForEach(account.catalogGenres.prefix(16)) { genre in
                            NavigationLink(value: MangaBakaBrowseRoute(query: .init(genres: [genre]))) {
                                Text(genre.label).font(.subheadline.weight(.medium)).padding(.horizontal, 15).padding(.vertical, 10)
                                    .background(.white.opacity(0.07), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 20)
                }
            }
        }
    }
    private func hero(_ series: MangaBakaSeries?) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Label("IN THE SPOTLIGHT", systemImage: "sparkles").font(.caption2.bold()).foregroundStyle(.mint)
                Text(series?.displayTitle ?? (model.loading.isEmpty ? "No spotlight titles available" : "Loading spotlight")).font(.title2.bold()).lineLimit(3, reservesSpace: true)
                    .redacted(reason: series == nil && !model.loading.isEmpty ? .placeholder : [])
                Text(series?.synopsis ?? (model.loading.isEmpty ? "Adjust your content settings or pull to refresh." : "Finding a story for you.")).font(.subheadline).foregroundStyle(.secondary).lineLimit(3, reservesSpace: true)
                    .redacted(reason: series == nil && !model.loading.isEmpty ? .placeholder : [])
                Label("Explore series", systemImage: "arrow.up.right").font(.subheadline.bold())
            }.frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if let series { MangaBakaCover(series: series, width: 112) }
                else { RoundedRectangle(cornerRadius: 14).fill(Theme.surface).frame(width: 112, height: 112 * 1.45) }
            }.rotationEffect(.degrees(5)).shadow(color: .black.opacity(0.3), radius: 14, y: 8)
        }.padding(22).background(LinearGradient(colors: [.teal.opacity(0.18), Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26)).overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.08)))
    }
    private var formats: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Explore by format").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
                ForEach(MangaBakaFormat.allCases, id: \.self) { format in
                    NavigationLink(value: MangaBakaBrowseRoute(query: .init(format: format))) {
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(colors: [tint(format).opacity(0.3), Theme.surface], startPoint: .topTrailing, endPoint: .bottomLeading)
                            if let art = allSeries.first(where: { $0.type == format.rawValue }) {
                                HStack { Spacer(); MangaBakaCover(series: art, width: 83).rotationEffect(.degrees(13)).offset(x: 8, y: 5).opacity(0.5) }
                            }
                            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(format.label).font(.headline); Image(systemName: "chevron.right").font(.caption.bold()) }
                                Text(format.detail).font(.caption2).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                            }.padding(14)
                        }.frame(height: 112).clipped().clipShape(RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                }
            }
        }.padding(.horizontal, 20)
    }
    private func tint(_ format: MangaBakaFormat) -> Color {
        switch format { case .manga: return .teal; case .novel: return .indigo; case .manhwa: return .pink
        case .manhua: return .orange; case .oel: return .blue; case .other: return .purple }
    }
}

struct MangaBakaPersonalShelf: View {
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var preferences: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MangaBakaShelfView(shelf: .recommended,
                items: account.recommendationState.items.filter { $0.isVisible(contentFilter: preferences.mangaBakaContent) },
                loading: account.recommendationState.loading, error: account.recommendationState.error, retry: {
                    Task { await account.loadRecommendations(contentFilter: preferences.mangaBakaContent, refresh: true) }
                }, emptyMessage: account.recommendationState.emptyMessage
            )
            Text("Refreshes weekly · Tap the refresh arrow for a new selection")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20)
            if let notice = account.recommendationCacheNotice {
                Text(notice).font(.caption).foregroundStyle(.orange).padding(.horizontal, 20)
            }
        }
    }
}

struct MangaBakaAttribution: View {
    var providers: [String] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Link("Catalog & tracking by MangaBaka ↗", destination: URL(string: "https://mangabaka.org/data/api")!)
            Text(providers.isEmpty ? "With metadata from AniList, Anime-Planet, Kitsu, MangaUpdates, MyAnimeList and Shikimori. Artwork belongs to its respective owners." : "Underlying metadata: " + providers.joined(separator: ", ") + ". Artwork belongs to its respective owners.")
            Text("MangaBaka-original data · CC BY-NC-SA 4.0")
        }.font(.caption2).foregroundStyle(.secondary)
    }
}
