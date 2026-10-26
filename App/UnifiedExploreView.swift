import SwiftUI
import AnimeCore

@MainActor
final class UnifiedReadingCatalog: ObservableObject {
    enum Shelf: String, CaseIterable {
        case trending, novels, gems
        var query: MangaBakaQuery {
            switch self {
            case .trending: return .init(shelf: .trending)
            case .novels: return .init(shelf: .trending, format: .novel)
            case .gems: return .init(shelf: .hiddenGems)
            }
        }
    }
    @Published var items: [Shelf: [MangaBakaSeries]] = [:]
    @Published var errors: [Shelf: String] = [:]
    @Published var loading = Set<Shelf>()
    private var adult: Bool?
    private var generation = UUID()
    func load(api: MangaBakaClient, adult: Bool, refresh: Bool = false) async {
        guard !Task.isCancelled else { return }
        if self.adult != adult { items = [:]; errors = [:] }
        self.adult = adult
        let attempt = UUID(); generation = attempt; loading = Set(Shelf.allCases)
        defer { if generation == attempt { loading = [] } }
        await withTaskGroup(of: (Shelf, [MangaBakaSeries]?, String?).self) { group in
            for shelf in Shelf.allCases {
                group.addTask {
                    do {
                        let page = try await api.browse(shelf.query, limit: 16, includeAdult: adult, refresh: refresh)
                        return (shelf, page.items.filter { $0.isVisible(includeAdult: adult) }, nil)
                    } catch { return (shelf, nil, error is CancellationError ? nil : error.localizedDescription) }
                }
            }
            for await (shelf, values, error) in group {
                guard generation == attempt, !Task.isCancelled else { continue }
                if let values { items[shelf] = values }
                errors[shelf] = error; loading.remove(shelf)
            }
        }
    }
}

