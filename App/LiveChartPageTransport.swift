import Foundation
import WebKit
import AnimeCore

/// LiveChart serves browser pages rather than a public JSON gallery API. Let
/// system WebKit load the public document with its normal browser negotiation.
/// This profile is ephemeral and never shares account/source browser cookies.
struct LiveChartPageTransport: HTTPTransport {
    private let lifetime = AppDataSession()

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try lifetime.check()
        try Task.checkCancellation()
        let page = await LiveChartPageLoad(request: request, lifetime: lifetime)
        return try await withTaskCancellationHandler {
            try await page.value()
        } onCancel: {
            Task { @MainActor in page.cancel() }
        }
    }

    @MainActor static func cancelAllForReset() { LiveChartPageLoad.cancelAll() }
}

@MainActor
private final class LiveChartPageLoad: NSObject, WKNavigationDelegate {
    private static var active: [UUID: LiveChartPageLoad] = [:]
    private static var profile = WKWebsiteDataStore.nonPersistent()
    private static var rules: Task<WKContentRuleList?, Never>?
    private let id = UUID()
    private let request: URLRequest
    private let lifetime: AppDataSession
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var browser: WKWebView?
    private var response: HTTPURLResponse?
    private var timeout: Task<Void, Never>?
    private var cancelled = false

    init(request: URLRequest, lifetime: AppDataSession) {
        self.request = request; self.lifetime = lifetime
        super.init()
    }

    func value() async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        try lifetime.check()
        guard !cancelled else { throw CancellationError() }
        guard let url = request.url, accepts(url) else { throw AnimeVisualsError.invalidResponse }
        let rules = await Self.resourceRules()
        try Task.checkCancellation()
        try lifetime.check()
        guard !cancelled else { throw CancellationError() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            Self.active[id] = self
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = Self.profile
            if let rules { configuration.userContentController.add(rules) }
            // Responsive markup gets a viewport; only the native image pipeline
            // downloads the artwork, without duplicate web image/media decoding.
            let browser = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
            browser.navigationDelegate = self
            self.browser = browser
            // Never inject the HTTP client's app-only User-Agent or credentials.
            var publicPage = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                        timeoutInterval: min(25, max(1, request.timeoutInterval)))
            publicPage.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            browser.load(publicPage)
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(25)) } catch { return }
                self?.finish(.failure(URLError(.timedOut)))
            }
        }
    }

    static func cancelAll() {
        for page in Array(active.values) { page.cancel() }
        profile = .nonPersistent()
    }
    func cancel() { cancelled = true; finish(.failure(CancellationError())) }

    private static func resourceRules() async -> WKContentRuleList? {
        if let rules { return await rules.value }
        let task = Task<WKContentRuleList?, Never> {
            await withCheckedContinuation { continuation in
                let json = #"[{"trigger":{"url-filter":".*","resource-type":["image","media","font","style-sheet"]},"action":{"type":"block"}}]"#
                WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: "AnimeCompanion-public-gallery-resources-v1", encodedContentRuleList: json
                ) { rules, _ in continuation.resume(returning: rules) }
            }
        }
        rules = task
        return await task.value
    }

    private func accepts(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              ["www.livechart.me", "livechart.me"].contains(url.host?.lowercased() ?? ""),
              let expected = request.url else { return false }
        let path = url.path.split(separator: "/"), wanted = expected.path.split(separator: "/")
        guard path.count == 3, path[0] == "anime", Int(path[1]).map({ $0 > 0 }) == true,
              path[2] == "visuals", path == wanted else { return false }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ==
            URLComponents(url: expected, resolvingAgainstBaseURL: false)?.queryItems
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.targetFrame?.isMainFrame != false else { decisionHandler(.cancel); return }
        guard let url = navigationAction.request.url, accepts(url) else {
            decisionHandler(.cancel); finish(.failure(AnimeVisualsError.invalidResponse)); return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard navigationResponse.isForMainFrame,
              let response = navigationResponse.response as? HTTPURLResponse,
              let url = response.url, accepts(url) else {
            decisionHandler(.cancel); finish(.failure(AnimeVisualsError.invalidResponse)); return
        }
        self.response = response
        guard response.statusCode == 200 else {
            // Preserve denied/rate-limited responses for the client's cooldown.
            // Do not retry them through another transport or solve challenges.
            decisionHandler(.cancel); finish(.success((Data(), response))); return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let response else { finish(.failure(AnimeVisualsError.invalidResponse)); return }
        // Wait briefly for lazy controllers to attach cards before classifying
        // a gallery as empty. This does not scroll or poll the visible UI.
        let script = #"""
        if (!document.querySelector('[data-anime-visual-url-value]')) {
            await new Promise(resolve => {
                const observer = new MutationObserver(() => {
                    if (document.querySelector('[data-anime-visual-url-value]')) finish();
                });
                const finish = () => { observer.disconnect(); clearTimeout(timer); resolve(); };
                const timer = setTimeout(finish, 1200);
                observer.observe(document.documentElement, {childList: true, subtree: true, attributes: true});
            });
        }
        return document.documentElement.outerHTML;
        """#
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            let html: String?
            switch result {
            case .success(let value): html = value as? String
            case .failure(let error): self.finish(.failure(error)); return
            }
            guard let html, let data = html.data(using: .utf8), data.count <= 2_000_000 else {
                self.finish(.failure(AnimeVisualsError.invalidResponse)); return
            }
            self.finish(.success((data, response)))
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failure(URLError(.networkConnectionLost)))
    }

    private func finish(_ result: Result<(Data, HTTPURLResponse), Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel(); timeout = nil
        browser?.navigationDelegate = nil; browser?.stopLoading(); browser = nil
        Self.active[id] = nil
        do {
            try lifetime.check()
            continuation.resume(with: result)
        } catch { continuation.resume(throwing: error) }
    }
}
