import SwiftUI
import AnimeCore

struct MangaExtensionsView: View {
    @EnvironmentObject private var store: MangaExtensionStore
    @AppStorage("manga.showMatureSources") private var showMature = false
    private enum Mode: String, CaseIterable { case available = "Available", installed = "Installed", updates = "Updates" }
    @State private var repositoryLink = "https://keiyoushi.github.io"
    @State private var query = ""
    @State private var language = "en"
    @State private var mode = Mode.available
    @State private var removingRepository = false
    @State private var opened = false
    @State private var updateTask: Task<Void, Never>?
    private var languages: [String] {
        let sources = (store.catalog?.extensions.flatMap(\.sources) ?? []) + store.state.installations.flatMap { $0.descriptor.sources }
        return Array(Set(sources.map(\.language) + ["en"])).filter { $0 != "all" }.sorted()
    }
    private var available: [MangaExtensionDescriptor] { (store.catalog?.extensions ?? []).filter(matches) }
    private var installed: [MangaExtensionDescriptor] {
        store.state.installations.map(\.descriptor).filter(matches).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var updates: [MangaExtensionDescriptor] { store.updates.filter(matches) }
    private var rows: [MangaExtensionDescriptor] { switch mode { case .available: return available; case .installed: return installed; case .updates: return updates } }
    private var updateable: [MangaExtensionDescriptor] { store.updates.filter { $0.supportsRuntime && (showMature || !$0.adult) } }
    private func matches(_ entry: MangaExtensionDescriptor) -> Bool { entry.matches(query: query, language: language, includeAdult: showMature) }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header
                repository
                if store.loading { ProgressView("Loading extensions…").frame(maxWidth: .infinity) }
                if let notice = store.notice { Label(notice, systemImage: "checkmark.circle").font(.subheadline).foregroundStyle(Theme.accent) }
                if let error = store.error {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Extension action couldn't finish", systemImage: "exclamationmark.triangle").font(.headline)
                        Text(error).font(.subheadline).textSelection(.enabled)
                        HStack {
                            Button("Retry") { Task { if store.unreadableState { await store.retryLoad() } else { await store.refresh(link: repositoryLink) } } }
                                .disabled(store.refreshing || store.installing != nil || store.updatingAll)
                            Spacer(); Button("Dismiss") { store.error = nil }
                        }
                    }.foregroundStyle(.orange).companionPanel()
                }
                if store.catalog != nil || !store.state.installations.isEmpty {
                    filters
                    if store.updatingAll {
                        HStack {
                            ProgressView()
                            Text(store.updateProgress).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                            Button("Stop") { updateTask?.cancel() }
                        }.companionPanel().accessibilityIdentifier("manga-update-progress")
                    }
                    HStack {
                        Text(mode == .updates ? "Updates · \(updates.count)" : "\(mode.rawValue) · \(rows.count)").font(.title2.bold())
                        Spacer()
                        if mode != .available && !updateable.isEmpty && !store.updatingAll {
                            Button("Update all (\(updateable.count))") { updateTask = Task { await store.updateAll(includeAdult: showMature) } }
                                .buttonStyle(.borderedProminent).disabled(store.busy).accessibilityIdentifier("manga-update-all")
                        }
                    }
                    ForEach(rows) { entry in extensionCard(entry) }
                    if rows.isEmpty && !store.loading {
                        ContentUnavailableView(mode == .updates && store.updates.isEmpty ? "You're up to date" : "No extensions match",
                            systemImage: mode == .updates ? "checkmark.circle" : "magnifyingglass",
                            description: Text(mode == .updates && store.updates.isEmpty ? "Check for updates to get the latest source packages." : "Try another name or language. Mature collections follow the switch above."))
                        if !query.isEmpty || !language.isEmpty { Button("Clear search and language filters") { query = ""; language = "" } }
                    }
                }
            }.frame(maxWidth: 940, alignment: .leading).padding(18).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Manga extensions").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Find a manga source")
            .task {
                await store.load()
                if !opened {
                    if !store.updates.isEmpty { mode = .updates }
                    else if !store.state.installations.isEmpty { mode = .installed }
                    opened = true
                }
            }
            .refreshable { if store.state.repositoryAdded { await store.refresh() } }
            .toolbar {
                if store.state.repositoryAdded {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Check for updates", systemImage: "arrow.clockwise") { Task { await store.refresh() } }.disabled(store.busy)
                            Link("Keiyoushi website", destination: URL(string: "https://keiyoushi.github.io")!)
                            Button("Remove repository", role: .destructive) { removingRepository = true }.disabled(store.busy)
                        } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }.accessibilityLabel("Repository options")
                    }
                }
            }
            .confirmationDialog("Remove Keiyoushi repository?", isPresented: $removingRepository) {
                Button("Remove repository", role: .destructive) { Task { await store.removeRepository() } }
            } message: { Text("Installed extensions stay on this device. Add the repository again to check for updates.") }
            .onDisappear { updateTask?.cancel() }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "books.vertical.fill").font(.system(size: 30)).foregroundStyle(Theme.accent)
                    .frame(width: 64, height: 64).background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your reading sources").font(.title.bold())
                    Text("Discover, manage and update your manga extensions.").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                statistic("Installed", value: store.state.installations.count)
                statistic("Updates", value: store.updates.count)
                statistic("Available", value: store.catalog?.extensions.count ?? 0)
            }
        }
    }
    private func statistic(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.formatted()).font(.title2.bold().monospacedDigit()).foregroundStyle(Theme.accent)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).companionPanel(padding: 14)
    }
    private var repository: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Keiyoushi", systemImage: "shippingbox.fill").font(.headline)
                Spacer()
                if store.refreshing { ProgressView() }
                else if store.state.repositoryAdded { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
            }
            if store.state.repositoryAdded {
                if let date = store.lastRefresh { Text("Last checked " + date.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary) }
                Button { Task { await store.refresh() } } label: {
                    Label("Check for updates", systemImage: "arrow.clockwise").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.bordered).disabled(store.busy).accessibilityIdentifier("manga-refresh")
            } else {
                Text("Add the repository to browse and install sources. No server is needed.").font(.subheadline).foregroundStyle(.secondary)
                TextField("Repository link", text: $repositoryLink).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("manga-repository-link")
                Button { Task { await store.refresh(link: repositoryLink) } } label: {
                    Label("Add Keiyoushi repository", systemImage: "plus.circle").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).disabled(store.busy || repositoryLink.isEmpty).accessibilityIdentifier("manga-add-repository")
            }
        }.companionPanel()
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Extensions", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).accessibilityIdentifier("manga-extension-list-mode")
            Picker("Language", selection: $language) {
                Text("All languages").tag("")
                ForEach(languages, id: \.self) { Text(Locale.current.localizedString(forLanguageCode: $0) ?? $0.uppercased()).tag($0) }
            }
            Toggle("Show mature source collections", isOn: $showMature).accessibilityIdentifier("manga-mature-sources")
        }.companionPanel()
    }
    private func extensionCard(_ descriptor: MangaExtensionDescriptor) -> some View {
        let installed = store.installed(descriptor.id)
        let update = installed.flatMap { store.update(for: $0) }
        return HStack(spacing: 12) {
            NavigationLink { MangaExtensionDetailView(store: store, descriptor: descriptor) } label: {
                MangaExtensionLabel(entry: descriptor, status: installed.map { update != nil ? "Update available" : ($0.enabled ? "Installed" : "Disabled") })
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            if store.installing == descriptor.id { ProgressView() }
            else if let update {
                Button("Update") { Task { await store.install(update) } }.buttonStyle(.borderedProminent)
                    .disabled(store.busy || !update.supportsRuntime)
                    .accessibilityIdentifier("manga-update-" + descriptor.id)
            } else if installed == nil {
                Button("Install") { Task { await store.install(descriptor) } }.buttonStyle(.bordered)
                    .disabled(store.busy || !descriptor.supportsRuntime)
                    .accessibilityIdentifier("manga-install-" + descriptor.id)
            } else {
                Image(systemName: installed?.enabled == true ? "checkmark.circle.fill" : "pause.circle").foregroundStyle(Theme.accent)
            }
        }.companionPanel(padding: 14)
    }
}

