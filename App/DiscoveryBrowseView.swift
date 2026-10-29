import SwiftUI
import AnimeCore

private struct DiscoveryRequestKey: Hashable { let filters: DiscoveryFilters; let includeAdult: Bool }

struct DiscoveryBrowseView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @EnvironmentObject private var dubFilters: DiscoveryFilterStore
    @AppStorage("discovery.layout") private var layout = "list"
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.animeSplitPresentation) private var usesSplit
    private var posters = PosterPreferences(.explore)
    @State private var showDisplay = false
    @State private var showDubFilters = false
    let category: DiscoveryCategory
    let selection: SeasonSelection
    var titleOverride: String? = nil
    @State private var filters: DiscoveryFilters
    @State private var results: [Anime] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var loading = false
    @State private var loadingMore = false
    @State private var scanning = false
    @State private var scanID = UUID()
    @State private var error: String?
    @State private var paginationError: String?
    @State private var requestID = UUID()
    @State private var loadedFilters: DiscoveryFilters?
    @State private var loadedAdult: Bool?
    @State private var paginationVisible = false
    @State private var paginationPaused = false
    @State private var paginationScheduled = false
    @FocusState private var searching: Bool

    init(category: DiscoveryCategory, selection: SeasonSelection = .current(), titleOverride: String? = nil, initialGenre: String? = nil, initialQuery: String = "") {
        self.category = category; self.selection = selection; self.titleOverride = titleOverride
        var initial = initialGenre.map { DiscoveryFilters(genre: $0) } ?? DiscoveryFilters(category: category, selection: selection)
        initial.search = initialQuery
        _filters = State(initialValue: initial)
    }
    private var genres: [String] { DiscoveryGenres.all }
    private var formats: [(String, String)] {
        [("TV", "TV show"), ("TV_SHORT", "TV short"), ("MOVIE", "Movie"), ("OVA", "OVA"), ("ONA", "ONA"), ("SPECIAL", "Special"), ("MUSIC", "Music")]
    }
    private let statuses = [("RELEASING", "Releasing"), ("NOT_YET_RELEASED", "Not yet released"), ("FINISHED", "Finished"), ("HIATUS", "On hiatus"), ("CANCELLED", "Cancelled")]
    private var queryFilters: DiscoveryFilters {
        var query = filters; query.minimumScore = dubFilters.selection.minimumScore; return query
    }
    private var visibleResults: [Anime] { results.filter { store.isVisible($0) && dubFilters.includes($0, dubs: dubs, library: store) } }
    private var locallyFiltered: Bool { dubFilters.selection.dub != .all || dubFilters.selection.hideCompleted }
    private var coverage: DiscoveryCoverage {
        DiscoveryCoverage(loaded: loadedFilters == queryFilters && loadedAdult == store.includeAdult,
                          loading: loading, scanning: scanning || loadingMore, hasMore: hasMore,
                          requiresDubs: dubFilters.selection.dub != .all, dubsLoaded: dubs.loaded, dubsUnavailable: dubs.unavailable)
    }

    var body: some View {
        GeometryReader { geometry in
          let contentWidth = max(0, min(geometry.size.width, layout == "grid" ? 1280 : 1000) - 24)
          ScrollViewReader { scroll in
           ScrollView {
            // Keep controls mounted while the lazy results preserve their scroll layout.
            VStack(alignment: .leading, spacing: 16) {
                searchBar.id("discovery-top")
                DubFilterButton { showDubFilters = true }
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
                    Text(dubFilters.selection.isActive ? "\(visibleResults.count) matches · \(results.count) loaded" : "\(results.count) titles").font(.caption).foregroundStyle(.secondary)
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
                if loading { ProgressView(results.isEmpty ? "Loading anime…" : "Refreshing anime…").frame(maxWidth: .infinity).padding() }
                if coverage == .checkingDubs {
                    ProgressView("Checking English dubs…").frame(maxWidth: .infinity).padding()
                }
                if coverage == .unavailableDubs {
                    NoticeView(message: "Some dub information is unavailable. Matches may be incomplete; previously loaded information is still shown.") {
                        Task { await dubs.load(using: store.dubs, refresh: true); await fillFilteredPages() }
                    }.accessibilityIdentifier("discovery-dub-unavailable")
                    Button("Browse all anime") { dubFilters.selection.dub = .all }.buttonStyle(.bordered)
                }
                if locallyFiltered && hasMore {
                    Text("\(visibleResults.count) matches in \(results.count) checked titles · More titles remain")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("discovery-partial-results")
                }
                if layout == "grid", posters.fittingColumns(in: contentWidth, accessible: textSize.isAccessibilitySize, split: usesSplit) < posters.preferredColumns {
                    Text("This window fits \(posters.fittingColumns(in: contentWidth, accessible: textSize.isAccessibilitySize, split: usesSplit)) per row. Your saved choice is \(posters.preferredColumns).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if layout == "list", posters.listPosterWidth(in: contentWidth - 18) < posters.listWidth - 1 {
                    Text("Covers fit this pane at \(Int(posters.listPosterWidth(in: contentWidth - 18))) pt. Your saved width is \(Int(posters.listWidth)) pt.")
                        .font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("explore-list-size-constrained")
                }
                if layout == "grid" {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: posters.fittingColumns(in: contentWidth, accessible: textSize.isAccessibilitySize, split: usesSplit)), alignment: .leading, spacing: 18) {
                        ForEach(visibleResults) { DiscoveryAnimeTile(anime: $0, posterWidth: posters.gridPosterWidth) }
                    }
                } else {
                    LazyVStack(spacing: 12) { ForEach(visibleResults) { DiscoveryAnimeRow(anime: $0, posterWidth: posters.listPosterWidth(in: contentWidth - 18)) } }
                }
                if let paginationError { NoticeView(message: paginationError) { Task { await continueBrowsing() } } }
                if hasMore {
                    Group {
                        if loadingMore || scanning { ProgressView("Checking more titles…") }
                        else if paginationError == nil { Text("Keep scrolling for more anime").font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("discovery-pagination")
                }
                if visibleResults.isEmpty && error == nil && paginationError == nil, let title = coverage.emptyTitle {
                    ContentUnavailableView(title, systemImage: "magnifyingglass", description: Text(coverage.emptyMessage ?? ""))
                        .accessibilityIdentifier("discovery-empty-state")
                    if dubFilters.selection.isActive { Button("Reset dub filters") { dubFilters.selection = DiscoveryPreferences() }.buttonStyle(.bordered) }
                }
                DiscoveryDataNote()
            }.padding(12).readableContent(width: layout == "grid" ? 1280 : 1000)
                .background {
                    DiscoveryScrollObserver { nearEnd, userContinued in
                        if paginationVisible != nearEnd { paginationVisible = nearEnd }
                        if userContinued { paginationPaused = false }
                        if nearEnd { automaticallyContinue() }
                    }.frame(width: 0, height: 0)
                }
           }.scrollDismissesKeyboard(.interactively)
               .accessibilityIdentifier("discovery-scroll")
               .onChange(of: loading) { _, busy in if !busy { automaticallyContinue() } }
               .onChange(of: filters) { _, _ in scroll.scrollTo("discovery-top", anchor: .top) }
               .onChange(of: dubFilters.selection) { _, _ in paginationPaused = false; scroll.scrollTo("discovery-top", anchor: .top) }
          }
        }.background(Theme.background)
            .navigationTitle(titleOverride ?? category.label(season: selection)).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showDubFilters = true } label: { Image(systemName: "line.3.horizontal.decrease") }
                        .accessibilityLabel("Dub filters").accessibilityIdentifier("explore-dub-filter-toolbar")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showDisplay = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Explore display options").accessibilityIdentifier("explore-display-options")
                }
            }
            .sheet(isPresented: $showDisplay) { DisplayOptionsView(scope: .explore) }
            .sheet(isPresented: $showDubFilters) { DubFiltersView() }
            .task(id: DiscoveryRequestKey(filters: queryFilters, includeAdult: store.includeAdult)) { await load(); await fillFilteredPages() }
            .task(id: dubFilters.selection) { await dubs.load(using: store.dubs); await fillFilteredPages() }
            .task(id: dubs.revision) { await fillFilteredPages() }
            .refreshable {
                async let metadata: Void = load(refresh: true)
                async let dubInfo: Void = dubs.load(using: store.dubs, refresh: true)
                _ = await (metadata, dubInfo)
                await fillFilteredPages()
            }
    }
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search this category", text: $filters.search).textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
                .focused($searching).onSubmit { searching = false }.accessibilityIdentifier("discovery-search")
            if !filters.search.isEmpty { Button { filters.search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear category search") }
        }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle()).onTapGesture { searching = true }
    }
    private func chip(_ label: String, selected: Bool) -> some View {
        Text(label).font(.subheadline.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 11)
            .foregroundStyle(selected ? Theme.accent : Color.secondary)
            .background(selected ? Theme.accent.opacity(0.12) : Theme.surface, in: RoundedRectangle(cornerRadius: 9))
    }
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                Menu {
                    Button("All genres") { filters.genre = nil }.accessibilityIdentifier("discovery-genre-option-all")
                    ForEach(genres, id: \.self) { genre in
                        Button(genre) { filters.genre = genre }.accessibilityIdentifier("discovery-genre-option-\(genre)")
                    }
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
        let requestedAdult = store.includeAdult
        guard !Task.isCancelled, refresh || loadedFilters != queryFilters || loadedAdult != requestedAdult else { return }
        let attempt = UUID(); requestID = attempt; let selected = queryFilters
        if loadedFilters != selected || loadedAdult != requestedAdult {
            results = []; loadedFilters = nil; page = 1; hasMore = false
        }
        scanID = UUID(); scanning = false; paginationPaused = false
        loading = true; loadingMore = false; error = nil; paginationError = nil
        defer { if requestID == attempt { loading = false } }
        do {
            if !refresh && !selected.search.isEmpty { try await Task.sleep(for: .milliseconds(400)) }
            let response = try await store.aniList.browse(selected, refresh: refresh, includeAdult: requestedAdult)
            try Task.checkCancellation(); guard requestID == attempt, queryFilters == selected, store.includeAdult == requestedAdult else { return }
            results = response.media ?? []; page = 1; hasMore = response.pageInfo?.hasNextPage == true
            loadedFilters = selected
            loadedAdult = requestedAdult
        } catch is CancellationError {} catch { if !Task.isCancelled, requestID == attempt { self.error = error.localizedDescription } }
    }
    private func loadMore() async {
        guard !Task.isCancelled, !loading, !loadingMore, hasMore, loadedFilters == queryFilters, loadedAdult == store.includeAdult else { return }
        loadingMore = true; let attempt = requestID; let selected = queryFilters; let nextPage = page + 1; let requestedAdult = store.includeAdult
        paginationError = nil
        defer { if requestID == attempt { loadingMore = false } }
        do {
            let response = try await store.aniList.browse(selected, page: nextPage, includeAdult: requestedAdult)
            try Task.checkCancellation(); guard requestID == attempt, queryFilters == selected, store.includeAdult == requestedAdult else { return }
            var ids = Set(results.map(\.id)); results += (response.media ?? []).filter { ids.insert($0.id).inserted }
            page = nextPage; hasMore = response.pageInfo?.hasNextPage == true
        } catch is CancellationError {} catch { if !Task.isCancelled, requestID == attempt { paginationError = error.localizedDescription } }
    }
    private func continueBrowsing() async {
        let attempt = requestID, previousPage = page, previousMatches = visibleResults.count
        if locallyFiltered { await fillFilteredPages(force: true) }
        else { await loadMore() }
        if requestID == attempt, page > previousPage {
            paginationPaused = DiscoveryPaginationPolicy.shouldPause(previousMatches: previousMatches, currentMatches: visibleResults.count)
        }
    }
    private func automaticallyContinue() {
        guard paginationVisible, !paginationPaused, !paginationScheduled, hasMore, !loading, !loadingMore, !scanning,
              dubFilters.selection.dub == .all || dubs.loaded,
              error == nil, paginationError == nil, loadedFilters == queryFilters, loadedAdult == store.includeAdult else { return }
        paginationScheduled = true
        Task { defer { paginationScheduled = false }; await continueBrowsing() }
    }
    private func fillFilteredPages(force: Bool = false) async {
        guard locallyFiltered, (dubFilters.selection.dub == .all || dubs.loaded), loadedFilters == queryFilters,
              loadedAdult == store.includeAdult, !loading, !loadingMore, !scanning else { return }
        let choice = dubFilters.selection, attempt = requestID, scan = UUID()
        let previousMatches = visibleResults.count
        var scanned = 0
        scanID = scan; scanning = true
        defer {
            if scanID == scan {
                if scanned > 0 {
                    paginationPaused = DiscoveryPaginationPolicy.shouldPause(previousMatches: previousMatches, currentMatches: visibleResults.count)
                }
                scanning = false
                // A new local filter can arrive while the previous scan is being cancelled.
                if choice != dubFilters.selection { Task { await fillFilteredPages() } }
            }
        }
        let target = force ? visibleResults.count + DiscoveryScanPolicy.targetMatches : DiscoveryScanPolicy.targetMatches
        if force { paginationError = nil }
        while DiscoveryScanPolicy.shouldContinue(matches: visibleResults.count, hasMore: hasMore, pagesScanned: scanned, target: target) {
            guard !Task.isCancelled, requestID == attempt, scanID == scan, dubFilters.selection == choice,
                  error == nil, paginationError == nil else { return }
            let previousPage = page
            await loadMore()
            guard page > previousPage else { return }
            scanned += 1
        }
    }
}

