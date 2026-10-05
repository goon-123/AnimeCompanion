import SwiftUI
import AnimeCore

struct DiscoveryBrowseView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @AppStorage("discovery.layout") private var layout = "list"
    @Environment(\.dynamicTypeSize) private var textSize
    private var posters = PosterPreferences(.explore)
    @State private var showDisplay = false
    let category: DiscoveryCategory
    let selection: SeasonSelection
    var titleOverride: String? = nil
    @State private var filters: DiscoveryFilters
    @State private var results: [Anime] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var loading = false
    @State private var loadingMore = false
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var loadedFilters: DiscoveryFilters?
    @FocusState private var searching: Bool

    init(category: DiscoveryCategory, selection: SeasonSelection = .current(), titleOverride: String? = nil) {
        self.category = category; self.selection = selection; self.titleOverride = titleOverride
        _filters = State(initialValue: DiscoveryFilters(category: category, selection: selection))
    }
    private var genres: [String] {
        ["Action", "Adventure", "Comedy", "Drama", "Fantasy", "Horror", "Mecha", "Music", "Mystery", "Psychological", "Romance", "Sci-Fi", "Slice of Life", "Sports", "Supernatural", "Thriller"]
    }
    private var formats: [(String, String)] {
        [("TV", "TV show"), ("TV_SHORT", "TV short"), ("MOVIE", "Movie"), ("OVA", "OVA"), ("ONA", "ONA"), ("SPECIAL", "Special"), ("MUSIC", "Music")]
    }
    private let statuses = [("RELEASING", "Releasing"), ("NOT_YET_RELEASED", "Not yet released"), ("FINISHED", "Finished"), ("HIATUS", "On hiatus"), ("CANCELLED", "Cancelled")]

    var body: some View {
        GeometryReader { geometry in
          let contentWidth = max(0, min(geometry.size.width, layout == "grid" ? 1280 : 1000) - 24)
          ScrollViewReader { scroll in
           ScrollView {
            // Keep controls mounted while the lazy results preserve their scroll layout.
            VStack(alignment: .leading, spacing: 16) {
                searchBar.id("discovery-top")
                filterBar.zIndex(1)
                HStack {
                    Menu {
                        MenuChoice(title: "List", selected: layout == "list") { layout = "list" }
                            .accessibilityIdentifier("discovery-layout-option-list")
                        MenuChoice(title: "Grid", selected: layout == "grid") { layout = "grid" }
                            .accessibilityIdentifier("discovery-layout-option-grid")
                    } label: { Label(layout == "grid" ? "Grid" : "List", systemImage: layout == "grid" ? "square.grid.2x2" : "list.bullet").font(.subheadline).padding(10).background(Theme.surface, in: Capsule()) }.accessibilityIdentifier("discovery-layout")
                    if layout == "grid" {
                        Menu {
                            ForEach(1...8, id: \.self) { count in
                                MenuChoice(title: "\(count) per row", selected: posters.preferredColumns == count) { posters.columns = count }
                                    .accessibilityIdentifier("discovery-column-option-\(count)")
                            }
                        } label: { Text("\(posters.preferredColumns) per row").font(.subheadline).padding(10).background(Theme.surface, in: Capsule()) }
                            .accessibilityIdentifier("discovery-columns")
                    }
                    Spacer()
                    Text("\(results.count) titles").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("discovery-count")
                }.zIndex(1)
                HStack {
                    Menu {
                        ForEach(DiscoverySort.allCases, id: \.self) { order in
                            MenuChoice(title: order.label, selected: filters.sort == order) { filters.sort = order }
                        }
                    } label: { Label(filters.sort.label, systemImage: "arrow.up.arrow.down").font(.subheadline).padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 9)) }
                        .accessibilityIdentifier("discovery-sort")
                    Spacer()
                    Button { filters = DiscoveryFilters(category: category, selection: selection) } label: { Image(systemName: "line.3.horizontal.decrease.circle").frame(width: 44, height: 44) }
                        .accessibilityLabel("Reset category filters")
                }.zIndex(1)
                if let error { NoticeView(message: error) { Task { await load(refresh: true) } } }
                if loading { ProgressView("Loading anime…").frame(maxWidth: .infinity).padding() }
                if layout == "grid", posters.fittingColumns(in: contentWidth, accessible: textSize.isAccessibilitySize) < posters.preferredColumns {
                    Text("This window fits \(posters.fittingColumns(in: contentWidth, accessible: textSize.isAccessibilitySize)) per row. Your saved choice is \(posters.preferredColumns).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if layout == "grid" {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: posters.fittingColumns(in: contentWidth, accessible: textSize.isAccessibilitySize)), alignment: .leading, spacing: 18) {
                        ForEach(results) { DiscoveryAnimeTile(anime: $0, posterWidth: posters.gridPosterWidth) }
                    }
                } else {
                    LazyVStack(spacing: 12) { ForEach(results) { DiscoveryAnimeRow(anime: $0, posterWidth: posters.listPosterWidth(in: contentWidth - 18)) } }
                }
                if hasMore {
                    Button { Task { await loadMore() } } label: {
                        if loadingMore { ProgressView() } else { Text("Load more titles").frame(maxWidth: .infinity) }
                    }.buttonStyle(.bordered).disabled(loading || loadingMore).accessibilityIdentifier("discovery-more")
                }
                if results.isEmpty && !loading && error == nil {
                    ContentUnavailableView("No matching titles", systemImage: "magnifyingglass", description: Text("Try changing the search or filters."))
                }
                DiscoveryDataNote()
            }.padding(12).readableContent(width: layout == "grid" ? 1280 : 1000)
           }.scrollDismissesKeyboard(.interactively)
               .accessibilityIdentifier("discovery-scroll")
               .onChange(of: filters) { _, _ in scroll.scrollTo("discovery-top", anchor: .top) }
          }
        }.background(Theme.background)
            .navigationTitle(titleOverride ?? category.label(season: selection)).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showDisplay = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Explore display options").accessibilityIdentifier("explore-display-options")
                }
            }
            .sheet(isPresented: $showDisplay) { DisplayOptionsView(scope: .explore) }
            .task(id: filters) { await load() }
            .task { await dubs.load(using: store.dubs) }
            .refreshable {
                async let metadata: Void = load(refresh: true)
                async let dubInfo: Void = dubs.load(using: store.dubs, refresh: true)
                _ = await (metadata, dubInfo)
            }
    }
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search this category", text: $filters.search).textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                .focused($searching).onSubmit { searching = false }.accessibilityIdentifier("discovery-search")
            if !filters.search.isEmpty { Button { filters.search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear category search") }
        }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
    }
    private func chip(_ label: String, selected: Bool) -> some View {
        Text(label).font(.subheadline.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 11)
            .foregroundStyle(selected ? Color.black : Color.white)
            .background(selected ? Color.white : Theme.surface, in: RoundedRectangle(cornerRadius: 9))
    }
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                Menu {
                    Button("All genres") { filters.genre = nil }
                    ForEach(genres, id: \.self) { genre in Button(genre) { filters.genre = genre } }
                } label: { chip(filters.genre ?? "Genre", selected: filters.genre != nil) }.accessibilityIdentifier("discovery-genre")
                Menu {
                    Button("All years") { filters.year = nil }
                    ForEach(Array((1970...SeasonSelection.current().year + 2).reversed()), id: \.self) { year in Button(String(year)) { filters.year = year } }
                } label: { chip(filters.year.map(String.init) ?? "Year", selected: filters.year != nil) }.accessibilityIdentifier("discovery-year")
                Menu {
                    Button("All seasons") { filters.season = nil }
                    ForEach(AnimeSeason.allCases, id: \.self) { season in Button(season.label) { filters.season = season } }
                } label: { chip(filters.season?.label ?? "Season", selected: filters.season != nil) }.accessibilityIdentifier("discovery-season")
                Menu {
                    Button("All formats") { filters.format = nil }
                    ForEach(formats, id: \.0) { format in Button(format.1) { filters.format = format.0 } }
                } label: { chip(formats.first { $0.0 == filters.format }?.1 ?? "Format", selected: filters.format != nil) }.accessibilityIdentifier("discovery-format")
                Menu {
                    Button("Any status") { filters.status = nil }
                    ForEach(statuses, id: \.0) { status in Button(status.1) { filters.status = status.0 } }
                } label: { chip(statuses.first { $0.0 == filters.status }?.1 ?? "Airing status", selected: filters.status != nil) }.accessibilityIdentifier("discovery-status")
            }
        }
    }
    private func load(refresh: Bool = false) async {
        // SwiftUI restarts this task after popping details. Keep the complete loaded
        // page, including appended titles, instead of collapsing its scroll content.
        guard !Task.isCancelled, refresh || loadedFilters != filters else { return }
        let attempt = UUID(); requestID = attempt; let selected = filters
        if loadedFilters != selected {
            results = []; loadedFilters = nil; page = 1; hasMore = false
        }
        loading = true; loadingMore = false; error = nil
        defer { if requestID == attempt { loading = false } }
        do {
            if !refresh && !selected.search.isEmpty { try await Task.sleep(for: .milliseconds(400)) }
            let response = try await store.aniList.browse(selected, refresh: refresh)
            try Task.checkCancellation(); guard requestID == attempt, filters == selected else { return }
            results = response.media ?? []; page = 1; hasMore = response.pageInfo?.hasNextPage == true
            loadedFilters = selected
        } catch is CancellationError {} catch { if !Task.isCancelled, requestID == attempt { self.error = error.localizedDescription } }
    }
    private func loadMore() async {
        guard !loading, !loadingMore, hasMore else { return }
        loadingMore = true; let attempt = requestID; let selected = filters; let nextPage = page + 1
        defer { if requestID == attempt { loadingMore = false } }
        do {
            let response = try await store.aniList.browse(selected, page: nextPage)
            try Task.checkCancellation(); guard requestID == attempt, filters == selected else { return }
            let ids = Set(results.map(\.id)); results += (response.media ?? []).filter { !ids.contains($0.id) }
            page = nextPage; hasMore = response.pageInfo?.hasNextPage == true
        } catch is CancellationError {} catch { if requestID == attempt { self.error = error.localizedDescription } }
    }
}

