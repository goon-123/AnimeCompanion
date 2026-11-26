import SwiftUI
import AnimeCore

private enum ExtensionHubTab: String, CaseIterable {
    case installed = "My sources", browse = "Browse", updates = "Updates"
}

struct UnifiedExtensionsView: View {
    @StateObject private var store = UnifiedExtensionStore()
    @ObservedObject private var runtime = AnymeXRuntime.shared
    @EnvironmentObject private var contentPreferences: AppStore
    @EnvironmentObject private var manga: MangaExtensionStore
    @State private var kind: ExtensionContentKind = .anime
    @State private var tab = ExtensionHubTab.installed
    @State private var manager = ""
    @State private var query = ""
    @State private var language = ""
    @State private var adding = false
    @State private var filtering = false
    @State private var activeSource: String?
    @State private var removing: UnifiedExtensionSource?
    @State private var notice: String?
    @State private var started = false
    var initialQuery = ""
    var initialKind: ExtensionContentKind = .anime

    private var managers: [UnifiedExtensionManager] { store.snapshot.managers.filter { $0.types.contains(kind) } }
    private var installed: [UnifiedExtensionSource] { visible(store.snapshot.installed) }
    private var available: [UnifiedExtensionSource] { visible(store.snapshot.available) }
    private var updates: [UnifiedExtensionSource] { installed.filter { $0.hasUpdate == true } }
    private var rows: [UnifiedExtensionSource] {
        let entries: [UnifiedExtensionSource]
        switch tab { case .installed: entries = installed; case .browse: entries = available; case .updates: entries = updates }
        return entries.filter {
            (manager.isEmpty || $0.managerId == manager) &&
            (language.isEmpty || $0.lang == language || $0.lang == "all") &&
            (query.isEmpty || $0.label.localizedCaseInsensitiveContains(query))
        }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
    private var languages: [String] {
        Array(Set((installed + available).compactMap(\.lang))).filter { !$0.isEmpty && $0 != "all" }.sorted()
    }
    private var hasFilters: Bool { !manager.isEmpty || !language.isEmpty || !query.isEmpty }
    private var hasRepositories: Bool { managers.contains { $0.repositories.contains { $0.type == kind } } }
    private var countLabel: String { "\(rows.count) \(rows.count == 1 ? "source" : "sources")" }
    private func visible(_ sources: [UnifiedExtensionSource]) -> [UnifiedExtensionSource] {
        sources.filter { $0.kind == kind && $0.isVisible(includeAdultAnime: contentPreferences.includeAdult, readingContent: contentPreferences.mangaBakaContent) }
    }
    private func systemName(_ source: UnifiedExtensionSource) -> String {
        store.snapshot.managers.first { $0.id == source.managerId }?.name ?? source.managerId.replacingOccurrences(of: "-desktop", with: "").capitalized
    }
    private func installedSource(_ source: UnifiedExtensionSource) -> UnifiedExtensionSource? {
        store.snapshot.installed.first { $0.id == source.id }
    }

    var body: some View {
        List {
            Section {
                Picker("Content", selection: Binding(get: { kind }, set: { kind = $0; clearFilters(); notice = nil })) {
                    ForEach(ExtensionContentKind.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("extensions-content")
                Picker("Sources", selection: $tab) {
                    ForEach(ExtensionHubTab.allCases, id: \.self) { item in
                        Text(item == .updates && !updates.isEmpty ? "Updates (\(updates.count))" : item.rawValue).tag(item)
                    }
                }.pickerStyle(.segmented).accessibilityIdentifier("extensions-tabs")
            }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            if !manager.isEmpty || !language.isEmpty {
                Section {
                    Button { filtering = true } label: {
                        Label([managers.first { $0.id == manager }?.name, language.isEmpty ? nil : extensionLanguageName(language)].compactMap { $0 }.joined(separator: " · "), systemImage: "line.3.horizontal.decrease.circle")
                            .font(.subheadline)
                    }
                }
            }

            if tab == .installed && !updates.isEmpty {
                Section {
                    Button { tab = .updates } label: {
                        Label("\(updates.count) \(updates.count == 1 ? "update ready" : "updates ready")", systemImage: "arrow.down.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }.accessibilityIdentifier("extensions-updates-ready")
                }
            }
            if store.busy { Section { ProgressView(store.status).font(.subheadline) } }
            if let error = store.error {
                Section {
                    Label("Couldn't finish", systemImage: "exclamationmark.triangle").font(.headline).foregroundStyle(.orange)
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                    Button("Try again") { Task { await store.update(store.snapshot.managers.isEmpty ? "initialize" : "refresh") } }.disabled(store.busy)
                }
            }
            if let notice { Section { Label(notice, systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Theme.accent) } }
            if managers.contains(where: { $0.error != nil }) {
                Section {
                    NavigationLink { ExtensionRepositoriesView(initialKind: kind).environmentObject(store) } label: {
                        Label("Some source systems need attention", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                    }
                }
            }

            if !rows.isEmpty {
                Section {
                    if tab == .updates {
                        Button { updateVisibleSources() } label: {
                            Label("Update these sources (\(rows.count))", systemImage: "arrow.down.circle")
                        }.disabled(store.busy || activeSource != nil).accessibilityIdentifier("extensions-update-all")
                    }
                    ForEach(rows) { source in sourceRow(source) }
                } header: {
                    HStack {
                        Text(countLabel)
                        Spacer()
                        if hasFilters { Button("Clear filters") { clearFilters() }.textCase(nil) }
                    }
                }
            } else if !store.busy && !store.snapshot.managers.isEmpty {
                Section { emptyState }.listRowBackground(Color.clear)
            }

            if kind == .manga && tab == .installed {
                Section {
                    NavigationLink { MangaExtensionsView() } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Keiyoushi sources")
                                Text("\(manga.state.installations.count) installed · Manga & webtoons")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "books.vertical").foregroundStyle(.teal) }
                    }
                } footer: { Text("Your existing Keiyoushi sources and reading progress are here.") }
            }
            if tab == .installed {
                Section {
                    NavigationLink { ExtensionSavedTitlesView().environmentObject(store) } label: {
                        Label("Saved titles", systemImage: "bookmark")
                    }
                }
            }
        }
        .navigationTitle("Extensions").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Find a source")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { filtering = true } label: { Image(systemName: hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") }
                    .accessibilityLabel("Filter sources").accessibilityIdentifier("extensions-filters")
                Button { adding = true } label: { Label("Add", systemImage: "plus").labelStyle(.titleAndIcon) }
                    .accessibilityLabel("Add repository").accessibilityIdentifier("extensions-add")
                Menu {
                    Button("Refresh sources", systemImage: "arrow.clockwise") { Task { await store.update("refresh") } }.disabled(store.busy)
                    NavigationLink { ExtensionRepositoriesView(initialKind: kind).environmentObject(store) } label: { Label("Manage repositories", systemImage: "shippingbox") }
                    NavigationLink { ContentPreferencesView() } label: { Label("Content preferences", systemImage: "eye") }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Extension options")
            }
        }
        .sheet(isPresented: $filtering) {
            ExtensionFiltersSheet(managers: managers, languages: languages, manager: $manager, language: $language)
        }
        .sheet(isPresented: $adding) {
            ExtensionAddRepositorySheet(initialKind: kind) { owner, content in
                kind = content; tab = .browse; query = ""; language = ""; manager = owner
                notice = "Repository added. Install a source below to get started."
            }.environmentObject(store)
        }
        .confirmationDialog("Remove this source?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { source in
            Button("Remove \(source.label)", role: .destructive) { perform("uninstall", source: source) }
        } message: { _ in Text("Saved titles are kept. Reinstall the source to open them again.") }
        .task {
            if !started { kind = initialKind; started = true }
            await store.load(); await manga.load()
        }
        .refreshable { await store.update("refresh") }
        .fullScreenCover(isPresented: $runtime.showingPlayer, onDismiss: { runtime.stopVideo() }) { AnymeXPlayerContainer().ignoresSafeArea() }
        .sheet(item: $runtime.website, onDismiss: { runtime.finishWebsite() }) { request in ExtensionWebsiteSessionView(request: request) }
        .accessibilityIdentifier("unified-extensions")
    }

