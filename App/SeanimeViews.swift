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
    @StateObject private var search = SeanimeSearchModel()
    var anime: Anime? = nil
    var episode: Int = 1
    var body: some View {
        List { SeanimeSourcesSections(search: search, anime: anime, episode: episode) }
            .navigationTitle("Find streams").navigationBarTitleDisplayMode(.inline)
            .task(id: "\(seanime.revision)-\(store.includeAdult)") {
                search.configure(store: seanime, anime: anime, allowAdult: store.includeAdult)
                if anime != nil { search.search() }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { search.stop() } }
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
    @AppStorage("playback.audioFilter") private var audioValue = StreamAudioFilter.all.rawValue
    @FocusState private var editing: Bool
    private var visible: [SeanimeSearchModel.Choice] {
        let audio = StreamAudioFilter(rawValue: audioValue) ?? .all
        return search.results.enumerated().filter { audio.includes($0.element.audio) }
            .sorted { lhs, rhs in
                let l = lhs.element.audio.english
                let r = rhs.element.audio.english
                return l != r ? l : lhs.offset < rhs.offset
            }.map(\.element)
    }
    var body: some View {
        Section("Torrent providers · TorBox") {
            if search.providers.isEmpty {
                Text("Enable a Seanime torrent provider in Settings to include torrent results.").font(.caption).foregroundStyle(.secondary)
                NavigationLink("Manage providers & TorBox") { SeanimeSettingsView() }
            } else {
                TextField("Search release titles", text: $search.query).focused($editing).submitLabel(.search).onSubmit { runSearch() }
                    .autocorrectionDisabled().accessibilityIdentifier("seanime-query")
                if search.providers.count > 1 {
                    Picker("Providers", selection: Binding(get: { search.providerID }, set: { search.selectProvider($0) })) {
                        Text("All enabled providers").tag(Optional<UUID>.none)
                        ForEach(search.providers) { Text($0.manifest.name).tag(Optional($0.id)) }
                    }.accessibilityIdentifier("seanime-provider-picker")
                }
                Button(search.providers.count > 1 && search.providerID == nil ? "Search all torrent providers" : "Search torrent releases") { runSearch() }
                    .disabled(search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || search.loading)
                    .accessibilityIdentifier("seanime-run-search")
                if search.loading {
                    ProgressView("Searching · \(search.remaining) providers remaining")
                    Button("Cancel search") { search.stop() }
                }
                if search.searched || !search.results.isEmpty {
                    Picker("Torrent audio", selection: $audioValue) {
                        ForEach(StreamAudioFilter.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("seanime-audio-filter")
                    Text("\(visible.count) releases · English audio listed first").font(.caption).foregroundStyle(.secondary)
                    if !search.loading && visible.isEmpty {
                        Text(search.results.isEmpty ? "No releases found. Try another title or provider." : "No releases match the audio filter. Unlisted releases may still include your language.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(search.errors.enumerated()), id: \.offset) { _, message in
                    Text(message).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("seanime-search-error")
                }
                Text("Select a release to see TorBox files here. Check the episode and audio before playing; batches may contain several episodes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        ForEach(visible) { choice in
            Section {
                Button { search.selected = search.selected == choice.id ? nil : choice.id } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(choice.provider.manifest.name).font(.caption).foregroundStyle(.secondary)
                        PlaybackAudioBadge(audio: choice.audio)
                        Text(choice.torrent.name).font(.headline).foregroundStyle(.primary)
                        Text("\(choice.torrent.formattedSize ?? "Size unlisted") · \(choice.torrent.seeders ?? 0) seeders")
                            .font(.caption).foregroundStyle(.secondary)
                        Label(search.selected == choice.id ? "Hide files" : "Show TorBox files", systemImage: search.selected == choice.id ? "chevron.up" : "play.rectangle")
                            .font(.subheadline)
                    }.padding(.vertical, 5)
                }.accessibilityIdentifier("seanime-torrent-result")
                if search.selected == choice.id {
                    TorBoxPlaybackControls(providerID: choice.provider.id, torrent: choice.torrent, anime: anime, episode: episode, restart: restart)
                        .id("\(choice.id)-\(episode)")
                }
            }
        }
    }
    private func runSearch() { editing = false; search.search() }
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
