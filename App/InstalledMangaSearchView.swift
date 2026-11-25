import SwiftUI
import AnimeCore

private struct InstalledSearchOutcome: Sendable {
    let source: MangaSourceReference
    let page: SourceMangaPage?
    let error: String?
}

@MainActor
final class InstalledMangaSearchModel: ObservableObject {
    @Published private(set) var results: [String: SourceMangaPage] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var loading = Set<String>()
    private var generation = UUID()
    func cancel() { generation = UUID(); loading = []; results = [:]; errors = [:] }
    func search(_ query: String, sources: [MangaSourceReference], extensions: MangaExtensionStore) async {
        cancel()
        let token = generation
        guard !query.isEmpty, !sources.isEmpty else { return }
        loading = Set(sources.map(\.id))
        do { try await Task.sleep(for: .milliseconds(400)); try Task.checkCancellation() } catch { if generation == token { loading = [] }; return }
        await withTaskGroup(of: InstalledSearchOutcome.self) { group in
            var iterator = sources.makeIterator()
            for _ in 0..<2 { if let source = iterator.next() { group.addTask { await Self.fetch(source, query: query, extensions: extensions) } } }
            for await outcome in group {
                guard generation == token, !Task.isCancelled else { group.cancelAll(); return }
                loading.remove(outcome.source.id)
                if let page = outcome.page { results[outcome.source.id] = page }
                else { errors[outcome.source.id] = outcome.error }
                if let source = iterator.next() { group.addTask { await Self.fetch(source, query: query, extensions: extensions) } }
            }
        }
    }
    private static func fetch(_ source: MangaSourceReference, query: String, extensions: MangaExtensionStore) async -> InstalledSearchOutcome {
        do {
            try Task.checkCancellation()
            let page = try await extensions.browse(extensionID: source.extensionID, sourceID: source.sourceID, mode: "search", query: query, page: 1)
            try Task.checkCancellation()
            var seen = Set<String>()
            let titles = page.mangas.filter { !$0.url.isEmpty && seen.insert($0.url).inserted }
            return InstalledSearchOutcome(source: source, page: .init(mangas: titles, hasNext: page.hasNext), error: nil)
        } catch { return InstalledSearchOutcome(source: source, page: nil, error: error.localizedDescription) }
    }

}

private struct InstalledSearchKey: Equatable {
    let query: String
    let versions: [String]
    let refresh: Int
}