struct UnifiedExploreView: View {
    let design: ExploreDesign
    @EnvironmentObject private var anime: AppStore
    @EnvironmentObject private var reading: MangaBakaStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @EnvironmentObject private var filters: DiscoveryFilterStore
    @Environment(\.scenePhase) private var scene
    @Environment(\.dynamicTypeSize) private var textSize
    @StateObject private var catalog = ExploreCatalogModel()
    @StateObject private var books = UnifiedReadingCatalog()
    @State private var selection = SeasonSelection.current()
    @Binding var designs: Bool
    @State private var seasons = false
    @State private var dubFilters = false
    private var response: ExploreResponse? { catalog.state.response }
    private func visible(_ values: [Anime]) -> [Anime] {
        values.filter { anime.isVisible($0) && filters.includes($0, dubs: dubs, library: anime) }
    }
    private var trending: [ExploreStory] {
        ExploreStory.mix(anime: visible(response?.trending.media ?? []), reading: books.items[.trending] ?? [],
                         novels: books.items[.novels] ?? [], includeAdult: anime.includeAdult)
    }
    private var wall: [ExploreStory] {
        ExploreStory.mix(anime: visible((response?.trending.media ?? []) + (response?.seasonal.media ?? []) + (response?.upcoming.media ?? [])),
            reading: (books.items[.trending] ?? []) + (books.items[.gems] ?? []), novels: books.items[.novels] ?? [], includeAdult: anime.includeAdult)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                notices
                if design == .posterGrid {
                    catalogDirectory
                    HStack {
                        Text("A world of stories").font(.title2.bold())
                        Spacer()
                        Text("\(wall.count) discoveries").font(.caption).foregroundStyle(.secondary)
                    }
                    if wall.isEmpty && isLoading { loadingPosters }
                    ExploreStoryGrid(items: wall)
                    Text("A discovery selection from both catalogs. Browse a format above for its full catalog and filters.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    if !trending.isEmpty { spotlight }
                    else if isLoading { loadingPosters }
                    storyShelf("Trending across your world", subtitle: "Anime, comics & novels, together", items: Array(trending.prefix(18)))
                    catalogDirectory
                    animeShelf(.seasonal, title: "Watch this season", subtitle: selection.label, values: response?.seasonal.media ?? [])
                    readingShelf(.novels, title: "A little more imagination", subtitle: "Light novels & web novels")
                    readingShelf(.trending, title: "Your next read", subtitle: "Trending manga, manhwa & more")
                    if reading.connected { MangaBakaPersonalShelf().padding(.horizontal, -20) }
                    readingShelf(.gems, title: "Off the beaten path", subtitle: "MangaBaka's hidden gems")
                    animeShelf(.upcoming, title: "On the horizon", subtitle: "Upcoming anime", values: response?.upcoming.media ?? [])
                    animeShelf(.trending, title: "More anime to explore", subtitle: "Trending now", values: response?.trending.media ?? [])
                }
                if wall.isEmpty && !isLoading {
                    ContentUnavailableView("No discoveries to show", systemImage: "sparkles",
                        description: Text("Adjust your content or dub filters, or retry a catalog above."))
                }
                if let saved = catalog.state.savedAt {
                    Text("Anime catalog updated \(saved.formatted(.relative(presentation: .named)))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                DiscoveryDataNote()
                MangaBakaAttribution()
            }.padding(20).padding(.bottom, 20).frame(maxWidth: 1180).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Explore").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar).animeNavigation()
            .accessibilityIdentifier("unified-explore-" + design.rawValue)
            .sheet(isPresented: $seasons) { seasonPicker }
            .sheet(isPresented: $dubFilters) { DubFiltersView() }
            .task(id: "\(selection.label)-\(anime.includeAdult)") { await loadAnime() }
            .task(id: anime.includeAdult) { await books.load(api: reading.api, adult: anime.includeAdult) }
            .task { await dubs.load(using: anime.dubs) }
            .task(id: "\(reading.connected)-\(reading.connectionID)-\(anime.includeAdult)-\(scene)") {
                if scene == .active { await reading.loadRecommendations(includeAdult: anime.includeAdult) }
            }
            .refreshable {
                async let shows: Void = loadAnime(refresh: true)
                async let written: Void = books.load(api: reading.api, adult: anime.includeAdult, refresh: true)
                async let personal: Void = reading.loadRecommendations(includeAdult: anime.includeAdult, refresh: true)
                async let dub: Void = dubs.load(using: anime.dubs, refresh: true)
                _ = await (shows, written, personal, dub)
            }
    }
    private var isLoading: Bool { catalog.state.loading || !books.loading.isEmpty }
    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("EXPLORE", systemImage: "sparkles").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.mint)
                Spacer()
                Button { designs = true } label: { Image(systemName: design.symbol).frame(width: 44, height: 44).silverGlass(in: Circle()) }
                    .accessibilityLabel("Explore design").accessibilityIdentifier("explore-designs")
                AccountSwitcherButton()
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 7) {
                Text("Your next story.").font(.largeTitle.bold())
                Text("Anime, manga & novels. One place to discover.").font(.subheadline).foregroundStyle(.secondary)
            }
            NavigationLink(value: ExploreSearchRoute()) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.mint)
                    Text("Search anime, manga & novels").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.caption.bold()).foregroundStyle(.secondary)
                }.font(.subheadline).padding(17).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08)) }
            }.buttonStyle(.plain).accessibilityIdentifier("unified-explore-search")
        }
    }
    private var notices: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = catalog.state.error { NoticeView(message: "Anime: " + error) { Task { await loadAnime(refresh: true) } } }
            ForEach(UnifiedReadingCatalog.Shelf.allCases, id: \.self) { shelf in
                if let error = books.errors[shelf] {
                    NoticeView(message: (shelf == .novels ? "Novels: " : "Manga: ") + error) {
                        Task { await books.load(api: reading.api, adult: anime.includeAdult, refresh: true) }
                    }
                }
            }
            if filters.selection.isActive {
                Button { dubFilters = true } label: { Label("Anime dub filters active · Adjust", systemImage: "line.3.horizontal.decrease") }
                    .font(.caption).buttonStyle(.bordered)
                if dubs.loading { ProgressView("Checking English dubs…") }
                if dubs.unavailable { Text("Dub information is incomplete. Manga and novels remain available.").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private var spotlight: some View {
        TabView {
            ForEach(Array(trending.prefix(6))) { item in
                ExploreStoryLink(item: item) {
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("IN THE SPOTLIGHT").font(.caption2.bold()).tracking(1.5).foregroundStyle(.mint)
                            Text(item.title).font(.title2.bold()).lineLimit(3)
                            Text(item.format).font(.subheadline).foregroundStyle(.secondary)
                            Label("Explore story", systemImage: "arrow.up.right").font(.subheadline.bold())
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if !textSize.isAccessibilitySize {
                            ExploreStoryCover(item: item, width: 104).rotationEffect(.degrees(5)).shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                        }
                    }.padding(22).padding(.bottom, 20).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(LinearGradient(colors: [.teal.opacity(0.2), Theme.surface, .indigo.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(RoundedRectangle(cornerRadius: 26)).contentShape(RoundedRectangle(cornerRadius: 26))
                }
            }
        }.tabViewStyle(.page(indexDisplayMode: .automatic)).frame(height: textSize.isAccessibilitySize ? 420 : 280).accessibilityIdentifier("unified-spotlight")
    }
    private var catalogDirectory: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Go exploring").font(.title2.bold())
                Spacer()
                Menu {
                    Button("Browse anime seasons", systemImage: "calendar") { seasons = true }
                    Button("Anime dub filters", systemImage: "waveform") { dubFilters = true }
                    NavigationLink("Manga genres & tags") { MangaBakaTaxonomyView().toolbar(.visible, for: .navigationBar) }
                    NavigationLink("All manga discovery shelves") { MangaBakaExploreView(showsNavigationBar: true).navigationTitle("Manga & novels").navigationBarTitleDisplayMode(.inline) }
                } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                    .accessibilityLabel("Discovery tools").accessibilityIdentifier("unified-discovery-tools")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    NavigationLink(value: DiscoveryRoute(category: .trending, selection: selection)) { directoryTile("Anime", detail: "Find something to watch", symbol: "play.rectangle.fill", color: .indigo) }
                        .accessibilityIdentifier("unified-browse-anime")
                    ForEach(MangaBakaFormat.allCases, id: \.self) { format in
                        NavigationLink(value: MangaBakaBrowseRoute(query: .init(shelf: .trending, format: format))) {
                            directoryTile(format.label, detail: format.detail, symbol: format == .novel ? "text.book.closed.fill" : "book.closed.fill", color: format == .novel ? .purple : .teal)
                        }.accessibilityIdentifier("unified-browse-" + format.rawValue)
                    }
                }.padding(.vertical, 2)
            }.buttonStyle(.plain)
        }
    }
    private func directoryTile(_ title: String, detail: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.title2).foregroundStyle(color)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.padding(16).frame(width: 164, alignment: .leading).frame(minHeight: 125)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.2)) }
            .foregroundStyle(.primary).contentShape(RoundedRectangle(cornerRadius: 18))
    }
    private func shelfHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }.foregroundStyle(.primary)
    }
    private func storyShelf(_ title: String, subtitle: String, items: [ExploreStory], showHeading: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if showHeading { shelfHeading(title, subtitle: subtitle) }
            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(items) { item in ExploreStoryLink(item: item) { ExploreStoryCard(item: item).frame(width: 150) } }
                    }
                }
            } else if !isLoading { Text("No titles match your current settings.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func animeShelf(_ category: DiscoveryCategory, title: String, subtitle: String, values: [Anime]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: DiscoveryRoute(category: category, selection: selection)) {
                HStack {
                    shelfHeading(title, subtitle: subtitle)
                    Spacer()
                    Label("See all", systemImage: "chevron.right").font(.caption).foregroundStyle(.mint)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
            storyShelf(title, subtitle: subtitle, items: visible(values).map(ExploreStory.anime), showHeading: false)
        }
    }
    private func readingShelf(_ shelf: UnifiedReadingCatalog.Shelf, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: MangaBakaBrowseRoute(query: shelf.query)) {
                HStack {
                    shelfHeading(title, subtitle: subtitle)
                    Spacer()
                    Label("See all", systemImage: "chevron.right").font(.caption).foregroundStyle(.mint)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
            storyShelf(title, subtitle: subtitle, items: (books.items[shelf] ?? []).filter { $0.isVisible(includeAdult: anime.includeAdult) }.map(ExploreStory.reading), showHeading: false)
        }
    }
    private var loadingPosters: some View {
        HStack(spacing: 14) {
            ForEach(0..<2) { _ in RoundedRectangle(cornerRadius: 16).fill(Theme.surface).frame(maxWidth: .infinity).frame(height: 210) }
        }.overlay { ProgressView("Loading discoveries…") }.accessibilityIdentifier("unified-explore-loading")
    }
    private var seasonPicker: some View {
        NavigationStack {
            Form {
                Picker("Season", selection: $selection.season) { ForEach(AnimeSeason.allCases, id: \.self) { Text($0.label).tag($0) } }
                Picker("Year", selection: $selection.year) { ForEach(Array((1970...SeasonSelection.current().year + 2).reversed()), id: \.self) { Text(String($0)).tag($0) } }
                Button("Current season") { selection = .current(); seasons = false }
            }.navigationTitle("Browse seasons").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { seasons = false } } }
        }.presentationDetents([.medium])
    }
    private func loadAnime(refresh: Bool = false) async {
        await catalog.load(selection: selection, includeAdult: anime.includeAdult, api: anime.aniList, cache: anime.exploreCache, refresh: refresh)
    }
}

