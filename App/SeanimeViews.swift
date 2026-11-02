import SwiftUI
import WebKit
import AnimeCore

struct SeanimeSettingsView: View {
    @EnvironmentObject private var seanime: SeanimeStore
    @State private var manifestURL = ""
    @State private var candidate: SeanimeInstallation?
    @State private var busy = false
    @State private var notice: String?
    @State private var marketplace = false
    @State private var work: Task<Void, Never>?
    @FocusState private var editing: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                    Button { editing = false; marketplace = true } label: {
                        destinationTile("Discover providers", detail: "Seanime Marketplace", icon: "globe")
                    }.accessibilityIdentifier("seanime-marketplace")
                    NavigationLink { SeanimeSearchView() } label: {
                        destinationTile("Search releases", detail: "All enabled providers", icon: "magnifyingglass")
                    }.accessibilityIdentifier("seanime-search")
                    NavigationLink { TorBoxSettingsView() } label: {
                        destinationTile("TorBox", detail: seanime.hasTorBoxKey ? "Connected · key saved" : "Connect your account", icon: "cloud")
                    }.accessibilityIdentifier("seanime-torbox-settings")
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 14) {
                    Label("Install a provider", systemImage: "plus.circle.fill").font(.headline)
                    Text("Paste an extension JSON URL, then review its code and network access.").font(.subheadline).foregroundStyle(.secondary)
                    TextField("Seanime extension JSON URL", text: $manifestURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .focused($editing).submitLabel(.done).onSubmit { editing = false }
                        .padding(14).background(Theme.background, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("seanime-manifest-url")
                    HStack {
                        PasteButton(payloadType: String.self) { values in if let value = values.first { manifestURL = value } }
                        Spacer()
                        if busy { ProgressView() }
                        Button("Review extension") { review() }.buttonStyle(.borderedProminent)
                            .disabled(busy || manifestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("seanime-review")
                    }
                }.padding(20).surfacePanel()
                HStack {
                    Text("Your providers").font(.title2.bold())
                    Spacer()
                    Text("\(seanime.installations.count) installed").font(.subheadline).foregroundStyle(.secondary)
                }
                if seanime.installations.isEmpty {
                    ContentUnavailableView("Add your first provider", systemImage: "puzzlepiece.extension",
                        description: Text("Browse the marketplace or paste a provider URL above. Installed providers search independently on this device."))
                        .padding().surfacePanel()
                }
                ForEach(seanime.installations) { installation in providerCard(installation) }
                if let notice { Label(notice, systemImage: "info.circle").font(.subheadline).accessibilityIdentifier("seanime-notice") }
                if let error = seanime.error { Label(error, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(.orange) }
                NavigationLink { SeanimeSafetyView() } label: {
                    Label("Compatibility & privacy", systemImage: "checkmark.shield").font(.subheadline).frame(minHeight: 44)
                }
            }.frame(maxWidth: 860).padding(20).frame(maxWidth: .infinity)
        }.background(Theme.background)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Torrent extensions").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $candidate) { value in
                AppNavigationStack { SeanimeInstallReview(installation: value) {
                    if seanime.install($0) { candidate = nil; manifestURL = ""; notice = "Provider saved. Configure it or run a test search below." }
                } }
            }
            .sheet(isPresented: $marketplace) {
                AppNavigationStack { SeanimeMarketplaceView { value in manifestURL = value; marketplace = false } }
            }
            .onDisappear { work?.cancel() }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "puzzlepiece.extension.fill").font(.system(size: 32)).foregroundStyle(Theme.accent)
                    .frame(width: 68, height: 68).background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your release sources").font(.title.bold())
                    Text("Seanime providers, made for your device.").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 16) {
                Label("\(seanime.installations.filter(\.enabled).count) enabled", systemImage: "checkmark.circle.fill")
                Label("On-device search", systemImage: "iphone")
            }.font(.caption.weight(.medium)).foregroundStyle(Theme.accent)
            Text("Search providers together or test them individually. Each has its own preferences and approved hosts.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
    private func destinationTile(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(Theme.accent).frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, minHeight: 86, alignment: .leading).surfacePanel()
    }
    private func providerCard(_ installation: SeanimeInstallation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shippingbox.fill").font(.title2).foregroundStyle(Theme.accent)
                    .frame(width: 52, height: 52).background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text(installation.manifest.name).font(.headline)
                    Text("v\(installation.manifest.version) · \(installation.manifest.language)").font(.caption).foregroundStyle(.secondary)
                    Text(installation.needsConfiguration ? "Setup needed" : (installation.enabled ? "Enabled" : "Disabled"))
                        .font(.caption.weight(.semibold)).foregroundStyle(installation.needsConfiguration ? .orange : Theme.accent)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Toggle("Enable \(installation.manifest.name)", isOn: Binding(get: {
                    seanime.installations.first { $0.id == installation.id }?.enabled ?? false
                }, set: { seanime.setEnabled(installation.id, enabled: $0) })).labelsHidden()
                    .accessibilityLabel("Enable \(installation.manifest.name)")
            }
            if let description = PlaybackSourceText.clean(installation.manifest.description, maximumLines: 2, maximumCharacters: 300) {
                Text(description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack {
                Label("\(installation.allowedHosts.count) approved hosts", systemImage: "network")
                if installation.adult { Text("Adult provider") }
            }.font(.caption).foregroundStyle(.secondary)
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { providerActions(installation) }
                VStack(alignment: .leading, spacing: 12) { providerActions(installation) }
            }
        }.padding(20).surfacePanel()
    }
    @ViewBuilder private func providerActions(_ installation: SeanimeInstallation) -> some View {
        NavigationLink { SeanimeConfigurationView(installation: installation) } label: {
            Label("Configure", systemImage: "slider.horizontal.3").frame(minHeight: 44)
        }.buttonStyle(.bordered)
        NavigationLink { SeanimeSearchView(preferredProvider: installation.id) } label: {
            Label("Test search", systemImage: "magnifyingglass").frame(minHeight: 44)
        }.buttonStyle(.borderedProminent).disabled(!installation.enabled)
        Menu {
            Button("Remove \(installation.manifest.name)", role: .destructive) { seanime.remove(installation.id) }
        } label: { Image(systemName: "ellipsis.circle").font(.title2).frame(width: 44, height: 44) }
            .accessibilityLabel("Manage \(installation.manifest.name)")
    }
    private func review() {
        editing = false; work?.cancel()
        let url = manifestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        work = Task {
            busy = true; notice = nil; defer { busy = false }
            do { let value = try await seanime.client.inspect(url); try Task.checkCancellation(); candidate = value }
            catch is CancellationError {} catch { notice = error.localizedDescription }
        }
    }
}

