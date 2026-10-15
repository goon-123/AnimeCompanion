import SwiftUI
import WebKit
import AnimeCore

private struct AddonInstallLink: Identifiable {
    let id = UUID()
    let endpoint: AddonEndpoint
}

/// The directory and configuration pages are their actual websites, not an API
/// mirror. This isolated web session never receives the app's installed links.
struct AddonDirectoryBrowser: View {
    @StateObject private var session: AddonBrowserSession
    @State private var installedNotice: String?
    init(startURL: URL = AddonBrowserLink.directoryURL) {
        _session = StateObject(wrappedValue: AddonBrowserSession(url: startURL))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { session.webView?.goBack() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .disabled(!session.canGoBack).accessibilityLabel("Back in add-on browser")
                Button { session.webView?.goForward() } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .disabled(!session.canGoForward).accessibilityLabel("Forward in add-on browser")
                Text(session.url.host ?? "Add-ons").font(.caption).lineLimit(1).frame(maxWidth: .infinity)
                Button { session.reload() } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                    .accessibilityLabel("Reload add-on browser")
                Link(destination: session.url) { Image(systemName: "safari").frame(width: 44, height: 44) }
                    .accessibilityLabel("Open this page in Safari")
            }.padding(.horizontal, 4)
            if session.loading { ProgressView().progressViewStyle(.linear) }
            if let error = session.error { NoticeView(message: error) { session.reload() }.padding(8) }
            if let installedNotice { Text(installedNotice).font(.caption).foregroundStyle(.mint).padding(8).accessibilityIdentifier("browser-addon-saved") }
            AddonWebView(session: session).accessibilityIdentifier("addon-directory-web-view")
            Text("stremio-addons.net · Third-party pages use their own content filters. Install links open a confirmation here; nothing installs automatically.")
                .font(.caption2).foregroundStyle(.secondary).padding(8)
        }.navigationTitle("Browse add-ons").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Directory") { session.navigate(AddonBrowserLink.directoryURL) }.accessibilityIdentifier("addon-directory-home")
            } }
            .sheet(item: $session.installLink) { link in
                NavigationStack {
                    AddonInstallReview(endpoint: link.endpoint, configure: { url in
                        session.installLink = nil; session.navigate(url)
                    }, installed: { name in
                        installedNotice = "\(name) installed. Manage it in Add-ons & playback."
                        session.installLink = nil
                    })
                }
            }
    }
}

