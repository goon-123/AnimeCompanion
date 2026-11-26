import SwiftUI
import AnimeCore

@MainActor
final class InstalledMangaSearchModel: ObservableObject {
    @Published private(set) var results: [String: SourceMangaPage] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var loading = Set<String>()
    @Published private(set) var queued = Set<String>()
    private var generation = UUID()
    func cancel() { generation = UUID(); loading = []; queued = []; results = [:]; errors = [:] }
    func search(_ query: String, sources: [MangaSourceReference], extensions: MangaExtensionStore) async {
        cancel()
        let token = generation
        guard !query.isEmpty, !sources.isEmpty else { return }
        queued = Set(sources.map(\.id))
        do { try await Task.sleep(for: .milliseconds(500)); try Task.checkCancellation() }
        catch { if generation == token { queued = [] }; return }
        await MangaBulkSearch.run(query: query, sources: sources, search: { source, text in
            try await extensions.browse(extensionID: source.extensionID, sourceID: source.sourceID, mode: "search", query: text, page: 1)
        }) { event in
            guard token == self.generation else { return }
            switch event {
            case .started(let source): self.queued.remove(source.id); self.loading.insert(source.id)
            case .results(let source, let page): self.loading.remove(source.id); self.results[source.id] = page
            case .failed(let source, let error): self.loading.remove(source.id); self.errors[source.id] = error
            }
        }
        if generation == token { loading = []; queued = [] }
    }
}

private struct InstalledSearchKey: Equatable {
    let query: String
    let versions: [String]
    let refresh: Int
    let localRefresh: Int
}

