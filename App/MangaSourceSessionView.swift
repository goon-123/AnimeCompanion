import SwiftUI
import WebKit
import AnimeCore

/// Each installed APK/source gets its own private WebKit profile. The reader
/// never observes Safari, OAuth, anime-provider or other source credentials.
@MainActor
enum MangaWebsiteProfiles {
    static var stores: [String: WKWebsiteDataStore] = [:]
    static func store(_ key: String) -> WKWebsiteDataStore {
        if let value = stores[key] { return value }
        let value = WKWebsiteDataStore.nonPersistent()
        stores[key] = value
        return value
    }
}

struct MangaSourceSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var extensions: MangaExtensionStore
    let source: MangaSourceReference
    var onContinue: () -> Void
    @State private var saving = false
    @State private var browserID = UUID()
    private var key: String? {
        guard let digest = extensions.installed(source.extensionID)?.descriptor.sha256 else { return nil }
        return MangaRuntime.sessionKey(apkSHA256: digest, sourceID: source.sourceID)
    }
    private var home: URL? {
        guard let value = extensions.installed(source.extensionID)?.sources.first(where: { $0.id == source.sourceID })?.homeURL,
              let url = URL(string: value), MangaWebsiteBrowser.allowed(url) else { return nil }
        return url
    }
    var body: some View {
        AppNavigationStack {
            VStack(spacing: 0) {
                Text("If this website asks you to sign in or verify, complete it here. Then tap Use session to retry the source. This private session stays on your iPhone until the app closes.")
                    .font(.footnote).foregroundStyle(.secondary).padding()
                if let key, let home {
                    MangaWebsiteBrowser(key: key, home: home).id(browserID)
                } else {
                    ContentUnavailableView("Website unavailable", systemImage: "globe", description: Text("Reinstall this source or check its address in Source settings."))
                }
            }.navigationTitle(source.name).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "Saving…" : "Use session") { save() }.disabled(saving || key == nil || home == nil)
                            .accessibilityIdentifier("manga-use-source-session")
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Clear website session", role: .destructive) {
                            guard let key else { return }
                            MangaSourceCookieJar.shared.clear(source: key)
                            MangaWebsiteProfiles.stores[key] = nil
                            extensions.sourceSessionChanged(source)
                            browserID = UUID()
                        }.disabled(saving)
                    }
                }
        }.interactiveDismissDisabled(saving)
    }
    private func save() {
        guard let key else { return }
        saving = true
        MangaWebsiteProfiles.store(key).httpCookieStore.getAllCookies { cookies in
            MangaSourceCookieJar.shared.replace(source: key, cookies: cookies)
            extensions.sourceSessionChanged(source)
            saving = false
            dismiss()
            onContinue()
        }
    }
}

private struct MangaWebsiteBrowser: UIViewRepresentable {
    let key: String
    let home: URL
    static func allowed(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443, let host = parts.host else { return false }
        return SeanimeNetworkPolicy.publicHost(host) != nil
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = MangaWebsiteProfiles.store(key)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.customUserAgent = MangaSourceCookieJar.browserUserAgent
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        Task { @MainActor in
            for cookie in MangaSourceCookieJar.shared.cookies(source: key) {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { continuation.resume() }
                }
            }
            web.load(URLRequest(url: home))
        }
        return web
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) { view.stopLoading(); view.navigationDelegate = nil }
    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, MangaWebsiteBrowser.allowed(url) else { decisionHandler(.cancel); return }
            if action.targetFrame == nil { webView.load(action.request); decisionHandler(.cancel) }
            else { decisionHandler(.allow) }
        }
    }
}
