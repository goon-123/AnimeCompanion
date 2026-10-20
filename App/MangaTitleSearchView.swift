import SwiftUI
import AnimeCore

/// Choose a source before making a search request. Installing many extensions
/// must not silently fan a title out to hundreds of websites.
struct MangaTitleSearchView: View {
    @EnvironmentObject private var extensions: MangaExtensionStore
    @AppStorage("manga.showMatureSources") private var showMature = false
    let titles: [String]
    @State private var query: String
    @State private var language = "en"
    @State private var manage = false
    @FocusState private var editing: Bool
    init(titles: [String]) {
        self.titles = titles
        _query = State(initialValue: titles.first ?? "")
    }
    private var search: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var sources: [MangaSourceReference] {
        extensions.state.installations.filter { $0.enabled && (showMature || !$0.descriptor.adult) }
            .flatMap { entry in entry.sources.map { MangaSourceReference(installation: entry, source: $0) } }
            .filter { language.isEmpty || $0.language == language || $0.language == "all" }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        List {
            Section {
                Label("Find the story behind the anime", systemImage: "books.vertical").font(.headline)
                TextField("Series title", text: $query).submitLabel(.search).autocorrectionDisabled()
                    .focused($editing).onSubmit { editing = false }
                    .accessibilityIdentifier("manga-search-title")
                if titles.count > 1 {
                    ForEach(titles, id: \.self) { title in
                        Button { query = title } label: {
                            HStack { Text(title); Spacer(); if search == title { Image(systemName: "checkmark") } }
                        }.font(.subheadline)
                    }
                }
            } footer: { Text("Edit the title or try its original name. Availability varies by source; a matching adaptation is not guaranteed.") }
            Section {
                Picker("Language", selection: $language) {
                    Text("All languages").tag("")
                    ForEach(Array(Set(extensions.state.installations.flatMap(\.sources).map(\.language) + ["en"])).filter { $0 != "all" }.sorted(), id: \.self) {
                        Text(Locale.current.localizedString(forLanguageCode: $0) ?? $0.uppercased()).tag($0)
                    }
                }
                if extensions.loading { ProgressView("Loading sources…") }
                else if sources.isEmpty {
                    ContentUnavailableView {
                        Label("Choose a manga source", systemImage: "puzzlepiece.extension")
                    } description: { Text("Install or enable an extension, or try another language. Your search title will stay here.") }
                    actions: { Button("Manage extensions") { manage = true }.buttonStyle(.borderedProminent) }
                } else {
                    ForEach(sources) { source in
                        NavigationLink { MangaSourceBrowseView(source: source, initialQuery: search) } label: {
                            HStack(spacing: 12) {
                                if let entry = extensions.installed(source.extensionID)?.descriptor { MangaExtensionIcon(entry: entry) }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.name).font(.headline)
                                    Text(source.language == "all" ? "Multilingual" : source.language.uppercased())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "magnifyingglass").foregroundStyle(MangaStyle.accent)
                            }.padding(.vertical, 4)
                        }.disabled(search.isEmpty).accessibilityIdentifier("manga-search-source-\(source.sourceID)")
                    }
                }
            } header: { Text("Search in a source") } footer: { Text("Only the source you select receives your search. Read results vertically in the webtoon reader.") }
        }.scrollContentBackground(.hidden).background(Color.black).navigationTitle("Find manga")
            .navigationBarTitleDisplayMode(.inline).tint(MangaStyle.accent)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { manage = true } label: { Image(systemName: "puzzlepiece.extension") }
                        .accessibilityLabel("Manage manga extensions")
                }
            }
            .sheet(isPresented: $manage) { MangaExtensionSheet() }
            .task { await extensions.load() }
    }
}