struct InstalledMangaSearchView: View {
    @EnvironmentObject private var extensions: MangaExtensionStore
    @EnvironmentObject private var preferences: AppStore
    @AppStorage(MangaSearchPreferences.storageKey) private var saved = ""
    @StateObject private var model = InstalledMangaSearchModel()
    @State private var choosing = false
    @State private var managing = false
    let query: String
    let compact: Bool
    let refresh: Int
    let showAll: () -> Void
    private var sources: [MangaSourceReference] {
        MangaSearchPreferences(saved: saved).sources(in: extensions.state.installations, allowMature: preferences.mangaBakaContent.allowsMatureSources)
    }
    private var key: InstalledSearchKey {
        .init(query: query, versions: sources.map { $0.id + ":" + (extensions.installed($0.extensionID)?.descriptor.sha256 ?? "") + ":" + extensions.imageVersion($0) }, refresh: refresh)
    }
    private var preview: [MangaTitleReference] {
        // Interleave sources so a large first result set does not hide the others.
        var titles: [MangaTitleReference] = []
        for index in 0..<8 {
            for source in sources {
                if let list = model.results[source.id]?.mangas, list.indices.contains(index) {
                    titles.append(.init(source: source, manga: list[index]))
                }
            }
        }
        return Array(titles.prefix(10))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Installed sources", systemImage: "square.stack.3d.up").font(.headline)
                Spacer()
                Button("Choose") { choosing = true }.font(.caption.bold()).accessibilityIdentifier("search-choose-manga-sources")
                if compact, !sources.isEmpty { Button("See all", action: showAll).font(.caption.bold()) }
            }
            if extensions.loading { ProgressView("Loading installed sources…") }
            else if extensions.unreadableState {
                Text("Saved sources could not be loaded. Reopen the app before changing them.").font(.caption).foregroundStyle(.orange)
            }
            else if sources.isEmpty {
                Text("Choose up to five installed sources to include in this search.").font(.caption).foregroundStyle(.secondary)
                Button("Manage sources") { managing = true }.font(.caption)
            } else if query.isEmpty {
                Text("Your search will include " + sources.map(\.name).joined(separator: ", ") + ".").font(.caption).foregroundStyle(.secondary)
            } else if compact {
                if !preview.isEmpty { posters(preview) }
                if !model.loading.isEmpty { ProgressView("Searching \(model.loading.count) sources…").font(.caption) }
                if !model.errors.isEmpty { Button("Some sources need attention · See sources", action: showAll).font(.caption).foregroundStyle(.orange) }
                if preview.isEmpty && model.loading.isEmpty && model.errors.isEmpty { Text("No installed-source matches.").font(.caption).foregroundStyle(.secondary) }
            } else {
                ForEach(sources) { source in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(source.name).font(.subheadline.bold())
                            Text(source.language.uppercased()).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            NavigationLink("More results") { MangaSourceBrowseView(source: source, initialQuery: query) }.font(.caption)
                        }
                        if model.loading.contains(source.id) { ProgressView("Searching…").font(.caption) }
                        if let error = model.errors[source.id] {
                            Text(error).font(.caption).foregroundStyle(.orange)
                            NavigationLink("Open this source / retry") { MangaSourceBrowseView(source: source, initialQuery: query) }.font(.caption)
                        } else if let page = model.results[source.id] {
                            if page.mangas.isEmpty { Text("No matches in this source.").font(.caption).foregroundStyle(.secondary) }
                            else { posters(Array(page.mangas.prefix(8)).map { .init(source: source, manga: $0) }) }
                        }
                    }.padding(.vertical, 6)
                }
            }
        }.padding(16).background(Theme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityIdentifier("unified-installed-manga-results")
            .task { await extensions.load(refreshCatalog: false) }
            .task(id: key) { await model.search(query, sources: sources, extensions: extensions) }
            .onDisappear { model.cancel() }
            .sheet(isPresented: $choosing) {
                MangaSearchSourcePicker(selected: MangaSearchPreferences(saved: saved).sourceIDs) { saved = MangaSearchPreferences(sourceIDs: $0).saved }
            }
            .sheet(isPresented: $managing) { MangaExtensionSheet() }
    }
    private func posters(_ titles: [MangaTitleReference]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(titles) { title in
                    NavigationLink { MangaTitleDetailView(title: title) } label: {
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

private struct MangaSearchSourcePicker: View {
    @EnvironmentObject private var extensions: MangaExtensionStore
    @EnvironmentObject private var preferences: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [String]
    @State private var query = ""
    let save: ([String]) -> Void
    init(selected: [String], save: @escaping ([String]) -> Void) { _selected = State(initialValue: selected); self.save = save }
    private var available: [MangaSourceReference] {
        extensions.state.installations.filter { $0.enabled && (preferences.mangaBakaContent.allowsMatureSources || !$0.descriptor.adult) }
            .flatMap { entry in entry.sources.map { MangaSourceReference(installation: entry, source: $0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        AppNavigationStack {
            List {
                Section {
                    ForEach(available.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.language.localizedCaseInsensitiveContains(query) }) { source in
                        Toggle(isOn: Binding(get: { selected.contains(source.id) }, set: { enabled in
                            selected.removeAll { $0 == source.id }
                            if enabled && selected.count < MangaSearchPreferences.limit { selected.append(source.id) }
                        })) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.name)
                                Text(source.language.uppercased()).font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(!selected.contains(source.id) && selected.count >= MangaSearchPreferences.limit)
                    }
                    if available.isEmpty { Text("Install or enable manga sources first.").foregroundStyle(.secondary) }
                } footer: { Text("\(selected.count) of 5 selected. Only these sources receive your query.") }
            }.navigationTitle("Search sources").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "Source name or language")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { save(selected); dismiss() } }
                }
                .onAppear { let ids = Set(available.map(\.id)); selected.removeAll { !ids.contains($0) } }
                .onChange(of: available.map(\.id)) { _, values in let ids = Set(values); selected.removeAll { !ids.contains($0) } }
        }.tint(MangaStyle.accent)
    }
}