    private func sourceRow(_ source: UnifiedExtensionSource) -> some View {
        let current = installedSource(source)
        return HStack(spacing: 12) {
            if let current {
                NavigationLink {
                    ExtensionContentAccess(source: current) { ExtensionSourceBrowser(source: current, initialQuery: initialQuery).environmentObject(store) }
                } label: { ExtensionSourceLabel(source: source, system: systemName(source)) }
                    .buttonStyle(.plain).accessibilityHint("Browse titles from this source")
            } else { ExtensionSourceLabel(source: source, system: systemName(source)) }
            Spacer(minLength: 0)
            if activeSource == source.id { ProgressView().accessibilityLabel("Working on \(source.label)") }
            else if let current {
                if current.hasUpdate == true {
                    Button("Update") { perform("update", source: current) }.buttonStyle(.bordered).disabled(store.busy || activeSource != nil)
                } else if tab == .browse {
                    NavigationLink {
                        ExtensionContentAccess(source: current) { ExtensionSourceBrowser(source: current, initialQuery: initialQuery).environmentObject(store) }
                    } label: { Text("Open") }.buttonStyle(.bordered)
                }
                Menu {
                    NavigationLink { ExtensionSourcePreferencesView(source: current).environmentObject(store) } label: { Label("Source settings", systemImage: "slider.horizontal.3") }
                    Button("Remove source", systemImage: "trash", role: .destructive) { removing = current }
                } label: { Image(systemName: "ellipsis").frame(minWidth: 32, minHeight: 44).contentShape(Rectangle()) }
                    .disabled(store.busy || activeSource != nil).accessibilityLabel("Options for \(source.label)")
            } else {
                Button("Install") { perform("install", source: source) }.buttonStyle(.borderedProminent)
                    .disabled(store.busy || activeSource != nil).accessibilityIdentifier("extension-install-" + source.id)
            }
        }.padding(.vertical, 6)
    }
    private var emptyState: some View {
        VStack(spacing: 15) {
            Image(systemName: hasFilters ? "magnifyingglass" : tab == .updates ? "checkmark.circle" : "puzzlepiece.extension")
                .font(.system(size: 38)).foregroundStyle(Theme.accent).padding(.top, 20)
            Text(hasFilters ? "No matching sources" : tab == .updates ? "You're up to date" : tab == .installed ? "Add your first source" : "Find your next source")
                .font(.title3.bold())
            Text(hasFilters ? "Try another name, language or system." : tab == .updates ? "Available updates will appear here." : hasRepositories ? "Browse your repositories and install a source. Tap an installed source to explore its titles." : "Add a repository link, then choose which sources to install.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if hasFilters { Button("Clear filters") { clearFilters() }.buttonStyle(.bordered) }
            else if tab != .updates {
                Button(!hasRepositories ? "Add repository" : tab == .installed ? "Browse sources" : "Refresh sources") {
                    if !hasRepositories { adding = true }
                    else if tab == .installed { tab = .browse }
                    else { Task { await store.update("refresh") } }
                }.buttonStyle(.borderedProminent).disabled(store.busy)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 14)
    }
    private func clearFilters() { manager = ""; language = ""; query = "" }
    private func perform(_ operation: String, source: UnifiedExtensionSource) {
        guard activeSource == nil, !store.busy else { return }
        activeSource = source.id; notice = nil
        Task {
            defer { activeSource = nil }
            await store.mutate(operation, source: source)
            if store.error == nil {
                notice = operation == "install" ? "\(source.label) installed. Tap it to browse titles." : operation == "update" ? "\(source.label) updated." : "\(source.label) removed."
            }
        }
    }
    private func updateVisibleSources() {
        guard activeSource == nil, !store.busy else { return }
        let targets = rows
        activeSource = targets.first?.id; notice = nil
        Task {
            defer { activeSource = nil }
            for source in targets {
                guard !Task.isCancelled else { return }
                activeSource = source.id
                await store.mutate("update", source: source)
                if store.error != nil { return }
            }
            notice = "Sources updated."
        }
    }
}

private struct ExtensionSourceLabel: View {
    let source: UnifiedExtensionSource
    let system: String
    var body: some View {
        HStack(spacing: 12) {
            ExtensionRemoteImage(url: source.iconUrl).frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(source.label).font(.headline).foregroundStyle(.primary)
                Text([system, source.lang.map(extensionLanguageName)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private func extensionLanguageName(_ code: String) -> String {
    code == "all" ? "Multilingual" : Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
}

private struct ExtensionFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    let managers: [UnifiedExtensionManager]
    let languages: [String]
    @Binding var manager: String
    @Binding var language: String
    var body: some View {
        AppNavigationStack {
            Form {
                Section {
                    Picker("Language", selection: $language) {
                        Text("All languages").tag("")
                        ForEach(languages, id: \.self) { Text(extensionLanguageName($0)).tag($0) }
                    }
                    Picker("Source system", selection: $manager) {
                        Text("All systems").tag("")
                        ForEach(managers) { Text($0.name).tag($0.id) }
                    }
                }
                Section { Button("Reset filters") { manager = ""; language = "" } }
            }.navigationTitle("Filter sources").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}

struct ExtensionRepositoriesView: View {
    @EnvironmentObject private var store: UnifiedExtensionStore
    @State private var adding = false
    @State private var removing: RepositoryRemoval?
    var initialKind: ExtensionContentKind = .anime
    private var configured: [UnifiedExtensionManager] { store.snapshot.managers.filter { !$0.repositories.isEmpty || $0.error != nil } }
    var body: some View {
        List {
            Section {
                Button { adding = true } label: { Label("Add repository", systemImage: "plus.circle.fill") }.disabled(store.busy)
            } footer: { Text("Repositories provide the sources shown in Browse. Removing a repository keeps installed sources.") }
            if store.busy { Section { ProgressView(store.status) } }
            if let error = store.error { Section { Text(error).foregroundStyle(.orange) } }
            if configured.isEmpty && !store.busy {
                ContentUnavailableView("No repositories yet", systemImage: "shippingbox", description: Text("Add a link to start browsing sources."))
            }
            ForEach(configured) { owner in
                Section(owner.name) {
                    if let error = owner.error {
                        Text(error).font(.subheadline).foregroundStyle(.orange)
                        Button("Retry") { Task { await store.update("retry", ["manager": owner.id]) } }.disabled(store.busy)
                    }
                    ForEach(Array(owner.repositories.enumerated()), id: \.offset) { _, repository in
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(repository.name ?? owner.name)
                                Text("\(URL(string: repository.url)?.host ?? "Repository") · \(repository.type.label)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { removing = RepositoryRemoval(owner: owner, repository: repository) } label: { Image(systemName: "trash") }
                                .foregroundStyle(.red).disabled(store.busy).accessibilityLabel("Remove repository")
                        }
                    }
                }
            }
            Section {
                NavigationLink("Extension runtime notices") {
                    ScrollView {
                        Text((Bundle.main.url(forResource: "ExtensionRuntimeNotices", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? "Runtime notices are unavailable in this build.")
                            .font(.footnote).textSelection(.enabled).padding()
                    }.navigationTitle("Runtime notices")
                }
            }
        }.navigationTitle("Repositories").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $adding) { ExtensionAddRepositorySheet(initialKind: initialKind) { _, _ in }.environmentObject(store) }
            .confirmationDialog("Remove repository?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { target in
                Button("Remove repository", role: .destructive) {
                    Task { await store.update("removeRepo", ["manager": target.owner.id, "type": target.repository.type.rawValue, "url": target.repository.url]) }
                }
            } message: { _ in Text("Installed sources and saved titles are kept.") }
    }
    private struct RepositoryRemoval { let owner: UnifiedExtensionManager; let repository: UnifiedExtensionRepository }
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
