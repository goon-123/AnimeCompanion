import SwiftUI
import WebKit
import AnimeCore

struct MetadataSourcePicker: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Picker("Metadata source", selection: $store.metadataSource) {
            ForEach(MetadataSource.allCases) { Text($0.label).tag($0) }
        }.pickerStyle(.segmented).accessibilityIdentifier("metadata-source-picker")
    }
}

struct LiveChartAnimeView: View {
    @EnvironmentObject private var store: AppStore
    let anime: Anime
    var onSelection: ((Anime) -> Void)? = nil
    @State private var url: URL?
    @State private var matched = false
    @State private var notice: String?
    var body: some View {
        VStack(spacing: 0) {
            if let notice { Text(notice).font(.caption).foregroundStyle(.secondary).padding(10) }
            if let url { LiveChartBrowserView(startURL: url, seedAnime: matched ? anime : nil, onSelection: onSelection).id(url) }
            else { ProgressView("Finding the LiveChart listing…").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.task(id: anime.id) {
            url = nil; matched = false; notice = nil
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-livechart-preview"), anime.id == 1 {
                matched = true; url = LiveChartURL.anime(3418); return
            }
            #endif
            do {
                if let id = try await store.liveChart.liveChartID(aniListID: anime.id) {
                    try Task.checkCancellation(); matched = true; url = LiveChartURL.anime(id)
                } else {
                    try Task.checkCancellation()
                    notice = "No unique LiveChart match yet. Choose the title in search; tracking appears for matched entries."
                    url = LiveChartURL.search(anime.title?.romaji ?? anime.displayTitle)
                }
            } catch is CancellationError {} catch {
                guard !Task.isCancelled else { return }
                notice = "Matching is unavailable. You can still search LiveChart and return to AniList tracking."
                url = LiveChartURL.search(anime.title?.romaji ?? anime.displayTitle)
            }
        }
    }
}

/// LiveChart's actual pages supply metadata. Native tracking always uses the matched AniList ID.
struct LiveChartBrowserView: View {
    @EnvironmentObject private var store: AppStore
    let startURL: URL
    let seedAnime: Anime?
    let onSelection: ((Anime) -> Void)?
    @StateObject private var session: LiveChartSession
    @State private var selectedAnime: Anime?
    @State private var matchedURL: URL?
    @State private var matching = false
    @State private var matchNotice: String?
    @State private var retry = 0
    init(startURL: URL, seedAnime: Anime? = nil, onSelection: ((Anime) -> Void)? = nil) {
        self.startURL = startURL; self.seedAnime = seedAnime; self.onSelection = onSelection
        _session = StateObject(wrappedValue: LiveChartSession(url: startURL))
        _selectedAnime = State(initialValue: seedAnime)
        _matchedURL = State(initialValue: seedAnime == nil ? nil : startURL)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { session.goBack() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .disabled(!session.canGoBack).accessibilityLabel("Back in LiveChart")
                VStack(alignment: .leading, spacing: 2) {
                    Text("LiveChart.me metadata").font(.caption.bold())
                    Text("Tracking · AniList").font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { session.reload() } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }.accessibilityLabel("Reload LiveChart")
                Link(destination: session.url) { Image(systemName: "safari").frame(width: 44, height: 44) }.accessibilityLabel("Open LiveChart in your browser")
            }.padding(.horizontal, 8).background(Theme.surface)
            if session.loading { ProgressView().progressViewStyle(.linear) }
            if let error = session.error {
                NoticeView(message: error) { session.reload() }.padding(8)
            }
            LiveChartWebView(startURL: startURL, session: session).accessibilityIdentifier("livechart-web-view")
        }.background(Theme.background)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let selectedAnime, matchedURL == session.url, store.isVisible(selectedAnime) {
                    CompactTrackingBar(anime: selectedAnime)
                } else if LiveChartURL.animeID(session.url) != nil {
                    VStack(alignment: .leading, spacing: 5) {
                        if matching { ProgressView("Matching this anime to AniList…").font(.caption) }
                        else {
                            Text(matchNotice ?? "No unique AniList match for this LiveChart entry.").font(.caption).foregroundStyle(.secondary)
                            Button("Retry matching") { retry += 1 }.font(.caption)
                        }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.ultraThinMaterial)
                }
            }
            .task(id: "\(session.url.absoluteString)-\(retry)-\(store.includeAdult)") { await match() }
    }
    private func match() async {
        let target = session.url
        selectedAnime = nil; matchedURL = nil; matchNotice = nil; matching = false
        guard let id = LiveChartURL.animeID(target) else { return }
        if target == startURL, let seedAnime {
            if store.isVisible(seedAnime) { selectedAnime = seedAnime; matchedURL = target; onSelection?(seedAnime) }
            else { matchNotice = "This title is hidden by your adult-content setting." }
            return
        }
        matching = true
        defer { if session.url == target { matching = false } }
        do {
            guard let aniListID = try await store.liveChart.aniListID(liveChartID: id) else {
                try Task.checkCancellation()
                matchNotice = "No unique AniList match yet. Browse AniList to track this title without guessing a season."
                return
            }
            let media = try await store.aniList.media(ids: [aniListID])
            try Task.checkCancellation(); guard session.url == target else { return }
            guard let anime = media.first, anime.id == aniListID else { throw ServiceError.invalidResponse }
            guard store.isVisible(anime) else { matchNotice = "This title is hidden by your adult-content setting."; return }
            selectedAnime = anime; matchedURL = target
            onSelection?(anime)
        } catch is CancellationError {} catch {
            guard !Task.isCancelled, session.url == target else { return }
            matchNotice = "Couldn’t match this listing to AniList. You can keep browsing and retry."
        }
    }
}

