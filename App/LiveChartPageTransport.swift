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
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            Self.active[id] = self
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let browser = WKWebView(frame: .zero, configuration: configuration)
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
    }
    func cancel() { cancelled = true; finish(.failure(CancellationError())) }

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
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, error in
            guard let self else { return }
            if let error { self.finish(.failure(error)); return }
            guard let html = result as? String, let data = html.data(using: .utf8), data.count <= 2_000_000 else {
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
