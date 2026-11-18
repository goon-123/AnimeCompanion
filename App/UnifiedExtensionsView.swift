import SwiftUI
import AnimeCore

struct UnifiedExtensionsView: View {
    @StateObject private var store = UnifiedExtensionStore()
    @ObservedObject private var runtime = AnymeXRuntime.shared
    @State private var kind: ExtensionContentKind = .anime
    @State private var manager = ""
    @State private var installedOnly = true
    @State private var query = ""
    @State private var language = ""
    @EnvironmentObject private var contentPreferences: AppStore
    private var mature: Bool { kind == .anime ? contentPreferences.includeAdult : contentPreferences.mangaBakaContent.allowsMatureSources }
    var initialQuery = ""
    var initialKind: ExtensionContentKind = .anime
    private var sources: [UnifiedExtensionSource] {
        (installedOnly ? store.snapshot.installed : store.snapshot.available).filter {
            $0.kind == kind && (manager.isEmpty || $0.managerId == manager)
                && (mature || $0.isNsfw != true)
                && (language.isEmpty || $0.lang == language || $0.lang == "all")
                && (query.isEmpty || $0.label.localizedCaseInsensitiveContains(query))
        }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
    private var managers: [UnifiedExtensionManager] { store.snapshot.managers.filter { $0.types.contains(kind) } }
    private var languages: [String] {
        Array(Set((store.snapshot.available + store.snapshot.installed).filter { $0.kind == kind }
            .compactMap(\.lang))).filter { !$0.isEmpty && $0 != "all" }.sorted()
    }
    var body: some View {
        List {
            Section {
                Text("Anime, manga & novels").font(.title2.bold())
                Text("Choose a source system, add a repository, then install the sources you want.").font(.subheadline).foregroundStyle(.secondary)
                Picker("Content", selection: $kind) { ForEach(ExtensionContentKind.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                Picker("Show", selection: $installedOnly) { Text("Installed").tag(true); Text("Available").tag(false) }.pickerStyle(.segmented)
            }
            Section {
                Picker("Source system", selection: $manager) {
                    Text("All systems").tag("")
                    ForEach(managers) { Text($0.name).tag($0.id) }
                }
                Picker("Language", selection: $language) { Text("All languages").tag(""); ForEach(languages, id: \.self) { Text($0.uppercased()).tag($0) } }
                MangaBakaContentButton()
                NavigationLink { ExtensionRepositoriesView().environmentObject(store) } label: { Label("Repositories & source systems", systemImage: "shippingbox") }
            }
            if store.busy { Section { ProgressView(store.status) } }
            if let error = store.error { Section { Text(error).foregroundStyle(.orange); Button("Retry") { Task { await store.update(store.snapshot.managers.isEmpty ? "initialize" : "refresh") } } } }
            Section("\(installedOnly ? "Installed" : "Available") · \(sources.count)") {
                ForEach(sources) { source in
                    if installedOnly {
                        NavigationLink { ExtensionContentAccess(source: source) { ExtensionSourceBrowser(source: source, initialQuery: initialQuery).environmentObject(store) } } label: { ExtensionSourceLabel(source: source) }
                    } else {
                        HStack {
                            ExtensionSourceLabel(source: source)
                            Spacer()
                            if store.snapshot.installed.contains(where: { $0.id == source.id }) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint) }
                            else { Button("Install") { Task { await store.mutate("install", source: source) } }.buttonStyle(.bordered).disabled(store.busy) }
                        }
                    }
                }
                if sources.isEmpty && !store.busy {
                    ContentUnavailableView(installedOnly ? "No sources installed" : "No sources match", systemImage: "puzzlepiece.extension",
                        description: Text(installedOnly ? "Add a repository and switch to Available to install sources." : "Add a repository, or change your system, language or search filters."))
                    if installedOnly { Button("Browse available sources") { installedOnly = false } }
                    NavigationLink("Add a repository") { ExtensionRepositoriesView().environmentObject(store) }
                }
            }
            Section { NavigationLink { ExtensionSavedTitlesView().environmentObject(store) } label: { Label("Saved extension titles", systemImage: "bookmark") } }
        }
        .navigationTitle("Extensions").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Find an extension")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Refresh repositories", systemImage: "arrow.clockwise") { Task { await store.update("refresh") } }
                    Button("Update all extensions", systemImage: "arrow.down.circle") { Task { await store.update("updateAll") } }
                } label: { Image(systemName: "ellipsis.circle") }.disabled(store.busy)
            }
        }
        .task { kind = initialKind; await store.load() }
        .onChange(of: kind) { _, _ in if !managers.contains(where: { $0.id == manager }) { manager = "" }; language = "" }
        .refreshable { await store.update("refresh") }
        .fullScreenCover(isPresented: $runtime.showingPlayer, onDismiss: { runtime.stopVideo() }) { AnymeXPlayerContainer().ignoresSafeArea() }
        .sheet(item: $runtime.website, onDismiss: { runtime.finishWebsite() }) { request in ExtensionWebsiteSessionView(request: request) }
        .accessibilityIdentifier("unified-extensions")
    }
}

