import SwiftUI
import AnimeCore

struct MangaExtensionsView: View {
    @StateObject private var store = MangaExtensionStore()
    @AppStorage("manga.showMatureSources") private var showMature = false
    @State private var repositoryLink = "https://keiyoushi.github.io"
    @State private var query = ""
    @State private var language = "en"
    @State private var showInstalled = false
    @State private var removingRepository = false
    private var languages: [String] {
        Array(Set((store.catalog?.extensions.flatMap(\.sources) ?? []).map(\.language))).filter { $0 != "all" }.sorted()
    }
    private var available: [MangaExtensionDescriptor] {
        (store.catalog?.extensions ?? []).filter { $0.matches(query: query, language: language, includeAdult: showMature) }
    }
    private var installed: [InstalledMangaExtension] {
        store.state.installations.filter { $0.descriptor.matches(query: query, language: language, includeAdult: showMature) }
            .sorted { $0.descriptor.name.localizedStandardCompare($1.descriptor.name) == .orderedAscending }
    }
    var body: some View {
        List {
            Section {
                Label("Runs on this device", systemImage: "iphone.gen3").foregroundStyle(.mint)
                Text("Install manga and manhwa sources from Keiyoushi, then browse them here. The page reader is the next stage.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Source compatibility is experimental. Some extensions need additional runtime support.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Repository") {
                if store.state.repositoryAdded {
                    LabeledContent("Keiyoushi", value: "\(store.catalog?.extensions.count ?? 0) extensions")
                    if let date = store.lastRefresh {
                        LabeledContent("Last checked") { Text(date, style: .relative).font(.caption).foregroundStyle(.secondary) }
                    }
                    Button { Task { await store.refresh() } } label: {
                        HStack { Label("Check for updates", systemImage: "arrow.clockwise"); if store.refreshing { Spacer(); ProgressView() } }
                    }.disabled(store.busy).accessibilityIdentifier("manga-refresh")
                } else {
                    TextField("Repository link", text: $repositoryLink).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .accessibilityIdentifier("manga-repository-link")
                    Button { Task { await store.refresh(link: repositoryLink) } } label: {
                        HStack { Text("Add Keiyoushi repository"); if store.refreshing { Spacer(); ProgressView() } }
                    }.disabled(store.busy || repositoryLink.isEmpty).accessibilityIdentifier("manga-add-repository")
                }
            }
            if store.loading { Section { ProgressView("Loading extensions…") } }
            if store.catalog != nil || !store.state.installations.isEmpty {
                Section {
                    Picker("Extensions", selection: $showInstalled) {
                        Text("Available").tag(false)
                        Text("Installed (\(store.state.installations.count))").tag(true)
                    }.pickerStyle(.segmented).accessibilityIdentifier("manga-extension-list-mode")
                    Picker("Language", selection: $language) {
                        Text("All languages").tag("")
                        ForEach(Array(Set(languages + ["en"])).sorted(), id: \.self) { code in
                            Text(Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()).tag(code)
                        }
                    }
                    Toggle("Show mature source collections", isOn: $showMature)
                        .accessibilityIdentifier("manga-mature-sources")
                } footer: { Text("English includes sources available in every language. Mature and mixed-content collections are hidden by default.") }
                if showInstalled {
                    Section("Installed on this device") {
                        ForEach(installed) { entry in
                            NavigationLink { MangaExtensionDetailView(store: store, descriptor: entry.descriptor) } label: {
                                MangaExtensionLabel(entry: entry.descriptor, status: store.update(for: entry) != nil ? "Update available" : entry.enabled ? "Installed" : "Disabled")
                            }
                        }
                        if installed.isEmpty { Text("No installed extensions match these filters.").foregroundStyle(.secondary) }
                    }
                } else {
                    Section("\(available.count) available") {
                        ForEach(available) { entry in
                            NavigationLink { MangaExtensionDetailView(store: store, descriptor: entry) } label: {
                                MangaExtensionLabel(entry: entry, status: store.installed(entry.id).map { store.update(for: $0) != nil ? "Update available" : "Installed" })
                            }
                        }
                        if available.isEmpty { Text("No extensions match these filters.").foregroundStyle(.secondary) }
                    }
                }
            }
        }.navigationTitle("Manga extensions").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Find a manga source")
            .task { await store.load() }
            .refreshable { if store.state.repositoryAdded { await store.refresh() } }
            .toolbar {
                if store.state.repositoryAdded {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Link("Keiyoushi website", destination: URL(string: "https://keiyoushi.github.io")!)
                            Button("Remove repository", role: .destructive) { removingRepository = true }.disabled(store.busy)
                        } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Repository options")
                    }
                }
            }
            .confirmationDialog("Remove Keiyoushi repository?", isPresented: $removingRepository) {
                Button("Remove repository", role: .destructive) { Task { await store.removeRepository() } }
            } message: { Text("Installed extensions stay on this device. Add the repository again to check for updates.") }
            .alert("Manga extensions", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK") { store.error = nil }
            } message: { Text(store.error ?? "") }
    }
}