struct ExploreStoryLink<Content: View>: View {
    let item: ExploreStory
    @ViewBuilder let content: () -> Content
    var body: some View {
        Group {
            switch item {
            case .anime(let value): AnimeLink(id: value.id, label: content)
            case .reading(let value): NavigationLink(value: MangaBakaSeriesRoute(series: value), label: content)
            }
        }.buttonStyle(.plain).accessibilityIdentifier("explore-story-" + item.id)
    }
}

struct ExploreStoryCover: View {
    let item: ExploreStory
    let width: CGFloat
    var body: some View {
        Group {
            switch item {
            case .anime(let value): AnimeCover(anime: value, width: width)
            case .reading(let value): MangaBakaCover(series: value, width: width)
            }
        }.frame(width: width, height: width * 1.45).clipped().contentShape(Rectangle())
    }
}

struct ExploreStoryCard: View {
    let item: ExploreStory
    @EnvironmentObject private var reading: MangaBakaStore
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            GeometryReader { geometry in ExploreStoryCover(item: item, width: geometry.size.width) }
                .aspectRatio(1 / 1.45, contentMode: .fit)
                .overlay(alignment: .bottomLeading) { LibraryFormatBadge(title: item.format).padding(7) }
            Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2, reservesSpace: true)
            switch item {
            case .anime(let value): DiscoveryIndicators(anime: value)
            case .reading(let value):
                HStack(spacing: 6) {
                    if let score = value.rating { Label(score.formatted(.number.precision(.fractionLength(0))) + "%", systemImage: "star.fill").foregroundStyle(.yellow) }
                    if let entry = reading.library.first(where: { $0.id == value.id }) { Text(MangaBakaReadingStatus(rawValue: entry.state)?.label ?? entry.state.capitalized).foregroundStyle(.mint) }
                    else { Text(value.status.capitalized).foregroundStyle(.secondary) }
                }.font(.caption2).lineLimit(1)
            }
        }.frame(maxWidth: .infinity, alignment: .topLeading).foregroundStyle(.primary).contentShape(Rectangle())
    }
}

struct ExploreStoryGrid: View {
    let items: [ExploreStory]
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 220 : 140), spacing: 14, alignment: .topLeading)], alignment: .leading, spacing: 24) {
            ForEach(items) { item in ExploreStoryLink(item: item) { ExploreStoryCard(item: item) } }
        }.accessibilityIdentifier("explore-story-grid")
    }
}