private struct ExtensionSourceLabel: View {
    let source: UnifiedExtensionSource
    var body: some View {
        HStack(spacing: 12) {
            ExtensionRemoteImage(url: source.iconUrl).frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 4) {
                Text(source.label).font(.headline)
                Text([source.managerId.replacingOccurrences(of: "-desktop", with: ""), source.lang?.uppercased(), source.version.map { "v\($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if source.hasUpdate == true { Text("Update available").font(.caption).foregroundStyle(.mint) }
            }
        }
    }
}

struct ExtensionRepositoriesView: View {
    @EnvironmentObject private var store: UnifiedExtensionStore
    @State private var managerID = ""
    @State private var kind: ExtensionContentKind = .anime
    @State private var url = ""
    @State private var validation: String?
    private var selected: UnifiedExtensionManager? { store.snapshot.managers.first { $0.id == managerID } }
    var body: some View {
        Form {
            Section("Add a repository") {
                Picker("System", selection: $managerID) { Text("Choose a system").tag(""); ForEach(store.snapshot.managers) { Text($0.name).tag($0.id) } }
                if let selected { Picker("Content", selection: $kind) { ForEach(selected.types) { Text($0.label).tag($0) } } }
                TextField("HTTPS repository URL", text: $url).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button("Add repository") { add() }.disabled(store.busy || selected == nil || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let validation { Text(validation).foregroundStyle(.orange) }
                Link("Find repository URLs", destination: URL(string: "https://github.com/Shebyyy/AnymeX-Guides")!)
            }
            if store.busy { Section { ProgressView(store.status) } }
            if let error = store.error { Section { Text(error).foregroundStyle(.orange) } }
            ForEach(store.snapshot.managers) { owner in
                Section(owner.name) {
                    Text(owner.types.map(\.label).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    if let error = owner.error {
                        Text(error).foregroundStyle(.orange)
                        Button("Retry \(owner.name)") { Task { await store.update("retry", ["manager": owner.id]) } }.disabled(store.busy)
                    }
                    ForEach(Array(owner.repositories.enumerated()), id: \.offset) { _, repository in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(repository.name ?? owner.name)
                            // Configured URLs can contain private tokens. Display only
                            // the host; do not expose paths in screenshots or logs.
                            Text("\(URL(string: repository.url)?.host ?? "Repository") · \(repository.type.label)").font(.caption).foregroundStyle(.secondary)
                        }.swipeActions {
                            Button("Remove", role: .destructive) { Task { await store.update("removeRepo", ["manager": owner.id, "type": repository.type.rawValue, "url": repository.url]) } }.disabled(store.busy)
                        }
                    }
                    if owner.repositories.isEmpty { Text("No repositories added").font(.subheadline).foregroundStyle(.secondary) }
                }
            }
            Section {
                Text("All source systems are included. Source availability depends on each repository and website.").font(.footnote).foregroundStyle(.secondary)
                NavigationLink("Extension runtime notices") {
                    ScrollView {
                        Text((Bundle.main.url(forResource: "ExtensionRuntimeNotices", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? "Runtime notices are included in the AnymeX-enabled release.")
                            .font(.footnote).textSelection(.enabled).padding()
                    }.navigationTitle("Runtime notices")
                }
            }
        }.navigationTitle("Repositories").navigationBarTitleDisplayMode(.inline)
            .onChange(of: managerID) { _, _ in kind = selected?.types.first ?? .anime }
    }
    private func add() {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: trimmed), parts.scheme?.lowercased() == "https", parts.host?.isEmpty == false,
              parts.user == nil, parts.password == nil else { validation = "Enter a complete HTTPS repository URL."; return }
        validation = nil
        Task { await store.update("addRepo", ["manager": managerID, "type": kind.rawValue, "url": trimmed]); if store.error == nil { url = "" } }
    }
}

struct ExtensionSourceBrowser: View {
    @EnvironmentObject private var store: UnifiedExtensionStore
    let source: UnifiedExtensionSource
    var initialQuery = ""
    @State private var query = ""
    @State private var mode = "popular"
    @State private var items: [ExtensionMedia] = []
    @State private var page = 1
    @State private var hasNext = false
    @State private var loading = false
    @State private var error: String?
    @State private var revision = UUID()
    private var requestID: String { mode + ":" + revision.uuidString }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                Picker("Browse", selection: $mode) { Text("Popular").tag("popular"); Text("Latest").tag("latest"); Text("Search").tag("search") }.pickerStyle(.segmented)
                if let error { Text(error).foregroundStyle(.orange); Button("Retry") { revision = UUID() } }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118, maximum: 180))], spacing: 18) {
                    ForEach(items) { media in
                        NavigationLink { ExtensionContentAccess(source: source) { ExtensionMediaDetailView(source: source, media: media).environmentObject(store) } } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                ExtensionRemoteImage(url: media.cover).aspectRatio(0.68, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
                                Text(media.title).font(.caption.weight(.semibold)).lineLimit(2).foregroundStyle(.primary)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                if loading { ProgressView("Loading…") }
                else if hasNext { Button("Load more") { Task { await load(next: true) } }.buttonStyle(.bordered) }
                else if items.isEmpty && error == nil { ContentUnavailableView("No titles found", systemImage: "magnifyingglass", description: Text("Try searching by title, or choose another browse mode.")) }
            }.padding(18).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.background(Theme.background)
        .navigationTitle(source.label).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search this source")
        .onSubmit(of: .search) { mode = "search"; revision = UUID() }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { ExtensionSourcePreferencesView(source: source).environmentObject(store) } label: { Image(systemName: "slider.horizontal.3") } } }
        .task { query = initialQuery; if !initialQuery.isEmpty { mode = "search" } }
        .task(id: requestID) { await load(next: false) }
    }
    private func load(next: Bool) async {
        if next && loading { return }
        let identity = requestID
        loading = true; error = nil
        if !next { items = []; page = 1; hasNext = false }
        let wanted = next ? page + 1 : 1
        do {
            let result: ExtensionMediaPage = try await store.request("browse", source: source,
                arguments: ["mode": mode, "query": query, "page": wanted])
            guard identity == requestID, !Task.isCancelled else { return }
            var known = Set(items.map(\.id))
            let additions = result.list.filter { known.insert($0.id).inserted }
            items += additions; hasNext = result.hasNextPage; page = wanted
        } catch is CancellationError {} catch { if identity == requestID { self.error = error.localizedDescription } }
        if identity == requestID { loading = false }
    }
}