@MainActor
final class LiveChartSession: ObservableObject {
    @Published var url: URL
    @Published var loading = false
    @Published var canGoBack = false
    @Published var error: String?
    weak var webView: WKWebView?
    init(url: URL) { self.url = url }
    func goBack() { webView?.goBack() }
    func reload() { error = nil; if webView?.url == nil { webView?.load(URLRequest(url: url)) } else { webView?.reload() } }
}

struct LiveChartWebView: UIViewRepresentable {
    let startURL: URL
    @ObservedObject var session: LiveChartSession
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false; web.backgroundColor = .clear; web.scrollView.backgroundColor = .clear
        session.webView = web
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-livechart-preview") {
            web.loadHTMLString("<html><meta name='viewport' content='width=device-width'><body style='background:#111;color:white;font:20px system-ui;padding:20px'><h1>LiveChart UI preview</h1><p>Website content appears here. Tracking stays in AniList.</p></body></html>", baseURL: startURL)
            return web
        }
        #endif
        web.load(URLRequest(url: startURL))
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {}
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) { web.stopLoading(); web.navigationDelegate = nil }
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let session: LiveChartSession
        init(session: LiveChartSession) { self.session = session }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-livechart-preview"), url.scheme == "about" { decisionHandler(.allow); return }
            #endif
            if LiveChartURL.accepts(url) {
                if action.targetFrame?.isMainFrame == true || action.targetFrame == nil {
                    session.url = url; session.error = nil
                    if action.targetFrame == nil { webView.load(action.request); decisionHandler(.cancel); return }
                }
                decisionHandler(.allow)
            } else if action.targetFrame?.isMainFrame == false {
                // Permit the site's own embedded media and verification frames.
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                if ["https", "http"].contains(url.scheme?.lowercased() ?? "") { UIApplication.shared.open(url) }
            }
        }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { session.loading = true }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            session.loading = false; session.canGoBack = webView.canGoBack
            if let url = webView.url, LiveChartURL.accepts(url) { session.url = url }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
        private func failed(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            session.loading = false
            session.error = "LiveChart couldn’t load. Retry or use the browser button above."
        }
    }
}