struct DiscoveryAnimeRow: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .caption) private var genreHeight: CGFloat = 44
    let anime: Anime
    var posterWidth: CGFloat = 128
    private var coverWidth: CGFloat { textSize.isAccessibilitySize ? min(posterWidth, 100) : posterWidth }
    var body: some View {
      ZStack(alignment: .bottomTrailing) {
        AnimeLink(id: anime.id) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(anime.displayTitle).font(.headline).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                    DiscoveryLibraryBadge(anime: anime)
                    if !(anime.genres ?? []).isEmpty { Color.clear.frame(height: genreHeight) }
                }.foregroundStyle(.primary).padding(14)
                    .frame(maxWidth: .infinity, minHeight: coverWidth * 1.45, alignment: .topLeading)
                    .padding(.leading, coverWidth)
                    .overlay(alignment: .leading) {
                        AnimePoster(anime: anime, cornerRadius: 0, artworkIdentifierPrefix: "discovery").frame(width: coverWidth)
                    }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("discovery-entry-\(anime.id)")
        AnimeGenres(anime: anime).accessibilityIdentifier("explore-genres-\(anime.id)")
            .padding(.leading, coverWidth + 14).padding(.trailing, 14).padding(.bottom, 14)
      }.background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(Theme.border, lineWidth: 1).allowsHitTesting(false) }
    }
}

struct DiscoveryAnimeTile: View {
    let anime: Anime
    var posterWidth: CGFloat = 360
    var body: some View {
      VStack(alignment: .leading, spacing: 4) {
        AnimeLink(id: anime.id) {
            VStack(alignment: .leading, spacing: 7) {
                AnimePoster(anime: anime, cornerRadius: 8).aspectRatio(1 / 1.45, contentMode: .fit)
                Text(anime.displayTitle).font(.subheadline.bold()).lineLimit(2, reservesSpace: true)
                DiscoveryLibraryBadge(anime: anime)
            }.foregroundStyle(.primary).frame(maxWidth: posterWidth, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("discovery-entry-\(anime.id)")
        AnimeGenres(anime: anime).accessibilityIdentifier("explore-genres-\(anime.id)")
      }.frame(maxWidth: posterWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