private struct MangaExtensionLabel: View {
    let entry: MangaExtensionDescriptor
    let status: String?
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension.fill").font(.title3).foregroundStyle(.teal)
                .frame(width: 38, height: 44).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name).foregroundStyle(.primary)
                Text("\(entry.languages.prefix(4).map { $0 == "all" ? "Multilingual" : $0.uppercased() }.joined(separator: " · ")) · \(entry.versionName)")
                    .font(.caption).foregroundStyle(.secondary)
                if let status { Text(status).font(.caption.weight(.medium)).foregroundStyle(.mint) }
                if !entry.supportsRuntime { Text("Needs a runtime update").font(.caption).foregroundStyle(.orange) }
            }.padding(.vertical, 4)
        }
    }
}

private struct MangaExtensionDetailView: View {
    @ObservedObject var store: MangaExtensionStore
    let descriptor: MangaExtensionDescriptor
    @AppStorage("manga.showMatureSources") private var showMature = false
    @State private var removing = false
    @State private var sourceLanguage = "en"
    private var installation: InstalledMangaExtension? { store.installed(descriptor.id) }
    private var entry: MangaExtensionDescriptor { installation?.descriptor ?? descriptor }
    private var canShow: Bool { showMature || !entry.adult }
    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: entry.versionName)
                LabeledContent("Sources", value: "\(installation?.sources.count ?? entry.sources.count)")
                if let installed = installation {
                    Label("Loaded on this device", systemImage: "checkmark.circle.fill").foregroundStyle(.mint)
                    Toggle("Enabled", isOn: Binding(get: { store.installed(entry.id)?.enabled ?? false }, set: { enabled in Task { await store.setEnabled(entry.id, enabled) } }))
                        .disabled(store.busy).accessibilityIdentifier("manga-extension-enabled")
                    if let update = store.update(for: installed) {
                        installButton(update, title: "Update to \(update.versionName)")
                    }
                } else { installButton(entry, title: "Install extension") }
            } footer: {
                if !entry.supportsRuntime { Text("This source’s extension format needs a newer runtime.") }
                else if entry.sha256 == nil { Text("Refresh the repository to retrieve this package’s checksum.") }
                else { Text("Packages are verified before loading. Updates are installed only when you choose them.") }
            }
            if !canShow {
                Section { Text("This collection is hidden by your mature-source preference.").foregroundStyle(.secondary) }
            } else if let installed = installation {
                Section {
                    if installed.sources.count > 1 {
                        Picker("Source language", selection: $sourceLanguage) {
                            Text("All languages").tag("")
                            ForEach(Array(Set(installed.sources.map(\.language) + ["en"])).filter { $0 != "all" }.sorted(), id: \.self) { code in
                                Text(Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()).tag(code)
                            }
                        }
                    }
                    ForEach(installed.sources.filter { sourceLanguage.isEmpty || $0.language == sourceLanguage || $0.language == "all" }, id: \.index) { source in
                        NavigationLink { MangaSourceBrowseView(store: store, extensionID: entry.id, source: source) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(source.name)
                                Text(source.language == "all" ? "Multilingual" : source.language.uppercased()).font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(!installed.enabled || store.installing != nil)
                    }
                } header: { Text("Browse sources") } footer: { Text("Browsing runs the installed extension on your phone. Source and website compatibility can vary; page reading follows in the reader update.") }
            } else {
                Section("Included sources") {
                    ForEach(entry.sources.prefix(12)) { source in
                        LabeledContent(source.name, value: source.language.uppercased())
                    }
                    if entry.sources.count > 12 { Text("\(entry.sources.count - 12) more sources").foregroundStyle(.secondary) }
                }
            }
            if installation != nil {
                Section { Button("Remove extension", role: .destructive) { removing = true }.disabled(store.busy) }
            }
        }.navigationTitle(entry.name).navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let installed = installation, !installed.sources.contains(where: { $0.language == "en" || $0.language == "all" }) { sourceLanguage = "" }
            }
            .confirmationDialog("Remove \(entry.name)?", isPresented: $removing) {
                Button("Remove extension", role: .destructive) { Task { await store.remove(entry.id) } }
            } message: { Text("This deletes the installed source package from this device.") }
    }
    private func installButton(_ entry: MangaExtensionDescriptor, title: String) -> some View {
        Button { Task { await store.install(entry) } } label: {
            HStack { Text(title); if store.installing == entry.id { Spacer(); ProgressView() } }
        }.disabled(store.busy || !entry.supportsRuntime || entry.sha256 == nil || !canShow)
            .accessibilityIdentifier("manga-install-extension")
    }
}

