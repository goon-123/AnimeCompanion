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
    @Environment(\.dynamicTypeSize) private var textSize
    init(initial: MangaBakaQuery) { self.initial = initial; _query = State(initialValue: initial) }
    private var key: MBBrowseKey { .init(query: query, adult: preferences.includeAdult) }
    private var visible: [MangaBakaSeries] { model.items.filter { $0.isVisible(includeAdult: preferences.includeAdult) } }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    filters
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
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: count), alignment: .leading, spacing: 24) {
                        ForEach(visible) { series in
                            NavigationLink(value: MangaBakaSeriesRoute(series: series)) { MangaBakaCard(series: series, width: width) }.buttonStyle(.plain)
                        }
                    }
                    if model.loading { ProgressView("Loading stories…").frame(maxWidth: .infinity).padding() }
                    else if model.hasMore { Button("Load more titles") { Task { await load(next: true) } }.buttonStyle(.bordered).frame(maxWidth: .infinity) }
                    MangaBakaAttribution().padding(.top, 12)
                }.padding(20).frame(maxWidth: 1180).frame(maxWidth: .infinity)
            }.refreshable { await load(refresh: true) }
        }.background(Theme.background).navigationTitle(initial.format?.label ?? initial.shelf.label)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query.text, prompt: "Search titles in every format")
            .task(id: key) {
                do { if !query.text.isEmpty { try await Task.sleep(for: .milliseconds(400)) }; try Task.checkCancellation() }
                catch { return }
                await load()
            }
    }
    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            HStack { formatPicker; sortPicker; statusPicker }
            VStack(alignment: .leading) { HStack { formatPicker; sortPicker }; statusPicker }
        }.font(.subheadline).buttonStyle(.bordered)
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

struct MangaBakaDetailView: View {
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var preferences: AppStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @State var series: MangaBakaSeries
    @State private var error: String?
    @State private var editing = false
    @State private var signingIn = false
    @State private var expanding = false
    private var entry: MangaBakaLibraryEntry? { account.entries[series.id] }
    var body: some View {
        ScrollView {
            if series.isVisible(includeAdult: preferences.includeAdult) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    actions
                    if let notice = account.notice { Text(notice).font(.subheadline).foregroundStyle(.mint) }
                    if let error { NoticeView(message: error) { Task { await reload(refresh: true) } } }
                    if !series.synopsis.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("The story").font(.title2.bold())
                            Text(series.synopsis).font(.body).foregroundStyle(.secondary).lineLimit(expanding ? nil : 7)
                            Button(expanding ? "Show less" : "Read more") { expanding.toggle() }.font(.subheadline.bold())
                        }
                    }
                    metadata
                    if !series.genres.isEmpty {
                        Text(series.genres.map { $0.name.replacingOccurrences(of: "_", with: " ").capitalized }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if series.type == "novel" {
                        Label("Novel discovery & tracking", systemImage: "text.book.closed").font(.headline)
                        Text("MangaBaka provides information and progress tracking, not novel text. Use an official publisher or reading service for the book.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Button { navigation.openMangaSearch(titles: series.searchTitles) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "book.closed").font(.title2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Find a reading source").font(.headline)
                                    Text("Search your installed manga extensions").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: "arrow.right")
                            }.padding(18).background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Link(destination: series.websiteURL) { Label("View on MangaBaka", systemImage: "arrow.up.right.square") }
                        ForEach(Array(series.links.compactMap(MangaBakaSeries.publicURL).prefix(12).enumerated()), id: \.offset) { _, url in
                            Link(url.host ?? "Related site", destination: url).font(.subheadline)
                        }
                    }
                    MangaBakaAttribution(providers: series.providers)
                }.padding(20).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
            } else { ContentUnavailableView("Hidden by content settings", systemImage: "eye.slash") }
        }.background(Theme.background).navigationTitle("Series").navigationBarTitleDisplayMode(.inline)
            .task(id: account.connected) { await reload() }
            .refreshable { await reload(refresh: true) }
            .sheet(isPresented: $editing) { NavigationStack { MangaBakaTrackingView(series: series) } }
            .sheet(isPresented: $signingIn) { NavigationStack { MangaBakaAccountView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { signingIn = false } } } } }
    }
    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            MangaBakaCover(series: series, width: 118)
            VStack(alignment: .leading, spacing: 10) {
                Text(series.formatLabel.uppercased()).font(.caption.bold()).tracking(1.2).foregroundStyle(.mint)
                Text(series.displayTitle).font(.title2.bold()).textSelection(.enabled)
                if let year = series.year { Text(String(year)).foregroundStyle(.secondary) }
                Text(series.status.replacingOccurrences(of: "_", with: " ").capitalized).font(.subheadline).foregroundStyle(.secondary)
                if let rating = series.rating, rating > 0 { Label("\(rating, specifier: "%.0f")% · Community score", systemImage: "star.fill").font(.caption).foregroundStyle(.yellow) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var actions: some View {
        Button { if account.connected { editing = true } else { signingIn = true } } label: {
            HStack {
                Image(systemName: entry == nil ? "plus" : "checkmark.circle.fill")
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.map { MangaBakaReadingStatus(rawValue: $0.state)?.label ?? $0.state.capitalized } ?? "Add to My Library").font(.headline)
                    if let entry { Text("Chapter \(entry.chapter ?? 0, specifier: "%g") · Edit progress").font(.caption) }
                    else if !account.connected { Text("Connect your MangaBaka account").font(.caption) }
                }
                Spacer(); Image(systemName: "chevron.right")
            }.padding(18).foregroundStyle(.black).background(.white, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain)
    }
    private var metadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details").font(.title2.bold())
            if !series.authors.isEmpty { LabeledContent("Story", value: series.authors.joined(separator: ", ")) }
            if !series.artists.isEmpty { LabeledContent("Art", value: series.artists.joined(separator: ", ")) }
            if let chapters = series.totalChapters { LabeledContent("Chapters", value: chapters.formatted()) }
            if let volumes = series.finalVolume { LabeledContent("Volumes", value: volumes.formatted()) }
            if let rating = series.contentRating { LabeledContent("Content", value: rating.capitalized) }
        }.font(.subheadline)
    }
    private func reload(refresh: Bool = false) async {
        error = nil
        do { let loaded = try await account.api.details(id: series.id, refresh: refresh); try Task.checkCancellation(); series = loaded }
        catch is CancellationError { return } catch { self.error = error.localizedDescription }
        if account.connected {
            do { _ = try await account.loadEntry(series) } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}
