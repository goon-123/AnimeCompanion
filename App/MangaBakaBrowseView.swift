import SwiftUI
import AnimeCore

private struct MBBrowseKey: Hashable { let query: MangaBakaQuery; let adult: Bool }

@MainActor
private final class MangaBakaBrowseModel: ObservableObject {
    @Published var items: [MangaBakaSeries] = []
    @Published var total: Int?
    @Published var hasMore = false
    @Published var loading = false
    @Published var error: String?
    private var key: MBBrowseKey?
    private var generation = UUID()
    private var page = 0
    func load(api: MangaBakaClient, key: MBBrowseKey, refresh: Bool = false, next: Bool = false) async {
        if self.key != key || refresh {
            generation = UUID(); loading = false; page = 0
            if self.key != key { items = []; total = nil; hasMore = false }
            self.key = key
        }
        guard !loading, !next || hasMore else { return }
        if !next && !refresh && page > 0 { return }
        let attempt = generation, requested = next ? page + 1 : 1
        loading = true; error = nil
        defer { if attempt == generation { loading = false } }
        do {
            let response = try await api.browse(key.query, page: requested, limit: key.query.shelf.isCurated ? 100 : 30,
                includeAdult: key.adult, refresh: refresh)
            try Task.checkCancellation()
            guard attempt == generation else { return }
            var known = Set(next ? items.map(\.id) : [])
            let additions = response.items.filter { known.insert($0.id).inserted }
            guard !next || !additions.isEmpty || !response.hasNext else { throw MangaBakaError.message("No new titles on this page. Pull to refresh the catalog.") }
            items = next ? items + additions : additions
            total = response.total; hasMore = response.hasNext; page = requested
        } catch is CancellationError {} catch { if attempt == generation { self.error = error.localizedDescription } }
    }
}