private struct MangaSourceBrowseView: View {
    @ObservedObject var store: MangaExtensionStore
    let extensionID: String
    let source: MangaRuntimeSource
    @State private var mode = "popular"
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var mangas: [SourceManga] = []
    @State private var page = 0
    @State private var hasNext = false
    @State private var loading = false
    @State private var error: String?
    @State private var generation = UUID()
    private var requestKey: String { mode + "\u{1f}" + submittedQuery }
    var body: some View {
        List {
            Section {
                Picker("Browse", selection: $mode) {
                    Text("Popular").tag("popular")
                    if source.supportsLatest { Text("Latest").tag("latest") }
                    if !submittedQuery.isEmpty { Text("Search").tag("search") }
                }.pickerStyle(.segmented)
            } footer: { Text("Source browsing preview. Chapter and page reading will be added next.") }
            if let error {
                Section {
                    Text(error).foregroundStyle(.orange)
                    Button("Try again") { Task { await load(reset: true) } }.disabled(loading)
                }
            }
            Section(mode == "search" ? "Results for “\(submittedQuery)”" : "Titles") {
                ForEach(mangas) { manga in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(manga.title).font(.headline)
                        if !manga.author.isEmpty { Text(manga.author).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 3)
                }
                if loading { ProgressView("Loading source…") }
                else if mangas.isEmpty && error == nil { Text("This source returned no titles.").foregroundStyle(.secondary) }
                if hasNext && !loading { Button("Load more") { Task { await load(reset: false) } } }
            }
        }.navigationTitle(source.name).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search this source")
            .onSubmit(of: .search) { submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines); mode = submittedQuery.isEmpty ? "popular" : "search" }
            .task(id: requestKey) { await load(reset: true) }
    }
    private func load(reset: Bool) async {
        if reset { generation = UUID(); mangas = []; page = 0; hasNext = false }
        let token = generation, key = requestKey, nextPage = reset ? 1 : page + 1
        loading = true; error = nil
        defer { if token == generation { loading = false } }
        do {
            let result = try await store.browse(extensionID: extensionID, sourceID: source.id, mode: mode, query: submittedQuery, page: nextPage)
            try Task.checkCancellation()
            guard token == generation, key == requestKey else { return }
            var seen = Set(mangas.map(\.id))
            mangas += result.mangas.filter { !$0.url.isEmpty && seen.insert($0.id).inserted }
            page = nextPage; hasNext = result.hasNext
        } catch is CancellationError {} catch {
            if token == generation, key == requestKey { self.error = error.localizedDescription }
        }
    }
}