struct InstalledMangaSearchView: View {
    @EnvironmentObject private var extensions: MangaExtensionStore
    @EnvironmentObject private var preferences: AppStore
    @EnvironmentObject private var reading: MangaReadingStore
    @AppStorage(MangaBulkSearch.pinnedOnlyKey) private var pinnedOnly = false
    @StateObject private var model = InstalledMangaSearchModel()
    @State private var managing = false
    @State private var localRefresh = 0
    let query: String
    let compact: Bool
    let refresh: Int
    var linkingTo: MangaSourceLinkTarget? = nil
    let showAll: () -> Void
    private var search: String { String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)) }
    private var sources: [MangaSourceReference] {
        guard !extensions.loading, !reading.loading else { return [] }
        return MangaBulkSearch.sources(in: extensions.state.installations, allowMature: preferences.mangaBakaContent.allowsMatureSources,
            pinned: reading.state.pinnedSources, pinnedOnly: pinnedOnly)
    }
    private var key: InstalledSearchKey {
        .init(query: search, versions: sources.map { $0.id + ":" + (extensions.installed($0.extensionID)?.descriptor.sha256 ?? "") + ":" + extensions.imageVersion($0) }.sorted(), refresh: refresh, localRefresh: localRefresh)
    }
    private var pending: Int { model.loading.count + model.queued.count }
    private var preview: [MangaTitleReference] {
        var titles: [MangaTitleReference] = []
        for index in 0..<8 {
            for source in sources {
                if let list = model.results[source.id]?.mangas, list.indices.contains(index) {
                    titles.append(.init(source: source, manga: list[index]))
                    if titles.count == 10 { return titles }
                }
            }
        }
        return titles
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Installed sources", systemImage: "square.stack.3d.up").font(.headline)
                Spacer()
                if compact { Button("See all", action: showAll).font(.caption.bold()) }
                else {
                    Button { localRefresh += 1 } label: { Image(systemName: "arrow.clockwise").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Search sources again").disabled(search.isEmpty || sources.isEmpty)
                }
            }
            Toggle("Only pinned sources", isOn: $pinnedOnly).font(.subheadline)
                .disabled(reading.loading || reading.unreadable).accessibilityIdentifier("manga-search-pinned-only")
            if extensions.loading || reading.loading { ProgressView("Loading installed sources…") }
            else if extensions.unreadableState {
                Text("Saved sources could not be loaded. Reopen the app before changing them.").font(.caption).foregroundStyle(.orange)
            } else if sources.isEmpty {
                Text(pinnedOnly ? "No enabled pinned sources. Turn off this filter to search all installed sources." : "Install or enable a manga source to search here.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if pinnedOnly { Button("Search all installed sources") { pinnedOnly = false } }
                Button("Manage sources") { managing = true }.font(.subheadline)
            } else if search.isEmpty {
                Text("Search \(sources.count) \(pinnedOnly ? "pinned" : "enabled") sources at once. Results appear by source as they arrive.").font(.subheadline).foregroundStyle(.secondary)
            } else if compact {
                if !preview.isEmpty { posters(preview) }
                summary
                if !model.errors.isEmpty { Button("Some sources need attention · See all", action: showAll).font(.caption).foregroundStyle(.orange) }
                if preview.isEmpty && pending == 0 && model.errors.isEmpty { Text("No installed-source matches.").font(.caption).foregroundStyle(.secondary) }
            } else {
                summary
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(sources) { source in sourceResults(source) }
                }
            }
        }.padding(16).background(Theme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityIdentifier("unified-installed-manga-results")
            .task {
                async let installed: Void = extensions.load(refreshCatalog: false)
                async let saved: Void = reading.load()
                _ = await (installed, saved)
            }
            .task(id: key) { await model.search(search, sources: sources, extensions: extensions) }
            .onDisappear { model.cancel() }
            .sheet(isPresented: $managing) { MangaExtensionSheet() }
    }
    private var summary: some View {
        HStack(spacing: 8) {
            if pending > 0 { ProgressView().controlSize(.small) }
            Text(pending > 0 ? "\(max(0, sources.count - pending)) of \(sources.count) sources searched" : "\(sources.count) sources searched")
                .font(.caption).foregroundStyle(.secondary)
        }.accessibilityIdentifier("manga-search-progress")
    }
    private func sourceResults(_ source: MangaSourceReference) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                NavigationLink { MangaSourceBrowseView(source: source, initialQuery: search, linkingTo: linkingTo) } label: {
                    HStack(spacing: 8) {
                        Text(source.name).font(.headline).foregroundStyle(.primary)
                        Text(source.language.uppercased()).font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.right").foregroundStyle(MangaStyle.accent)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("All results from \(source.name), \(source.language.uppercased())")
                    .accessibilityIdentifier("manga-search-source-\(source.sourceID)")
                Button { Task { await reading.pin(source) } } label: {
                    Image(systemName: reading.state.pinnedSources.contains(source.id) ? "pin.fill" : "pin").frame(width: 44, height: 44)
                }.buttonStyle(.plain).foregroundStyle(MangaStyle.accent).disabled(reading.unreadable)
                    .accessibilityLabel((reading.state.pinnedSources.contains(source.id) ? "Unpin " : "Pin ") + source.name)
            }
            if model.loading.contains(source.id) { ProgressView("Searching…").font(.caption) }
            else if model.queued.contains(source.id) { Text("Waiting to search…").font(.caption).foregroundStyle(.secondary) }
            else if let error = model.errors[source.id] {
                Text(error).font(.caption).foregroundStyle(.orange)
                NavigationLink("Open source to retry or verify") { MangaSourceBrowseView(source: source, initialQuery: search, linkingTo: linkingTo) }.font(.caption)
            } else if let page = model.results[source.id] {
                if page.mangas.isEmpty { Text("No results found").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 12) }
                else { posters(Array(page.mangas.prefix(8)).map { .init(source: source, manga: $0) }) }
            }
        }.accessibilityIdentifier("manga-search-group-" + source.id)
    }
    private func posters(_ titles: [MangaTitleReference]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(titles) { title in
                    NavigationLink { MangaTitleDetailView(title: title, linkingTo: linkingTo) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            MangaCover(title: title, width: 120).frame(width: 120, height: 174).clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(title.manga.title).font(.caption.weight(.semibold)).lineLimit(2).foregroundStyle(.primary)
                            Text(title.source.name).font(.caption2).lineLimit(1).foregroundStyle(MangaStyle.accent)
                        }.frame(width: 120, alignment: .leading)
                    }.buttonStyle(.plain).accessibilityIdentifier("unified-source-title-" + title.source.sourceID + "-" + title.manga.url)
                }
            }
        }
    }
}