struct ExtensionMediaDetailView: View {
    @EnvironmentObject private var store: UnifiedExtensionStore
    @ObservedObject private var library = ExtensionSavedLibrary.shared
    let source: UnifiedExtensionSource
    let media: ExtensionMedia
    @State private var details: ExtensionMedia?
    @State private var error: String?
    @State private var loading = false
    @State private var reverse = false
    private var entry: ExtensionMedia { details ?? media }
    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    ExtensionRemoteImage(url: entry.cover).frame(width: 100, height: 150).clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 12) {
                        Text(entry.title).font(.title2.bold())
                        Text(source.label).font(.subheadline).foregroundStyle(.secondary)
                        Button { library.toggle(source: source, media: media) } label: { Label(library.contains(source, media) ? "Saved" : "Save title", systemImage: library.contains(source, media) ? "bookmark.fill" : "bookmark") }.buttonStyle(.bordered)
                    }
                }.padding(.vertical, 8)
                if !entry.synopsis.isEmpty { Text(TextSanitizer.synopsis(entry.synopsis)).font(.subheadline).textSelection(.enabled) }
            }
            if loading { Section { ProgressView("Loading details…") } }
            if let error { Section { Text(error).foregroundStyle(.orange); Button("Retry") { Task { await load() } } } }
            Section {
                ForEach(reverse ? Array(entry.episodes.reversed()) : entry.episodes) { episode in
                    NavigationLink {
                        ExtensionContentAccess(source: source) { ExtensionChapterView(source: source, media: entry, episode: episode).environmentObject(store) }
                    } label: {
                        HStack {
                            Image(systemName: source.kind == .anime ? "play.circle" : "doc.text")
                            Text(episode.label).lineLimit(2)
                            Spacer()
                            if library.isRead(source, episode) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint) }
                        }
                    }
                }
                if entry.episodes.isEmpty && !loading { Text("No episodes or chapters are available from this source.").foregroundStyle(.secondary) }
            } header: { HStack { Text(source.kind == .anime ? "Episodes" : "Chapters"); Spacer(); Button(reverse ? "Newest first" : "Source order") { reverse.toggle() } } }
        }.navigationTitle(entry.title).navigationBarTitleDisplayMode(.inline).task { await load() }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { details = try await store.request("detail", source: source, arguments: ["media": media.payload.foundation]) }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct ExtensionContentAccess<Content: View>: View {
    @EnvironmentObject private var preferences: AppStore
    let source: UnifiedExtensionSource
    @ViewBuilder let content: () -> Content
    var body: some View {
        if source.isVisible(includeAdultAnime: preferences.includeAdult, readingContent: preferences.mangaBakaContent) {
            content()
        } else {
            VStack(spacing: 16) {
                ContentUnavailableView("Source hidden", systemImage: "eye.slash", description: Text("This source is hidden by your Content preferences."))
                MangaBakaContentButton()
            }
        }
    }
}
