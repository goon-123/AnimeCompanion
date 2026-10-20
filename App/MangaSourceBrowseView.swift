import SwiftUI
import AnimeCore

@MainActor
protocol MangaCatalogLoading {
    func browse(extensionID: String, sourceID: String, mode: String, query: String, page: Int) async throws -> SourceMangaPage
}

@MainActor
final class MangaBrowseModel: ObservableObject {
    @Published private(set) var pagination = MangaCatalogPagination()
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    var mangas: [SourceManga] { pagination.mangas }
    var hasNext: Bool { pagination.continuation == .more }
    var stalled: Bool { pagination.continuation == .stalled }
    var paginationID: String { generation.uuidString + ":\(pagination.page)" }
    private var generation = UUID()
    private var selection = ""
    private func key(_ source: MangaSourceReference, _ mode: String, _ query: String) -> String {
        source.id + "\u{1f}" + mode + "\u{1f}" + query
    }
    func loadIfNeeded(_ source: MangaSourceReference, extensions: any MangaCatalogLoading, mode: String, query: String) async {
        guard selection != key(source, mode, query) || (pagination.page == 0 && !loading && error == nil) else { return }
        await load(source, extensions: extensions, mode: mode, query: query, reset: true)
    }
    func load(_ source: MangaSourceReference, extensions: any MangaCatalogLoading, mode: String, query: String, reset: Bool, automatic: Bool = false) async {
        if reset { generation = UUID(); selection = key(source, mode, query); pagination = MangaCatalogPagination() }
        else if loading || selection != key(source, mode, query) || pagination.continuation == .end || (automatic && (stalled || error != nil)) { return }
        let token = generation, next = pagination.page + 1
        loading = true; error = nil
        defer { if token == generation { loading = false } }
        do {
            let result = try await extensions.browse(extensionID: source.extensionID, sourceID: source.sourceID,
                mode: mode, query: query, page: next)
            try Task.checkCancellation()
            guard token == generation else { return }
            pagination.append(result)
        } catch is CancellationError {} catch {
            if token == generation && !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

struct MangaSourceBrowseView: View {
    @EnvironmentObject private var extensions: MangaExtensionStore
    @EnvironmentObject private var reading: MangaReadingStore
    @AppStorage("manga.showMatureSources") private var showMature = false
    let source: MangaSourceReference
    @StateObject private var model = MangaBrowseModel()
    @State private var mode = "popular"
    @State private var query = ""
    @State private var submitted = ""
    @State private var showSettings = false
    @State private var showWebsite = false
    init(source: MangaSourceReference, initialQuery: String = "") {
        self.source = source
        let text = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        _query = State(initialValue: text); _submitted = State(initialValue: text)
        _mode = State(initialValue: text.isEmpty ? "popular" : "search")
    }
    private var key: String { mode + "\u{1f}" + submitted }
    private var latest: Bool { extensions.installed(source.extensionID)?.sources.first { $0.id == source.sourceID }?.supportsLatest == true }
    var body: some View {
        Group {
            if source.adult && !showMature {
                ContentUnavailableView("Source collection hidden", systemImage: "eye.slash",
                    description: Text("This collection is hidden by your mature-source setting."))
            } else { catalog }
        }.background(Color.black).navigationTitle(source.name).navigationBarTitleDisplayMode(.large).tint(MangaStyle.accent)
            .searchable(text: $query, prompt: "Search this source")
            .onSubmit(of: .search) {
                submitted = query.trimmingCharacters(in: .whitespacesAndNewlines)
                mode = submitted.isEmpty ? "popular" : "search"
            }
            .onChange(of: query) { _, value in if value.isEmpty && mode == "search" { submitted = ""; mode = "popular" } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showWebsite = true } label: { Image(systemName: "globe") }
                        .accessibilityLabel("Source website session").accessibilityIdentifier("manga-source-website")
                        .disabled(source.adult && !showMature)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Source settings").accessibilityIdentifier("manga-source-settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                MangaSourceSettingsView(source: source) {
                    Task { await model.load(source, extensions: extensions, mode: mode, query: submitted, reset: true) }
                }
            }
            .sheet(isPresented: $showWebsite) {
                MangaSourceSessionView(source: source) {
                    Task { await model.load(source, extensions: extensions, mode: mode, query: submitted, reset: true) }
                }
            }
            .task(id: key) {
                guard showMature || !source.adult else { return }
                await reading.load()
                await reading.visit(source)
                await model.loadIfNeeded(source, extensions: extensions, mode: mode, query: submitted)
            }
    }
    private var catalog: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    modeButton("Popular", icon: "sparkles", value: "popular")
                    if latest { modeButton("Latest", icon: "clock", value: "latest") }
                    if !submitted.isEmpty { modeButton("Search", icon: "magnifyingglass", value: "search") }
                    Spacer(minLength: 0)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 12)], spacing: 12) {
                    ForEach(Array(model.mangas.enumerated()), id: \.element.id) { index, manga in
                        let title = MangaTitleReference(source: source, manga: manga)
                        NavigationLink { MangaTitleDetailView(title: title) } label: {
                            MangaTitleCard(title: title, saved: reading.record(title.id)?.saved == true)
                        }.buttonStyle(.plain).accessibilityIdentifier("manga-title-\(index)")
                    }
                }
                paginationFooter
            }.padding(16)
        }.accessibilityIdentifier("manga-source-catalog")
            .refreshable { await model.load(source, extensions: extensions, mode: mode, query: submitted, reset: true) }
    }
    /// The task belongs to a stable footer, not to the button that disappears
    /// when loading becomes true (which used to cancel every next-page request).
    private var paginationFooter: some View {
        VStack(spacing: 12) {
            if model.loading {
                ProgressView(model.mangas.isEmpty ? "Loading titles…" : "Loading more titles…")
                    .accessibilityIdentifier("manga-catalog-loading")
            } else if let error = model.error {
                Text(error).font(.subheadline).foregroundStyle(.secondary)
                Button("Try again") { Task { await model.load(source, extensions: extensions, mode: mode, query: submitted, reset: model.pagination.page == 0) } }
                    .buttonStyle(.bordered).accessibilityIdentifier("manga-catalog-retry")
                Button("Open website / verify") { showWebsite = true }.font(.subheadline)
            } else if model.stalled {
                Text("This source returned no new titles. Automatic loading is paused.")
                    .font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("manga-catalog-stalled")
                Button("Try next page") { Task { await more() } }.buttonStyle(.bordered)
                    .accessibilityIdentifier("manga-catalog-next-page")
            } else if model.mangas.isEmpty && model.pagination.page > 0 {
                ContentUnavailableView("No titles found", systemImage: "magnifyingglass", description: Text("Try another search or browse Popular."))
            } else if model.hasNext && model.pagination.page > 0 {
                Button("Load more") { Task { await more() } }.accessibilityIdentifier("manga-catalog-load-more")
            } else if !model.mangas.isEmpty {
                Text("You’re all caught up").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("manga-catalog-end")
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 20)
            .task(id: model.paginationID) {
                guard model.pagination.page > 0 else { return }
                await more(automatic: true)
            }
    }
    private func modeButton(_ label: String, icon: String, value: String) -> some View {
        Button { mode = value } label: {
            Label(label, systemImage: icon).font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 10)
                .background(mode == value ? MangaStyle.accent.opacity(0.22) : MangaStyle.surface, in: Capsule())
                .foregroundStyle(mode == value ? MangaStyle.accent : .white)
        }.buttonStyle(.plain)
    }
    private func more(automatic: Bool = false) async {
        await model.load(source, extensions: extensions, mode: mode, query: submitted, reset: false, automatic: automatic)
    }
}