private struct MangaExtensionLabel: View {
    let entry: MangaExtensionDescriptor
    let status: String?
    var body: some View {
        HStack(spacing: 12) {
            MangaExtensionIcon(entry: entry, size: 52)
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
                HStack(spacing: 14) {
                    MangaExtensionIcon(entry: entry, size: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name).font(.headline)
                        Text(entry.languages.map { $0 == "all" ? "Multilingual" : $0.uppercased() }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }.padding(.vertical, 4)
                LabeledContent(installation == nil ? "Version" : "Installed version", value: entry.versionName)
                if let installed = installation, let update = store.update(for: installed) {
                    LabeledContent("Available version", value: update.versionName).foregroundStyle(Theme.accent)
                }
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
                else { Text("Packages are verified before loading. Updates are installed only when you choose them.") }
            }
            if let message = store.notice { Section { Text(message).foregroundStyle(Theme.accent) } }
            if let error = store.error { Section { Text(error).font(.subheadline).foregroundStyle(.orange).textSelection(.enabled) } }
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
                            NavigationLink { MangaSourceBrowseView(source: MangaSourceReference(installation: installed, source: source)) } label: {
                            HStack(spacing: 12) {
                                MangaExtensionIcon(entry: entry)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.name)
                                    Text(source.language == "all" ? "Multilingual" : source.language.uppercased()).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.disabled(!installed.enabled || store.installing != nil)
                    }
                } header: { Text("Browse sources") } footer: { Text("Sources also appear in the Manga tab. Source and website compatibility can vary.") }
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
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                    .disabled(store.busy || !store.state.repositoryAdded).accessibilityLabel("Check for extension updates")
            } }
            .onChange(of: installation?.descriptor.sha256, initial: true) {
                if let installed = installation, !installed.sources.contains(where: { $0.language == sourceLanguage || $0.language == "all" }) { sourceLanguage = "" }
            }
            .confirmationDialog("Remove \(entry.name)?", isPresented: $removing) {
                Button("Remove extension", role: .destructive) { Task { await store.remove(entry.id) } }
            } message: { Text("This deletes the installed source package from this device.") }
    }
    private func installButton(_ entry: MangaExtensionDescriptor, title: String) -> some View {
        Button { Task { await store.install(entry) } } label: {
            HStack { Text(title); if store.installing == entry.id { Spacer(); ProgressView() } }
        }.buttonStyle(.borderedProminent).frame(minHeight: 44)
            .disabled(store.busy || !entry.supportsRuntime || (!showMature && entry.adult))
            .accessibilityIdentifier("manga-install-extension")
    }
}