private struct SeanimeSafetyView: View {
    var body: some View {
        Form {
            Section("On-device compatibility") {
                Text("Supports torrent-provider JavaScript/TypeScript using regular search, not Seanime Smart Search or automatic season matching. Other plugin types and some runtime APIs are unsupported. No Real-Debrid integration or local torrent engine is included.")
            }
            Section("Execution & account safety") {
                Text("Install only code you trust. Reviewed source snapshots are saved on this device; nothing updates or executes silently. The worker has no app credentials or tracking access. Only bounded HTTPS GETs to approved hosts are bridged; direct web networking, private-address URLs, redirects and unsupported runtime APIs are blocked.")
                Text("The host allowlist is not a DNS firewall: only approve domains you trust. Third-party providers may log searches. Filename/episode hints are approximate; always verify the selected torrent and file.")
                Text("Only native code contacts TorBox. Each add/download requires your explicit action and may use account limits. While an expanded release is preparing, its status updates automatically in the foreground; checks never resubmit it.")
                Text("Known adult providers follow Show adult anime. Other providers may return unrated content. Marketplace web pages use the website’s own filters.")
                NavigationLink("Runtime licenses") { SeanimeLicensesView() }
            }.font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("Compatibility & privacy").navigationBarTitleDisplayMode(.inline)
    }
}

private struct SeanimeInstallReview: View {
    @Environment(\.dismiss) private var dismiss
    @State var installation: SeanimeInstallation
    let install: (SeanimeInstallation) -> Void
    var body: some View {
        Form {
            Section(installation.manifest.name) {
                Text(installation.manifestURL.absoluteString).font(.caption).textSelection(.enabled)
                Text(PlaybackSourceText.clean(installation.manifest.description, maximumLines: 8, maximumCharacters: 2000) ?? "Seanime torrent provider")
                Text("This installs executable third-party code, not a Stremio HTTP manifest. TorBox keys and app tracking data are never passed to it.").font(.caption).foregroundStyle(.secondary)
                Text("Approved network hosts: \(installation.allowedHosts.joined(separator: ", "))").font(.caption).accessibilityIdentifier("seanime-review-hosts")
                Text("\(installation.source.utf8.count) bytes of reviewed source · regular search only").font(.caption)
                DisclosureGroup("Source preview (first 8,000 characters)") { Text(String(installation.source.prefix(8000))).font(.caption.monospaced()).textSelection(.enabled) }
                if installation.manifest.semverConstraint != nil { Text("Seanime version constraints do not guarantee compatibility with this smaller runtime.").font(.caption).foregroundStyle(.orange) }
                Toggle("Adult provider", isOn: $installation.adult)
                Button("Trust code & install") { install(installation) }.accessibilityIdentifier("seanime-install-confirm")
            }
        }.navigationTitle("Review Seanime extension").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}

private struct SeanimeConfigurationView: View {
    @EnvironmentObject private var seanime: SeanimeStore
    @Environment(\.dismiss) private var dismiss
    @State var installation: SeanimeInstallation
    @State private var hosts = ""
    var body: some View {
        Form {
            Section("Provider preferences") {
                ForEach(Array((installation.manifest.userConfig?.fields ?? []).enumerated()), id: \.offset) { _, field in
                    let value = Binding(get: { installation.preferences[field.name] ?? "" }, set: { installation.preferences[field.name] = $0 })
                    if let options = field.options, !options.isEmpty {
                        Picker(field.label ?? field.name, selection: value) { ForEach(Array(options.enumerated()), id: \.offset) { _, option in Text(option.label ?? option.value).tag(option.value) } }
                    } else { TextField(field.label ?? field.name, text: value).textInputAutocapitalization(.never).autocorrectionDisabled() }
                }
                Toggle("Adult provider", isOn: $installation.adult)
            }
            Section("Approved public HTTPS hosts") {
                TextField("Hosts separated by commas", text: $hosts, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("Changing a provider’s API/feed URL does not silently approve a new host. Add it here only if you trust it. No cookies, app tokens, TorBox credentials, POSTs or redirects are available to extensions.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text(installation.manifestURL.absoluteString).font(.caption).textSelection(.enabled)
                Text("To update code, paste this manifest URL in settings and review/install the new snapshot. Disable/remove affects this device, not TorBox’s cloud torrents.").font(.caption).foregroundStyle(.secondary)
                Button("Save provider configuration") {
                    let values = hosts.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
                    guard values.allSatisfy({ SeanimeNetworkPolicy.publicHost($0) != nil }) else { seanime.error = SeanimeError.invalidNetwork.localizedDescription; return }
                    installation.allowedHosts = Array(Set(values.map { $0.lowercased() })).sorted()
                    if seanime.update(installation) { dismiss() }
                }
                if let error = seanime.error { Text(error).foregroundStyle(.orange) }
            }
        }.navigationTitle("Configure provider").navigationBarTitleDisplayMode(.inline)
            .onAppear { hosts = installation.allowedHosts.joined(separator: ", ") }
    }
}

struct SeanimeSearchView: View {
    @EnvironmentObject private var seanime: SeanimeStore
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var search = SeanimeSearchModel()
    var anime: Anime? = nil
    var episode: Int = 1
    var preferredProvider: UUID? = nil
    var body: some View {
        ScrollView {
            SeanimeSourcesSections(search: search, anime: anime, episode: episode)
                .frame(maxWidth: 780).padding(16).padding(.bottom, 16).frame(maxWidth: .infinity)
        }.background(Theme.background).accessibilityIdentifier("stream-picker-scroll")
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Find streams").navigationBarTitleDisplayMode(.inline)
            .task(id: "\(seanime.revision)-\(store.includeAdult)") {
                search.configure(store: seanime, anime: anime, allowAdult: store.includeAdult)
                if let preferredProvider { search.selectProvider(preferredProvider) }
                else if anime != nil { search.search() }
            }
            .onChange(of: scenePhase) { _, phase in
                    if phase == .background { search.pause() }
                    else if phase == .active { search.resumeIfNeeded() }
                }
            .onDisappear { search.stop() }
    }
}

/// Sections share their parent's lifecycle; scrolling a row offscreen must not
/// cancel another provider or restart the whole search.
struct SeanimeSourcesSections: View {
    @ObservedObject var search: SeanimeSearchModel
    var anime: Anime? = nil
    var episode: Int = 1
    var restart = false
    var resultFilter = ""
    var showsAudioControls = true
    @AppStorage("playback.audioFilter") private var audioValue = StreamAudioFilter.all.rawValue
    @AppStorage("playback.torrentSort") private var sortValue = TorrentSort.seeders.rawValue
    @State private var editingSearch = false
    @State private var releaseInfo: SeanimeSearchModel.Choice?
    @FocusState private var editing: Bool
    private var sort: TorrentSort { TorrentSort(rawValue: sortValue) ?? .seeders }
    private var visible: [SeanimeSearchModel.Choice] {
        let audio = StreamAudioFilter(rawValue: audioValue) ?? .all
        let filter = resultFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = search.results.filter { value in
            return audio.includes(value.audio) && (filter.isEmpty ||
                (value.torrent.name + " " + value.provider.manifest.name + " " + value.audio.searchableText +
                 " " + (value.torrent.formattedSize ?? "")).localizedCaseInsensitiveContains(filter))
        }
        return sort.sorted(filtered, torrent: { $0.torrent }, audio: { $0.audio })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                StreamPickerHeading(title: "TorBox releases", count: visible.count, loading: search.loading, countID: "seanime-result-count")
                if !search.providers.isEmpty { sortMenu }
            }
            if search.providers.isEmpty {
                StreamPickerCard {
                    Text("No torrent providers enabled").font(.subheadline.weight(.semibold))
                    NavigationLink("Manage Seanime extensions") { SeanimeSettingsView() }
                }
            } else {
                providerStatus
                if anime == nil {
                    searchPanel
                } else {
                    DisclosureGroup("Edit torrent search", isExpanded: $editingSearch) { searchPanel.padding(.top, 8) }
                        .font(.subheadline).padding(.horizontal, 4).accessibilityIdentifier("seanime-edit-search")
                }
                if showsAudioControls {
                    Picker("Audio language", selection: $audioValue) {
                        ForEach(StreamAudioFilter.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("seanime-audio-filter")
                }
                if search.loading {
                    HStack {
                        Text("Searching \(search.remaining) \(search.remaining == 1 ? "provider" : "providers")…").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel search") { search.stop() }.font(.caption)
                    }.padding(.horizontal, 4)
                }
                ForEach(Array(search.errors.enumerated()), id: \.offset) { _, message in
                    StreamPickerCard {
                        Text(message).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("seanime-search-error")
                        Button("Retry torrent search") { runSearch() }.font(.subheadline)
                    }
                }
                if search.searched && !search.loading && visible.isEmpty {
                    let failed = search.states.values.contains { $0.failed }
                    StreamPickerEmptyState(title: search.results.isEmpty ? (failed ? "Some providers couldn't search" : "No releases found") : "No matching releases",
                        message: search.results.isEmpty ? (failed ? "Check each provider's status above. Configure its hosts or preferences, then retry." : "Try another title or torrent provider.") : "Try All audio or clear the release filter. Unlisted audio may still include your language.",
                        symbol: failed ? "exclamationmark.triangle" : "magnifyingglass")
                    if !search.results.isEmpty, audioValue != StreamAudioFilter.all.rawValue {
                        Button("Show all audio") { audioValue = StreamAudioFilter.all.rawValue }.font(.subheadline)
                    }
                }
                LazyVStack(spacing: 12) {
                    ForEach(visible) { choice in
                        releaseCard(choice)
                    }
                }
            }
        }.sheet(item: $releaseInfo) { choice in
            AppNavigationStack {
                Form {
                    Section(choice.provider.manifest.name) {
                        PlaybackAudioBadge(audio: choice.audio)
                        Text(choice.torrent.name).textSelection(.enabled)
                        Text("\(choice.torrent.formattedSize ?? "Size unlisted") · \(choice.torrent.seederSummary)").font(.caption).foregroundStyle(.secondary)
                    }
                    Section { Text("Release titles and audio hints are supplied by this provider. Verify the episode and file before playing.").font(.caption).foregroundStyle(.secondary) }
                }.navigationTitle("Release information").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { releaseInfo = nil } } }
            }
        }
    }
    private var providerStatus: some View {
        StreamPickerCard {
            if search.providers.count > 1 {
                Picker("Providers", selection: Binding(get: { search.providerID }, set: { search.selectProvider($0) })) {
                    Text("All enabled providers").tag(Optional<UUID>.none)
                    ForEach(search.providers) { Text($0.manifest.name).tag(Optional($0.id)) }
                }.accessibilityIdentifier("seanime-provider-picker")
            }
            ForEach(search.providers.filter { search.providerID == nil || search.providerID == $0.id }) { provider in
                let state = search.states[provider.id]
                HStack(spacing: 10) {
                    if state == .searching { ProgressView().controlSize(.small) }
                    else { Image(systemName: state?.symbol ?? "shippingbox").foregroundStyle(state?.failed == true ? .orange : Theme.accent) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(provider.manifest.name).font(.subheadline.weight(.medium))
                        Text(state?.label ?? (provider.needsConfiguration ? "Setup needed" : "Ready to search"))
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if state?.failed == true || provider.needsConfiguration {
                        NavigationLink { SeanimeConfigurationView(installation: provider) } label: {
                            Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                        }.accessibilityLabel("Configure \(provider.manifest.name)")
                    }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("seanime-provider-status")
            }
        }
    }
    private var sortMenu: some View {
        Menu {
            Picker("Sort torrents", selection: Binding(get: { sort.rawValue }, set: { sortValue = $0 })) {
                ForEach(TorrentSort.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Section {
                Text("English audio first")
                Text("Your sort is saved as the default")
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down").font(.subheadline).frame(minHeight: 44)
        }
        .accessibilityLabel("Sort torrents")
        .accessibilityValue("\(sort.label). English audio first. Saved default.")
        .accessibilityIdentifier("seanime-torrent-sort")
    }
    private var searchPanel: some View {
        StreamPickerCard {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Anime or release title", text: $search.query).focused($editing).submitLabel(.search).onSubmit { runSearch() }
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("seanime-query")
                Button { runSearch() } label: { Image(systemName: "arrow.right.circle.fill").font(.title2) }
                    .disabled(search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || search.loading)
                    .accessibilityLabel("Search torrent releases").accessibilityIdentifier("seanime-run-search")
            }

        }
    }
    private func releaseCard(_ choice: SeanimeSearchModel.Choice) -> some View {
        let selected = search.selected == choice.id
        return StreamPickerCard {
            HStack(alignment: .top, spacing: 4) {
                Button { search.selected = selected ? nil : choice.id } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(choice.provider.manifest.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Spacer(minLength: 8)
                            Image(systemName: selected ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        Text(choice.torrent.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(selected ? 3 : 2)
                        PlaybackAudioBadge(audio: choice.audio, compact: true)
                        Text("\(choice.torrent.formattedSize ?? "Size unlisted") · \(choice.torrent.seederSummary)").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("seanime-torrent-result")
                    .accessibilityLabel("\(choice.provider.manifest.name) · \(choice.audio.label) · \(choice.torrent.name) · \(choice.torrent.formattedSize ?? "Size unlisted") · \(choice.torrent.seederSummary) · \(selected ? "Hide files" : "Show TorBox files")")
                Button { releaseInfo = choice } label: { Image(systemName: "info.circle").frame(width: 44, height: 44) }
                    .buttonStyle(.borderless).accessibilityLabel("Release information")
                    .accessibilityIdentifier("seanime-release-info")
            }
            if selected {
                Divider()
                TorBoxPlaybackControls(providerID: choice.provider.id, torrent: choice.torrent, anime: anime, episode: episode, restart: restart)
                    .id("\(choice.id)-\(episode)")
            }
        }
    }
    private func runSearch() { editing = false; editingSearch = false; search.search() }
}

private struct SeanimeLicensesView: View {
    var body: some View {
        ScrollView { Text(notices).font(.caption.monospaced()).textSelection(.enabled).padding() }.navigationTitle("Runtime licenses")
    }
    private var notices: String {
        guard let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "txt", subdirectory: "SeanimeRuntimeResources"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "Runtime license notices unavailable." }
        return text
    }
}

private struct SeanimeMarketplaceView: View {
    @Environment(\.dismiss) private var dismiss
    let choose: (String) -> Void
    @State private var error: String?
    var body: some View {
        VStack {
            Text("Seanime Community Marketplace · Use Copy Link, return, then Paste in settings. JSON links can be selected directly. The website controls its own content filters.").font(.caption).foregroundStyle(.secondary).padding(8)
            if let error {
                Text(error).font(.caption).foregroundStyle(.orange).padding(8)
                Link("Open marketplace in Safari", destination: URL(string: "https://bas1874.github.io/Seanime-Marketplace/")!)
            }
            SeanimeMarketplaceWeb(choose: choose, failed: { error = $0 })
        }.navigationTitle("Seanime Marketplace").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }
}
private struct SeanimeMarketplaceWeb: UIViewRepresentable {
    let choose: (String) -> Void
    let failed: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(choose: choose, failed: failed) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config); web.navigationDelegate = context.coordinator; web.uiDelegate = context.coordinator
        web.isOpaque = false; web.backgroundColor = .clear
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: URL(string: "https://bas1874.github.io/Seanime-Marketplace/")!)); return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {}
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) { web.stopLoading(); web.navigationDelegate = nil; web.uiDelegate = nil }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let choose: (String) -> Void
        let failed: (String) -> Void
        init(choose: @escaping (String) -> Void, failed: @escaping (String) -> Void) { self.choose = choose; self.failed = failed }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { failed("The marketplace page could not load. Open it in Safari and paste an extension JSON link here.") }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, AddonBrowserLink.permitsPage(url) else { decisionHandler(.cancel); return }
            if action.sourceFrame.isMainFrame, action.targetFrame?.isMainFrame != false, url.path.hasSuffix(".json") { choose(url.absoluteString); decisionHandler(.cancel); return }
            if action.targetFrame == nil { webView.load(action.request); decisionHandler(.cancel); return }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if action.sourceFrame.isMainFrame, let url = action.request.url, AddonBrowserLink.permitsPage(url) {
                if url.path.hasSuffix(".json") { choose(url.absoluteString) } else { webView.load(action.request) }
            }
            return nil
        }
    }
}
