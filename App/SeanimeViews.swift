import SwiftUI
import WebKit
import AnimeCore

struct SeanimeSettingsView: View {
    @EnvironmentObject private var seanime: SeanimeStore
    @State private var key = ""
    @State private var manifestURL = ""
    @State private var candidate: SeanimeInstallation?
    @State private var busy = false
    @State private var notice: String?
    @State private var marketplace = false
    @State private var work: Task<Void, Never>?
    private enum Editing { case key, manifest }
    @FocusState private var editing: Editing?
    var body: some View {
        Form {
            Section("TorBox · no Seanime server") {
                Text(seanime.hasTorBoxKey ? "TorBox API key saved securely on this device." : "Enter your existing TorBox API key. Extensions never receive it.").font(.caption).foregroundStyle(.secondary)
                SecureField("TorBox API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($editing, equals: .key).submitLabel(.done).onSubmit { editing = nil }.accessibilityIdentifier("torbox-api-key")
                Button("Save TorBox key") { if seanime.saveKey(key) { key = ""; editing = nil; notice = "TorBox key saved." } }
                    .disabled(key.isEmpty || busy).accessibilityIdentifier("torbox-save-key")
                Button("Verify TorBox connection") {
                    work = Task { busy = true; defer { busy = false }
                        do { try await seanime.torBox().verify(); notice = "TorBox connected. No torrents were added." }
                        catch is CancellationError {} catch { notice = error.localizedDescription }
                    }
                }.disabled(!seanime.hasTorBoxKey || busy).accessibilityIdentifier("torbox-verify")
                Button("Remove saved TorBox key", role: .destructive) { if seanime.saveKey("") { notice = "TorBox key removed from this device." } }
                    .disabled(!seanime.hasTorBoxKey || busy)
                Link("Open TorBox account", destination: URL(string: "https://torbox.app/settings")!)
            }
            Section("Seanime torrent providers") {
                Button("Browse Seanime Marketplace") { editing = nil; marketplace = true }.accessibilityIdentifier("seanime-marketplace")
                TextField("Paste Seanime extension JSON URL", text: $manifestURL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL).focused($editing, equals: .manifest).submitLabel(.done).onSubmit { editing = nil }.accessibilityIdentifier("seanime-manifest-url")
                PasteButton(payloadType: String.self) { values in if let value = values.first { manifestURL = value } }
                Button("Review extension") {
                    editing = nil
                    work = Task { busy = true; notice = nil; defer { busy = false }
                        do { let value = try await seanime.client.inspect(manifestURL); try Task.checkCancellation(); candidate = value }
                        catch is CancellationError {} catch { notice = error.localizedDescription }
                    }
                }.disabled(busy || manifestURL.isEmpty).accessibilityIdentifier("seanime-review")
                if busy { ProgressView() }
                NavigationLink("Search installed Seanime providers") { SeanimeSearchView() }.accessibilityIdentifier("seanime-search")
                Text("Only torrent-provider JavaScript/TypeScript is supported in this first on-device runtime. Search uses the provider’s regular search—not Seanime Smart Search or automatic season matching. Other runtime APIs may be unsupported.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Installed · \(seanime.installations.count)") {
                ForEach(seanime.installations) { installation in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(installation.manifest.name).font(.headline)
                        Text("\(installation.manifest.version) · \(installation.manifest.language)").font(.caption).foregroundStyle(.secondary)
                        Toggle("Enable \(installation.manifest.name)", isOn: Binding(get: {
                            seanime.installations.first { $0.id == installation.id }?.enabled ?? false
                        }, set: { enabled in var value = installation; value.enabled = enabled; _ = seanime.update(value) }))
                        NavigationLink("Configure \(installation.manifest.name)") { SeanimeConfigurationView(installation: installation) }
                        Button("Remove \(installation.manifest.name)", role: .destructive) { seanime.remove(installation.id) }
                    }
                }
            }
            if let notice { Section { Text(notice).font(.caption).accessibilityIdentifier("seanime-notice") } }
            if let error = seanime.error { Section { Text(error).foregroundStyle(.orange) } }
            Section("Execution & account safety") {
                Text("Install only code you trust. Reviewed source snapshots are saved on this device; nothing updates or executes silently. The worker has no app credentials or tracking access. Only bounded HTTPS GETs to approved hosts are bridged; direct web networking, private-address URLs, redirects and unsupported runtime APIs are blocked.")
                Text("The host allowlist is not a DNS firewall: only approve domains you trust. Third-party providers may log searches. Filename/episode hints are approximate; always verify the selected torrent and file.")
                Text("TorBox is contacted only by native code. Adding a torrent requires confirmation and may use account storage/download limits. File readiness is refreshed manually. No Real-Debrid integration or local torrent engine is included.")
                Text("Known adult providers follow Show adult anime. Other providers may return unrated content. Marketplace web pages use the website’s own filters.")
                NavigationLink("Runtime licenses") { SeanimeLicensesView() }
            }.font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("Seanime & TorBox").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $candidate) { value in
                NavigationStack { SeanimeInstallReview(installation: value) { if seanime.install($0) { candidate = nil; manifestURL = ""; notice = "Seanime extension installed." } } }
            }
            .sheet(isPresented: $marketplace) {
                NavigationStack { SeanimeMarketplaceView { value in manifestURL = value; marketplace = false } }
            }
            .onDisappear { work?.cancel(); key = "" }
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
    var anime: Anime? = nil
    var episode: Int = 1
    @State private var providerID: UUID?
    @State private var query = ""
    @State private var results: [SeanimeTorrent] = []
    @State private var loading = false
    @State private var error: String?
    @State private var selected: SeanimeTorrent?
    @State private var task: Task<Void, Never>?
    @State private var runner: SeanimeRunner?
    @State private var audio = StreamAudioFilter.all
    @State private var lookupID = UUID()
    @FocusState private var editing: Bool
    private var providers: [SeanimeInstallation] { seanime.installations.filter { $0.enabled && (store.includeAdult || !$0.adult) } }
    private var provider: SeanimeInstallation? { providers.first { $0.id == providerID } }
    private var visible: [SeanimeTorrent] {
        results.enumerated().filter { audio.includes(StreamAudioInfo(texts: [$0.element.name])) }
            .sorted { lhs, rhs in
                let l = StreamAudioInfo(texts: [lhs.element.name]).english, r = StreamAudioInfo(texts: [rhs.element.name]).english
                return l != r ? l : lhs.offset < rhs.offset
            }.map(\.element)
    }
    var body: some View {
        List {
            Section("On-device provider search") {
                if let anime { Text("\(anime.displayTitle) · Episode \(episode)").font(.headline) }
                Picker("Provider", selection: $providerID) {
                    Text("Choose provider").tag(Optional<UUID>.none)
                    ForEach(providers) { Text($0.manifest.name).tag(Optional($0.id)) }
                }.accessibilityIdentifier("seanime-provider-picker")
                TextField("Search release titles", text: $query).focused($editing).submitLabel(.search).onSubmit { search() }
                    .autocorrectionDisabled().accessibilityIdentifier("seanime-query")
                Button("Search on this device") { search() }.disabled(provider == nil || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loading)
                    .accessibilityIdentifier("seanime-run-search")
                if loading { ProgressView("Running provider…"); Button("Cancel search") { stop() } }
                NavigationLink("Install/configure providers & TorBox") { SeanimeSettingsView() }
                Text("Regular title search. Verify the episode and chosen file manually; no automatic season mapping. Audio badges reflect filenames, not verified tracks.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.orange).accessibilityIdentifier("seanime-search-error") }
            Section("Torrents · \(results.count)") {
                Picker("Audio", selection: $audio) { ForEach(StreamAudioFilter.allCases, id: \.self) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                ForEach(visible) { torrent in
                    Button { selected = torrent } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            PlaybackAudioBadge(audio: StreamAudioInfo(texts: [torrent.name]))
                            Text(torrent.name).font(.headline).foregroundStyle(.primary)
                            Text("\(torrent.formattedSize ?? "Size unlisted") · \(torrent.seeders ?? 0) seeders").font(.caption).foregroundStyle(.secondary)
                            Label("Review in TorBox", systemImage: "play.rectangle").font(.subheadline)
                        }.padding(.vertical, 6)
                    }.accessibilityIdentifier("seanime-torrent-result")
                }
            }
        }.navigationTitle("Seanime sources").navigationBarTitleDisplayMode(.inline)
            .onAppear { if providerID == nil { providerID = providers.first?.id }; if query.isEmpty { query = anime?.title?.romaji ?? anime?.displayTitle ?? "" } }
            .onChange(of: providerID) { _, _ in stop(); results = []; error = nil }
            .onChange(of: seanime.revision) { _, _ in stop(); results = []; if provider == nil { providerID = providers.first?.id } }
            .onChange(of: store.includeAdult) { _, _ in stop(); results = []; if provider == nil { providerID = providers.first?.id } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { stop() } }
            .onDisappear { stop() }
            .sheet(item: $selected) { torrent in
                if let provider { NavigationStack { TorBoxPlaybackView(providerID: provider.id, torrent: torrent, anime: anime, episode: episode) } }
            }
    }
    private func stop() { lookupID = UUID(); task?.cancel(); runner?.cancel(); loading = false }
    private func search() {
        guard let provider, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        stop(); editing = false; loading = true; error = nil; results = []
        let expected = UUID(); lookupID = expected
        let engine = SeanimeRunner(client: seanime.client); runner = engine
        task = Task {
            defer { if lookupID == expected { loading = false } }
            do { let value = try await engine.search(provider, query: query, anime: anime, allowAdult: store.includeAdult); try Task.checkCancellation(); if lookupID == expected { results = value; error = engine.warning } }
            catch is CancellationError {} catch { if lookupID == expected { self.error = error.localizedDescription } }
        }
    }
}

private struct TorBoxPlaybackView: View {
    @EnvironmentObject private var seanime: SeanimeStore
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let providerID: UUID
    let torrent: SeanimeTorrent
    let anime: Anime?
    let episode: Int
    @State private var cachedOnly = true
    @State private var confirmed = false
    @State private var cloudID: Int?
    @State private var cloud: TorBoxTorrent?
    @State private var busy = false
    @State private var error: String?
    @State private var work: Task<Void, Never>?
    @State private var runner: SeanimeRunner?
    private var provider: SeanimeInstallation? { seanime.installations.first { $0.id == providerID && $0.enabled && (store.includeAdult || !$0.adult) } }
    var body: some View {
        List {
            Section {
                Text(torrent.name).font(.headline)
                if let anime { Text("Selected episode · \(anime.displayTitle) · \(episode)").font(.caption) }
                Text("Choose the correct video file yourself, especially for batches. Adding a torrent may use TorBox account limits. Closing this screen does not delete cloud torrents. If submission is interrupted, check TorBox before submitting again.").font(.caption).foregroundStyle(.secondary)
                if cloudID == nil {
                    Toggle("Cached only", isOn: $cachedOnly)
                    Button("Add torrent to TorBox & choose file") { confirmed = true }
                        .disabled(busy || !seanime.hasTorBoxKey || provider == nil).accessibilityIdentifier("torbox-add-torrent")
                } else {
                    Text("TorBox torrent #\(cloudID!) · \(cloud?.download_state ?? "Preparing")").font(.caption)
                    Button("Check TorBox readiness") { load() }.disabled(busy).accessibilityIdentifier("torbox-refresh-files")
                    Button("Forget this local TorBox reference", role: .destructive) { seanime.forgetJob(for: torrent); cloudID = nil; cloud = nil }
                        .disabled(busy)
                    Text("Forgetting a reference does not delete anything from TorBox. Use this if the cloud torrent was deleted.").font(.caption).foregroundStyle(.secondary)
                }
                if !seanime.hasTorBoxKey { Text("Save your TorBox key in Seanime & TorBox settings first.").foregroundStyle(.orange) }
                if provider == nil { Text("This provider is disabled, removed, or hidden by your content setting.").foregroundStyle(.orange) }
                if busy { ProgressView() }
            }
            if let cloud {
                Section("Choose video file") {
                    if !cloud.ready { Text("TorBox is not ready yet. Check readiness later; no automatic resubmission or polling.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(cloud.videoFiles) { file in
                        Button { play(file, cloud: cloud) } label: {
                            VStack(alignment: .leading) { PlaybackAudioBadge(audio: StreamAudioInfo(texts: [file.name])); Text(file.name); Text("Play in VidHub").font(.caption) }
                        }.disabled(!cloud.ready || busy || provider == nil).accessibilityIdentifier("torbox-file-\(file.id)")
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.orange).accessibilityIdentifier("torbox-playback-error") }
            if let message = playback.playerMessage { Text(message).font(.caption).accessibilityIdentifier("torbox-player-message") }
        }.navigationTitle("TorBox playback").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Add this torrent to your TorBox account?", isPresented: $confirmed, titleVisibility: .visible) {
                Button("Confirm add to TorBox") { add() }
            } message: { Text(cachedOnly ? "Cached-only is on. Uncached torrents will not be queued." : "TorBox may download this torrent using your account’s storage and download limits.") }
            .onDisappear { work?.cancel(); runner?.cancel() }
            .onAppear { if cloudID == nil, let id = seanime.job(for: torrent) { cloudID = id; load() } }
            .onChange(of: seanime.revision) { _, _ in work?.cancel(); runner?.cancel(); cloud = nil; cloudID = seanime.job(for: torrent); busy = false }
    }
    private func add() {
        guard cloudID == nil, !busy, let provider else { return }
        busy = true; error = nil
        let engine = SeanimeRunner(client: seanime.client); runner = engine
        work = Task {
            defer { busy = false }
            do {
                let magnet = try await engine.magnet(provider, torrent: torrent, allowAdult: store.includeAdult)
                let client = try seanime.torBox()
                cloudID = try await client.add(magnet: magnet, cachedOnly: cachedOnly)
                if !seanime.recordJob(cloudID!, for: torrent) { error = "The cloud torrent was added, but its local reference could not be saved. Check your TorBox dashboard before submitting again." }
                cloud = try await client.torrent(id: cloudID!)
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    private func load() {
        guard !busy, let cloudID else { return }
        busy = true; error = nil
        work = Task { defer { busy = false }
            do { cloud = try await seanime.torBox().torrent(id: cloudID) }
            catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    private func play(_ file: TorBoxFile, cloud: TorBoxTorrent) {
        guard !busy, provider != nil else { return }; busy = true; error = nil
        work = Task { defer { busy = false }
            do {
                let url = try await seanime.torBox().download(torrent: cloud, fileID: file.id)
                try Task.checkCancellation()
                guard provider != nil, seanime.hasTorBoxKey else { throw SeanimeError.runtime }
                let data = try JSONSerialization.data(withJSONObject: ["name": file.name, "url": url.absoluteString, "behaviorHints": ["filename": file.name]])
                let stream = try JSONDecoder().decode(StremioStream.self, from: data)
                if let anime { await playback.play(stream: stream, anime: anime, episode: episode, subtitle: nil, restart: false) }
                else { await playback.playUntracked(stream: stream, title: file.name) }
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
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
