import SwiftUI
import AnimeCore

@MainActor
final class MangaBrowseModel: ObservableObject {
    @Published var mangas: [SourceManga] = []
    @Published var loading = false
    @Published var hasNext = false
    @Published var error: String?
    private var page = 0
    private var generation = UUID()
    func load(_ source: MangaSourceReference, extensions: MangaExtensionStore, mode: String, query: String, reset: Bool) async {
        if reset { generation = UUID(); mangas = []; page = 0; hasNext = false }
        else if loading || !hasNext { return }
        let token = generation, next = page + 1
        loading = true; error = nil
        defer { if token == generation { loading = false } }
        do {
            let result = try await extensions.browse(extensionID: source.extensionID, sourceID: source.sourceID,
                mode: mode, query: query, page: next)
            try Task.checkCancellation()
            guard token == generation else { return }
            var seen = Set(mangas.map(\.url))
            mangas += result.mangas.filter { !$0.url.isEmpty && seen.insert($0.url).inserted }
            page = next; hasNext = result.hasNext
        } catch is CancellationError {} catch { if token == generation { self.error = error.localizedDescription } }
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
            .task(id: key) {
                guard showMature || !source.adult else { return }
                await reading.load()
                await reading.visit(source)
                await model.load(source, extensions: extensions, mode: mode, query: submitted, reset: true)
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
                if let error = model.error {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error).font(.subheadline).foregroundStyle(.secondary)
                        Button("Try again") { Task { await model.load(source, extensions: extensions, mode: mode, query: submitted, reset: model.mangas.isEmpty) } }
                            .buttonStyle(.bordered)
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(MangaStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 12)], spacing: 12) {
                    ForEach(Array(model.mangas.enumerated()), id: \.element.id) { index, manga in
                        let title = MangaTitleReference(source: source, manga: manga)
                        NavigationLink { MangaTitleDetailView(title: title) } label: {
                            MangaTitleCard(title: title, saved: reading.record(title.id)?.saved == true)
                        }.buttonStyle(.plain).accessibilityIdentifier("manga-title-\(index)")
                    }
                }
                if model.loading { ProgressView("Loading titles…").frame(maxWidth: .infinity).padding() }
                else if model.mangas.isEmpty && model.error == nil {
                    ContentUnavailableView("No titles found", systemImage: "magnifyingglass", description: Text("Try another search or browse Popular."))
                } else if model.hasNext && model.error == nil {
                    Button("Load more") { Task { await more() } }.frame(maxWidth: .infinity).padding()
                        .task { await more() }
                }
            }.padding(16)
        }.accessibilityIdentifier("manga-source-catalog")
            .refreshable { await model.load(source, extensions: extensions, mode: mode, query: submitted, reset: true) }
    }
    private func modeButton(_ label: String, icon: String, value: String) -> some View {
        Button { mode = value } label: {
            Label(label, systemImage: icon).font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 10)
                .background(mode == value ? MangaStyle.accent.opacity(0.22) : MangaStyle.surface, in: Capsule())
                .foregroundStyle(mode == value ? MangaStyle.accent : .white)
        }.buttonStyle(.plain)
    }
    private func more() async { await model.load(source, extensions: extensions, mode: mode, query: submitted, reset: false) }
}