private struct AddonInstallReview: View {
    @EnvironmentObject private var playback: PlaybackStore
    @Environment(\.dismiss) private var dismiss
    let endpoint: AddonEndpoint
    let configure: (URL) -> Void
    let installed: (String) -> Void
    @State private var candidate: InstalledAddon?
    @State private var loading = true
    @State private var error: String?
    @State private var retry = 0
    var body: some View {
        Form {
            Section("Manifest URL") {
                Text(endpoint.manifestURL.absoluteString).font(.caption).textSelection(.enabled)
                    .accessibilityIdentifier("addon-review-url")
                Text("This link may contain private account tokens. It will be stored in this device’s Keychain only if you install it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if loading { ProgressView("Checking manifest…") }
            if let error { Section { Text(error).foregroundStyle(.orange); Button("Retry") { retry += 1 } } }
            if let candidate {
                Section(candidate.manifest.name) {
                    Text(candidate.manifest.capabilitySummary).accessibilityIdentifier("addon-review-capabilities")
                    if let description = PlaybackSourceText.clean(candidate.manifest.description) { Text(description).font(.caption) }
                    AddonCompatibilityText(addon: candidate)
                    if candidate.manifest.behaviorHints?.configurable == true || candidate.manifest.behaviorHints?.configurationRequired == true {
                        Button("Configure on provider website") { configure(endpoint.configurationURL) }
                            .accessibilityIdentifier("addon-review-configure")
                    }
                    Button("Install add-on") {
                        if playback.saveInstallation(candidate) { installed(candidate.manifest.name) }
                        else { error = playback.setupError }
                    }.disabled(candidate.manifest.behaviorHints?.configurationRequired == true || playback.installing)
                        .accessibilityIdentifier("addon-review-install")
                }
            }
        }.navigationTitle("Review add-on").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task(id: retry) {
                loading = true; error = nil; candidate = nil
                defer { loading = false }
                do {
                    let value = try await playback.client.install(endpoint.manifestURL.absoluteString)
                    try Task.checkCancellation(); candidate = value
                } catch is CancellationError {} catch { self.error = error.localizedDescription }
            }
    }
}

struct AddonCompatibilityText: View {
    let addon: InstalledAddon
    var body: some View {
        Group {
            if addon.manifest.behaviorHints?.configurationRequired == true {
                Text("Configuration required. Finish setup on the provider’s page, then tap its install button.").foregroundStyle(.orange)
            }
            if addon.manifest.advertises("stream") {
                Text(addon.supportsAnime ? "Accepts AniList/MAL IDs for native Watch." : "Uses other video IDs. Open an installed catalog or enter the provider’s exact video ID; AniList seasons are not guessed.")
            }
            if !addon.manifest.advertises("stream") { Text("This add-on does not supply video streams. Its catalogs, metadata or subtitles can work with other enabled add-ons.") }
            if addon.manifest.advertises("addon_catalog") { Text("Nested add-on-directory resources are not rendered natively. Browse the website or paste individual manifest links.") }
            Text("VidHub plays direct HTTP(S) video links. Torrent-only, DRM, YouTube IDs and special playback headers need a compatible service or proxy; JavaScript plugins and legacy/IPFS transports are not supported.")
        }.font(.caption).foregroundStyle(.secondary)
    }
}

@MainActor
private final class AddonBrowserSession: ObservableObject {
    @Published var url: URL
    @Published var loading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var error: String?
    @Published var installLink: AddonInstallLink?
    weak var webView: WKWebView?
    init(url: URL) { self.url = url }
    func navigate(_ url: URL) {
        guard AddonBrowserLink.permitsPage(url) else { return }
        self.url = url; error = nil
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-addon-browser-preview"), url.path.hasSuffix("/configure") {
            webView?.loadHTMLString(AddonWebView.configuredPreviewHTML, baseURL: url); return
        }
        #endif
        webView?.load(URLRequest(url: url))
    }
    func reload() {
        error = nil
        if webView?.url == nil { webView?.load(URLRequest(url: url)) } else { webView?.reload() }
    }
}

private struct AddonWebView: UIViewRepresentable {
    @ObservedObject var session: AddonBrowserSession
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator; web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        session.webView = web
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-addon-browser-preview") {
            web.loadHTMLString(Self.previewHTML, baseURL: session.url); return web
        }
        #endif
        web.load(URLRequest(url: session.url)); return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {}
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading(); web.navigationDelegate = nil; web.uiDelegate = nil
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let session: AddonBrowserSession
        init(session: AddonBrowserSession) { self.session = session }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            let topLevel = action.targetFrame?.isMainFrame == true || (action.targetFrame == nil && action.sourceFrame.isMainFrame)
            if topLevel, action.sourceFrame.isMainFrame, let endpoint = AddonBrowserLink.installEndpoint(url) {
                if session.installLink == nil { session.installLink = AddonInstallLink(endpoint: endpoint) }
                decisionHandler(.cancel); return
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-addon-browser-preview") {
                if url.scheme == "about" { decisionHandler(.allow); return }
            }
            #endif
            guard AddonBrowserLink.permitsPage(url) else {
                if topLevel { session.error = "This link needs another app or an unsupported transport. Use an HTTPS manifest install link." }
                decisionHandler(.cancel); return
            }
            if topLevel { session.url = url; session.error = nil }
            if action.targetFrame == nil { webView.load(action.request); decisionHandler(.cancel); return }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // New-window links are handled by the navigation policy in this same
            // isolated browser. Never hand an install scheme to another app.
            if action.sourceFrame.isMainFrame, let url = action.request.url {
                if let endpoint = AddonBrowserLink.installEndpoint(url) {
                    if session.installLink == nil { session.installLink = AddonInstallLink(endpoint: endpoint) }
                } else if AddonBrowserLink.permitsPage(url) { session.navigate(url) }
            }
            return nil
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { session.loading = true }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            session.loading = false; session.canGoBack = webView.canGoBack; session.canGoForward = webView.canGoForward
            if let url = webView.url, AddonBrowserLink.permitsPage(url) { session.url = url }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
        private func fail(_ error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            session.loading = false
            session.error = "The page could not load. Retry or open it in Safari, then paste its install link here."
        }
    }
    #if DEBUG
    private static let previewHTML = """
    <html><meta name="viewport" content="width=device-width"><body style="background:#111;color:white;font:20px system-ui;padding:20px">
    <h1>Add-on directory preview</h1><p>Offline fixture · no external requests</p>
    <p><a style="color:cyan" href="stremio://addon.example/catalog/manifest.json">Install catalog</a></p>
    <p><a style="color:cyan" target="_blank" href="https://web.stremio.com/#/addons?addon=https%3A%2F%2Faddon.example%2Fimdb%2Fmanifest.json%3Fkey%3Dopaque%252Btoken">Install IMDb sources</a></p>
    <p><a style="color:cyan" href="stremio://addon.example/subtitles/manifest.json">Install subtitles</a></p>
    <p><a style="color:cyan" href="stremio://addon.example/configure-first/manifest.json">Configure provider</a></p>
    </body></html>
    """
    fileprivate static let configuredPreviewHTML = """
    <html><meta name="viewport" content="width=device-width"><body style="background:#111;color:white;font:20px system-ui;padding:20px">
    <h1>Provider configuration preview</h1><p><a style="color:cyan" href="stremio://addon.example/configured/opaque%2Btoken/manifest.json">Install configured provider</a></p>
    </body></html>
    """
    #endif
}