struct DiscoveryAnimeRow: View {
    let anime: Anime
    var posterWidth: CGFloat = 90
    var body: some View {
        NavigationLink(value: AnimeRoute(id: anime.id)) {
            HStack(alignment: .top, spacing: 12) {
                AnimeCover(anime: anime, width: posterWidth, cornerRadius: 6)
                VStack(alignment: .leading, spacing: 7) {
                    Text(anime.displayTitle).font(.headline).lineLimit(2)
                    Text(metadata).font(.caption).foregroundStyle(.secondary)
                    DiscoveryIndicators(anime: anime)
                    Text(anime.synopsis).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    HStack(spacing: 5) {
                        ForEach(Array((anime.genres ?? []).prefix(3)), id: \.self) { genre in
                            Text(genre).font(.caption2).lineLimit(1).padding(.horizontal, 6).padding(.vertical, 4).background(Theme.background, in: Capsule())
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(9).foregroundStyle(.primary).background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityIdentifier("discovery-entry-\(anime.id)")
    }
    private var metadata: String {
        var parts = [anime.format?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Anime"]
        if let episodes = anime.episodes { parts.append("\(episodes) episodes") }
        if let score = anime.averageScore { parts.append(String(format: "%.1f ★", Double(score) / 10)) }
        return parts.joined(separator: " · ")
    }
}

struct DiscoveryAnimeTile: View {
    let anime: Anime
    var posterWidth: CGFloat = 360
    var body: some View {
        NavigationLink(value: AnimeRoute(id: anime.id)) {
            VStack(alignment: .leading, spacing: 7) {
                GeometryReader { geometry in AnimeCover(anime: anime, width: geometry.size.width, cornerRadius: 8) }.aspectRatio(1 / 1.45, contentMode: .fit)
                Text(anime.displayTitle).font(.subheadline.bold()).lineLimit(2, reservesSpace: true)
                if let score = anime.averageScore { Text("AniList \(Double(score) / 10, specifier: "%.1f") ★").font(.caption).foregroundStyle(Theme.highlight) }
                DiscoveryIndicators(anime: anime)
                AnimeGenres(anime: anime).accessibilityIdentifier("explore-genres-\(anime.id)")
            }.foregroundStyle(.primary).frame(maxWidth: posterWidth, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("discovery-entry-\(anime.id)")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
