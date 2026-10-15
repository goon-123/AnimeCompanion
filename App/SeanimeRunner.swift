import Foundation
import WebKit
import AnimeCore

/// Every call gets a new worker and non-persistent WebKit content process. The
/// trusted host document can terminate CPU-bound extension JavaScript without
/// blocking the app's UI. The native bridge exposes only bounded, approved GETs.
@MainActor
final class SeanimeRunner: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    @Published private(set) var warning: String?
    private var web: WKWebView?
    private var continuation: CheckedContinuation<Data, Error>?
    private var timeout: Task<Void, Never>?
    private var requests: [Task<Void, Never>] = []
    private var input: [String: Any] = [:]
    private var hosts: [String] = []
    private var requestCount = 0
    private var receivedBytes = 0
    private var networkError: Error?
    private var generation = UUID()
    let client: SeanimeClient
    init(client: SeanimeClient = SeanimeClient()) { self.client = client; super.init() }

    func search(_ installation: SeanimeInstallation, query: String, anime: Anime?, allowAdult: Bool) async throws -> [SeanimeTorrent] {
        var media: [String: Any] = ["id": anime?.id ?? 0, "synonyms": [], "isAdult": anime?.isAdult ?? false,
            "romajiTitle": anime?.title?.romaji ?? query, "englishTitle": anime?.title?.english ?? query,
            "format": anime?.format ?? "TV", "status": anime?.status ?? "FINISHED", "episodeCount": anime?.episodes ?? -1]
        if let id = anime?.idMal { media["idMal"] = id }
        let data = try await run(installation, input: ["method": "search", "allowAdult": allowAdult,
            "options": ["query": query, "media": media]])
        struct Result: Decodable { let torrents: [SeanimeTorrent]; let warnings: Int? }
        guard let result = try? JSONDecoder().decode(Result.self, from: data) else { throw SeanimeError.invalidResults }
        warning = (result.warnings ?? 0) > 0 ? "The provider reported errors. These results may be incomplete." : nil
        var seen = Set<String>()
        return result.torrents.filter { !$0.name.isEmpty && seen.insert($0.id).inserted }
    }
    func magnet(_ installation: SeanimeInstallation, torrent: SeanimeTorrent, allowAdult: Bool) async throws -> String {
        if let magnet = torrent.magnet { return magnet }
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(torrent))
        let data = try await run(installation, input: ["method": "magnet", "allowAdult": allowAdult, "torrent": object])
        struct Result: Decodable { let magnet: String }
        guard let result = try? JSONDecoder().decode(Result.self, from: data) else { throw SeanimeError.invalidResults }
        return result.magnet
    }
    private func run(_ installation: SeanimeInstallation, input: [String: Any]) async throws -> Data {
        guard continuation == nil, installation.enabled, !installation.adult || input["allowAdult"] as? Bool == true else { throw SeanimeError.runtime }
        try Task.checkCancellation()
        self.input = input.merging(["source": installation.source, "preferences": installation.preferences]) { _, last in last }
        hosts = installation.allowedHosts; requestCount = 0; receivedBytes = 0; networkError = nil; generation = UUID(); warning = nil
        let expected = generation
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
                config.processPool = WKProcessPool()
                config.userContentController.add(self, name: "engine")
                let web = WKWebView(frame: .zero, configuration: config)
                self.web = web; web.navigationDelegate = self
                // A synthetic HTTPS document origin avoids opaque blob-worker
                // origins. No server is contacted; the HTML is supplied here.
                web.loadHTMLString(Self.hostHTML, baseURL: URL(string: "https://seanime-runtime.invalid/")!)
                timeout = Task { [weak self] in
                    #if DEBUG
                    let duration: Duration = ProcessInfo.processInfo.arguments.contains("--ui-seanime-timeout") ? .seconds(1) : .seconds(60)
                    #else
                    let duration: Duration = .seconds(60)
                    #endif
                    do { try await Task.sleep(for: duration); try Task.checkCancellation(); self?.finish(.failure(SeanimeError.timeout)) }
                    catch {}
                }
            }
        } onCancel: { Task { @MainActor [weak self] in if self?.generation == expected { self?.finish(.failure(CancellationError())) } } }
    }
    func cancel() { finish(.failure(CancellationError())) }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let currentWeb = web, controller === currentWeb.configuration.userContentController,
              message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let kind = body["kind"] as? String, continuation != nil else { return }
        let started = generation
        switch kind {
        case "ready":
            Task {
                do {
                    guard let resource = Bundle.main.url(forResource: "worker", withExtension: "js", subdirectory: "SeanimeRuntimeResources") else { throw SeanimeError.invalidSource }
                    let source = try String(contentsOf: resource, encoding: .utf8)
                    guard started == generation, let web else { return }
                    _ = try await web.callAsyncJavaScript("window.begin(workerSource, input)", arguments: ["workerSource": source, "input": input], in: nil, in: .page)
                } catch { if started == generation { finish(.failure(SeanimeError.runtime)) } }
            }
        case "fetch":
            guard requestCount < 24, let id = body["id"] as? Int, let url = body["url"] as? String, url.utf8.count <= 16_384 else { finish(.failure(SeanimeError.runtime)); return }
            requestCount += 1
            requests.append(Task {
                do {
                    let result = try await client.fetch(url, hosts: hosts)
                    try Task.checkCancellation()
                    guard started == generation, continuation != nil else { return }
                    receivedBytes += result.0.utf8.count
                    guard receivedBytes <= 12_000_000 else { throw SeanimeError.runtime }
                    await reply(["kind": "response", "id": id, "text": result.0, "status": result.1], started: started)
                } catch {
                    guard started == generation, continuation != nil else { return }
                    networkError = error
                    await reply(["kind": "response", "id": id, "error": true], started: started)
                }
            })
        case "result":
            guard let result = body["result"] as? [String: Any] else { finish(.failure(SeanimeError.runtime)); return }
            if let networkError { finish(.failure(networkError)); return }
            if result["error"] as? String == "adult" { finish(.failure(SeanimeError.adultProvider)); return }
            if result["error"] != nil { finish(.failure(SeanimeError.runtime)); return }
            guard let data = try? JSONSerialization.data(withJSONObject: result), data.count <= 4_000_000 else { finish(.failure(SeanimeError.invalidResults)); return }
            finish(.success(data))
        default: break
        }
    }
    private func reply(_ message: [String: Any], started: UUID) async {
        guard started == generation, let web else { return }
        do { _ = try await web.callAsyncJavaScript("window.reply(message)", arguments: ["message": message], in: nil, in: .page) }
        catch { if started == generation { finish(.failure(SeanimeError.runtime)) } }
    }
    private func finish(_ result: Result<Data, Error>) {
        guard let continuation else { return }
        self.continuation = nil; generation = UUID(); timeout?.cancel(); timeout = nil
        requests.forEach { $0.cancel() }; requests = []
        let old = web; web = nil
        old?.evaluateJavaScript("window.halt()")
        old?.stopLoading(); old?.configuration.userContentController.removeScriptMessageHandler(forName: "engine")
        old?.navigationDelegate = nil
        continuation.resume(with: result)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if webView === web { finish(.failure(SeanimeError.runtime)) } }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if webView === web { finish(.failure(SeanimeError.runtime)) } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if webView === web { finish(.failure(SeanimeError.runtime)) } }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = action.request.url
        let bootstrap = url?.scheme == "https" && url?.host == "seanime-runtime.invalid" && url?.path == "/" && action.navigationType == .other
        decisionHandler(url?.scheme == "about" || bootstrap ? .allow : .cancel)
    }
    private static let hostHTML = """
    <!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' blob:; worker-src blob:; connect-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'">
    <script>
    let worker;
    window.halt = () => { if (worker) { worker.terminate(); worker = null; } };
    window.begin = (source, input) => {
      window.halt();
      const url = URL.createObjectURL(new Blob([source], {type: 'text/javascript'}));
      worker = new Worker(url); URL.revokeObjectURL(url);
      worker.onmessage = e => window.webkit.messageHandlers.engine.postMessage(e.data);
      worker.onerror = () => window.webkit.messageHandlers.engine.postMessage({kind:'result',result:{error:'runtime'}});
      worker.postMessage({kind:'run',input});
    };
    window.reply = message => { if (worker) worker.postMessage(message); };
    window.webkit.messageHandlers.engine.postMessage({kind:'ready'});
    </script>
    """
}