struct MangaBakaBrowseView: View {
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var preferences: AppStore
    let initial: MangaBakaQuery
    @State private var query: MangaBakaQuery
    @StateObject private var model = MangaBakaBrowseModel()
    @State private var showingFilters = false
    @AppStorage("mangabaka.browseLayout") private var layout = "grid"
    @Environment(\.dynamicTypeSize) private var textSize
    init(initial: MangaBakaQuery) { self.initial = initial; _query = State(initialValue: initial) }
    private var key: MBBrowseKey { .init(query: query, adult: preferences.includeAdult) }
    private var visible: [MangaBakaSeries] { model.items.filter { query.includes($0, includeAdult: preferences.includeAdult) } }
    private var title: String {
        query.publisher?.name ?? query.genres.first?.label ?? query.tags.first?.label ?? (query.contentRatings.count == 1 ? query.contentRatings.first?.label : nil) ?? query.format?.label ?? query.shelf.label
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    filters
                    if query.hasFacets {
                        Text(filterSummary).font(.caption).foregroundStyle(.mint).fixedSize(horizontal: false, vertical: true)
                    }
                    if let total = model.total {
                        Text("\(total.formatted()) catalog matches").font(.caption).foregroundStyle(.secondary)
                    } else if query.shelf.isCurated { Text("A curated selection from MangaBaka").font(.caption).foregroundStyle(.secondary) }
                    if let error = model.error { NoticeView(message: error) { Task { await load(refresh: !model.hasMore, next: model.hasMore) } } }
                    if visible.isEmpty && !model.loading && model.error == nil {
                        ContentUnavailableView.search(text: query.text)
                    }
                    let minimum: CGFloat = textSize.isAccessibilitySize ? 180 : 140
                    let available = max(140, min(1180, geometry.size.width) - 40)
                    let count = max(1, Int((available + 14) / (minimum + 14)))
                    let width = max(1, (available - CGFloat(count - 1) * 14) / CGFloat(count))
                    if layout == "list" {
                        LazyVStack(spacing: 14) {
                            ForEach(visible) { series in
                                NavigationLink(value: MangaBakaSeriesRoute(series: series)) { MangaBakaBrowseRow(series: series) }.buttonStyle(.plain)
                            }
                        }
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: count), alignment: .leading, spacing: 24) {
                            ForEach(visible) { series in
                                NavigationLink(value: MangaBakaSeriesRoute(series: series)) { MangaBakaCard(series: series, width: width) }.buttonStyle(.plain)
                            }
                        }
                    }
                    if model.loading { ProgressView("Loading stories…").frame(maxWidth: .infinity).padding() }
                    else if model.hasMore { Button("Load more titles") { Task { await load(next: true) } }.buttonStyle(.bordered).frame(maxWidth: .infinity) }
                    MangaBakaAttribution().padding(.top, 12)
                }.padding(20).frame(maxWidth: 1180).frame(maxWidth: .infinity)
            }.refreshable { await load(refresh: true) }
        }.background(Theme.background).navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query.text, prompt: "Search titles in every format")
            .sheet(isPresented: $showingFilters) { MangaBakaFilterSheet(query: $query) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingFilters = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Genres, tags and content ratings") } }
            .task(id: key) {
                do { if !query.text.isEmpty { try await Task.sleep(for: .milliseconds(400)) }; try Task.checkCancellation() }
                catch { return }
                await load()
            }
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { showingFilters = true } label: {
                    Label(query.filterCount > 0 ? "Filters (\(query.filterCount))" : "Genres, tags & ratings", systemImage: "slider.horizontal.3")
                }.buttonStyle(.bordered)
                Spacer(minLength: 6)
                Picker("Results layout", selection: $layout) {
                    Image(systemName: "square.grid.2x2").accessibilityLabel("Poster grid").tag("grid")
                    Image(systemName: "list.bullet.rectangle").accessibilityLabel("Detailed list").tag("list")
                }.pickerStyle(.segmented).frame(width: 100)
            }
            ViewThatFits(in: .horizontal) {
                HStack { formatPicker; sortPicker; statusPicker }
                VStack(alignment: .leading) { HStack { formatPicker; sortPicker }; statusPicker }
            }.buttonStyle(.bordered)
        }.font(.subheadline)
    }
    private var filterSummary: String {
        ((query.publisher.map { [$0.name] } ?? []) + query.genres.map(\.label) + query.tags.map(\.label) + query.excludedTags.map { "Exclude " + $0.label } +
         MangaBakaContentRating.allCases.filter { query.contentRatings.contains($0) }.map(\.label)).joined(separator: " · ")
    }
    private var formatPicker: some View {
        Menu {
            Button("Every format") { query.format = nil; regularQuery() }
            ForEach(MangaBakaFormat.allCases, id: \.self) { format in Button(format.label) { query.format = format; regularQuery() } }
        } label: { Label(query.format?.label ?? "All formats", systemImage: "books.vertical") }
    }
    private var sortPicker: some View {
        Menu {
            ForEach(MangaBakaShelf.allCases.filter { !$0.isCurated }, id: \.self) { shelf in Button(shelf.label) { query.shelf = shelf } }
        } label: { Label(query.text.isEmpty ? query.shelf.label : "Relevance", systemImage: "arrow.up.arrow.down") }
            .disabled(!query.text.isEmpty)
    }
    private var statusPicker: some View {
        Menu {
            Button("Any publication status") { query.status = nil; regularQuery() }
            ForEach(["releasing", "completed", "hiatus", "cancelled", "upcoming"], id: \.self) { status in
                Button(status.capitalized) { query.status = status; regularQuery() }
            }
        } label: { Label(query.status?.capitalized ?? "Any status", systemImage: "line.3.horizontal.decrease") }
    }
    private func regularQuery() { if query.shelf.isCurated { query.shelf = .popular } }
    private func load(refresh: Bool = false, next: Bool = false) async { await model.load(api: account.api, key: key, refresh: refresh, next: next) }
}
