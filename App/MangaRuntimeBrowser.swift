import Foundation
import WebKit
import AnimeCore

enum MangaBrowserPolicy {
    static func allowed(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443, let host = parts.host else { return false }
        return SeanimeNetworkPolicy.publicHost(host) != nil
    }
}

/// Synchronous worker-side transport. WebKit and its delegates stay on MainActor;
/// only owned JSON crosses this boundary. Cancelling the VM also closes its views.
final class MangaRuntimeBrowser: @unchecked Sendable {
    private let owner = UUID()
    private let sourceKey: String
    private let documentLoader: (@MainActor (WKWebView, URL) -> Void)?
    private let lock = NSLock()
    private var stopped = false
    private var calls = 0
    @MainActor private static var sessions: [UUID: [Int: MangaBrowserSession]] = [:]
    init(sourceKey: String, documentLoader: (@MainActor (WKWebView, URL) -> Void)? = nil) { self.sourceKey = sourceKey; self.documentLoader = documentLoader }
    func finish() {
        lock.lock(); stopped = true; lock.unlock()
        let owner = owner
        Task { @MainActor in
            let sessions = Self.sessions.removeValue(forKey: owner) ?? [:]
            for session in sessions.values { await session.close() }
        }
    }
    private var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func request(_ input: Data, remaining: TimeInterval) throws -> Data {
        guard !Thread.isMainThread, !cancelled, input.count <= 1_000_000 else { throw MangaExtensionError.sourceUnavailable }
        let command = try JSONDecoder().decode(MangaBrowserCommand.self, from: input)
        guard (1...8).contains(command.id) else { throw MangaExtensionError.sourceUnavailable }
        lock.lock(); calls += 1; let count = calls; lock.unlock()
        guard count <= 4096 else { throw MangaExtensionError.oversized }
        let result = MangaBrowserResult()
        Task { @MainActor [self] in
            do {
                guard !cancelled else { throw CancellationError() }
                if command.op == "load" {
                    guard let text = command.url, let url = URL(string: text), MangaBrowserPolicy.allowed(url),
                          Self.sessions[owner]?[command.id] == nil else { throw MangaExtensionError.sourceUnavailable }
                    let session = try MangaBrowserSession(sourceKey: sourceKey, command: command, url: url)
                    session.documentLoader = documentLoader
                    Self.sessions[owner, default: [:]][command.id] = session
                    result.set(.success([:]))
                } else if command.op == "close" {
                    let session = Self.sessions[owner]?.removeValue(forKey: command.id)
                    await session?.close()
                    result.set(.success([:]))
                } else {
                    guard let session = Self.sessions[owner]?[command.id] else { throw MangaExtensionError.sourceUnavailable }
                    switch command.op {
                    case "next": result.set(.success(await session.next()))
                    case "evaluate": result.set(.success(try await session.evaluate(command.script ?? "")))
                    case "decision": try await session.decide(command); result.set(.success([:]))
                    case "stop": session.web.stopLoading(); result.set(.success([:]))
                    default: throw MangaExtensionError.sourceUnavailable
                    }
                }
            } catch { result.set(.failure(error)) }
        }
        guard result.semaphore.wait(timeout: .now() + max(0.1, min(5, remaining))) == .success else {
            finish(); throw URLError(.timedOut)
        }
        guard !cancelled else { throw CancellationError() }
        return try JSONSerialization.data(withJSONObject: result.get())
    }
}

struct MangaBrowserCommand: Decodable {
    let op: String
    let id: Int
    var url: String?
    var html: String?
    var headers: [[String]]?
    var userAgent: String?
    var bridges: [String]?
    var script: String?
    var requestID: Int?
    var allow: Bool?
    var response: MangaBrowserResponse?
    var javaScriptEnabled: Bool?
    var domStorageEnabled: Bool?
    var blockImages: Bool?
}

struct MangaBrowserResponse: Codable {
    let mimeType: String
    let encoding: String
    let status: Int
    let headers: [[String]]
    let bodyBase64: String
}

private final class MangaBrowserResult: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var value: Result<[String: Any], Error>?
    func set(_ value: Result<[String: Any], Error>) {
        lock.lock()
        guard self.value == nil else { lock.unlock(); return }
        self.value = value; lock.unlock(); semaphore.signal()
    }
    func get() throws -> [String: Any] { lock.lock(); defer { lock.unlock() }; return try value!.get() }
}

@MainActor
final class MangaBrowserSession: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let web: WKWebView
    private let sourceKey: String
    private let command: MangaBrowserCommand
    private let home: URL
    private let handlerName = "ac" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private var events: [[String: Any]] = []
    private var prepared = true
    private var navigationReady = false
    private var navigationResponse: MangaBrowserResponse?
    private var closed = false
    private var overflow = false
    private var eventBytes = 0
    // Native tests may load an owned document while retaining the real source origin.
    var documentLoader: (@MainActor (WKWebView, URL) -> Void)?
    private var currentProfile: Bool { MangaWebsiteProfiles.stores[sourceKey] === web.configuration.websiteDataStore }

    init(sourceKey: String, command: MangaBrowserCommand, url: URL) throws {
        guard (command.bridges?.count ?? 0) <= 64,
              (command.html?.utf8.count ?? 0) <= 1_000_000,
              (command.bridges ?? []).allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }) else { throw MangaExtensionError.oversized }
        self.sourceKey = sourceKey; self.command = command; self.home = url
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = MangaWebsiteProfiles.store(sourceKey)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = command.javaScriptEnabled ?? true
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        super.init()
        web.navigationDelegate = self
        web.customUserAgent = command.userAgent?.isEmpty == false ? command.userAgent : MangaSourceCookieJar.browserUserAgent
        configuration.userContentController.add(self, name: handlerName)
        let namesData = try JSONSerialization.data(withJSONObject: command.bridges ?? [])
        let names = String(decoding: namesData, as: UTF8.self)
        let script = """
        (() => {
          const pending = new Map(); let nextID = 10;
          window.\(handlerName)Reply = (id, decision) => {
            const resolve = pending.get(id); pending.delete(id); if (resolve) resolve(decision);
          };
          const fetch = window.fetch;
          window.fetch = async function(input, options) {
            const request = new Request(input instanceof Request ? input.clone() : input, options);
            const requestID = nextID++;
            const decision = await new Promise(resolve => {
              pending.set(requestID, resolve);
              window.webkit.messageHandlers.\(handlerName).postMessage({type: 'request', requestID,
                url: request.url, method: request.method, headers: Array.from(request.headers)});
            });
            if (decision.allow) return fetch.call(this, input, options);
            const response = decision.response || {status: 403, headers: [], bodyBase64: ''};
            const bytes = Uint8Array.from(atob(response.bodyBase64), ch => ch.charCodeAt(0));
            const headers = new Headers(response.headers);
            if (response.mimeType) headers.set('Content-Type', response.mimeType + '; charset=' + (response.encoding || 'utf-8'));
            return new Response(bytes, {status: response.status, headers});
          };
          const names = \(names);
          for (const name of names) {
            const send = (method, value) => {
              window.webkit.messageHandlers.\(handlerName).postMessage({name, method, message: String(value)});
            };
            Object.defineProperty(window, name, {configurable: true, value: {
              post: value => send('post', value), postMessage: value => send('postMessage', value)
            }});
          }
        })();
        """
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        if command.domStorageEnabled == false {
            let disableStorage = "for(const key of ['localStorage','sessionStorage']) Object.defineProperty(window,key,{get(){throw new DOMException('Storage is disabled','SecurityError')}});"
            configuration.userContentController.addUserScript(WKUserScript(source: disableStorage, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        navigationReady = command.html != nil
        if command.html == nil {
            var headers = command.headers ?? []
            if !headers.contains(where: { $0.first?.lowercased() == "accept" }) { headers.append(["Accept", "text/html"]) }
            enqueue(["type": "request", "requestID": 1, "url": url.absoluteString, "method": "GET", "headers": headers, "mainFrame": true])
        }
        enqueue(["type": "started", "url": url.absoluteString])
    }
    private func enqueue(_ event: [String: Any]) {
        guard !closed, currentProfile else { return }
        let bytes = (try? JSONSerialization.data(withJSONObject: event).count) ?? 4_000_001
        guard events.count < 256, eventBytes + bytes <= 4_000_000 else { overflow = true; web.stopLoading(); return }
        eventBytes += bytes
        events.append(event)
    }
    private func takeEvent() -> [String: Any] {
        guard !events.isEmpty else { return ["type": "idle"] }
        let event = events.removeFirst()
        eventBytes -= (try? JSONSerialization.data(withJSONObject: event).count) ?? 0
        return event
    }
    func next() async -> [String: Any] {
        guard !closed, currentProfile else { return ["type": "error"] }
        if overflow { return ["type": "error"] }
        if !events.isEmpty { return takeEvent() }
        if prepared && navigationReady {
            prepared = false
            do {
                let filters = ["^http:", "^https://[0-9.]+(:[0-9]+)?/", "^https://\\[", "^https://[a-zA-Z0-9-]+(:[0-9]+)?/", "^https://[^/]*\\.(local|localhost|internal|test|invalid)(:[0-9]+)?/", "^https://[^/]*@", "^https://[^/]*:[0-9]+/"]
                var rules: [[String: Any]] = filters.map { ["trigger": ["url-filter": $0], "action": ["type": "block"]] }
                if command.blockImages == true { rules.append(["trigger": ["url-filter": ".*", "resource-type": ["image"]], "action": ["type": "block"]]) }
                let encoded = try JSONSerialization.data(withJSONObject: rules)
                let ruleID = command.blockImages == true ? "ac-manga-public-no-images-v1" : "ac-manga-public-v1"
                let list: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
                    WKContentRuleListStore.default().compileContentRuleList(forIdentifier: ruleID, encodedContentRuleList: String(decoding: encoded, as: UTF8.self)) { list, error in
                        if let list { continuation.resume(returning: list) }
                        else { continuation.resume(throwing: error ?? MangaExtensionError.sourceUnavailable) }
                    }
                }
                web.configuration.userContentController.add(list)
            } catch { return ["type": "error"] }
            for cookie in MangaSourceCookieJar.shared.cookies(source: sourceKey) {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    web.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { continuation.resume() }
                }
            }
            guard !closed, currentProfile else { return ["type": "error"] }
            if let response = navigationResponse, let data = Data(base64Encoded: response.bodyBase64) {
                var headers = Dictionary(response.headers.filter { $0.count == 2 }.map { ($0[0], $0[1]) }, uniquingKeysWith: { _, value in value })
                headers["Content-Type"] = response.mimeType + "; charset=" + response.encoding
                guard let supplied = HTTPURLResponse(url: home, statusCode: response.status, httpVersion: "HTTP/1.1", headerFields: headers) else { return ["type": "error"] }
                web.loadSimulatedRequest(URLRequest(url: home), response: supplied, responseData: data)
            } else if let html = command.html { web.loadSimulatedRequest(URLRequest(url: home), responseHTML: html) }
            else if let documentLoader { documentLoader(web, home) }
            else {
                var request = URLRequest(url: home)
                for pair in command.headers ?? [] where pair.count == 2 {
                    guard !["host", "content-length", "connection", "cookie"].contains(pair[0].lowercased()) else { continue }
                    request.setValue(pair[1], forHTTPHeaderField: pair[0])
                }
                web.load(request)
            }
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        return takeEvent()
    }
    func decide(_ decision: MangaBrowserCommand) async throws {
        guard !closed, currentProfile, let requestID = decision.requestID, let allow = decision.allow else { throw MangaExtensionError.sourceUnavailable }
        if let response = decision.response {
            guard (200...599).contains(response.status), let data = Data(base64Encoded: response.bodyBase64), data.count <= 1_000_000 else { throw MangaExtensionError.oversized }
        }
        if requestID == 1 {
            guard prepared, !navigationReady else { throw MangaExtensionError.sourceUnavailable }
            navigationReady = true
            if !allow {
                guard let response = decision.response else { throw MangaExtensionError.sourceUnavailable }
                navigationResponse = response
            }
        } else {
            let response = try decision.response.map { value -> Any in
                try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
            } ?? NSNull()
            let data = try JSONSerialization.data(withJSONObject: ["allow": allow, "response": response])
            let json = String(decoding: data, as: UTF8.self)
            _ = try await evaluate("window.\(handlerName)Reply(\(requestID), \(json))")
        }
    }
    func evaluate(_ script: String) async throws -> [String: Any] {
        guard !closed, currentProfile, script.utf8.count <= 1_000_000 else { throw MangaExtensionError.oversized }
        // Page-start hooks in Android's fallback inject before page code. Stage
        // those scripts before the first load so WebKit preserves that ordering.
        if prepared {
            web.configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            return ["value": "null"]
        }
        let value: Any? = try? await web.evaluateJavaScript(script)
        guard !closed, currentProfile else { throw CancellationError() }
        let encoded = try JSONSerialization.data(withJSONObject: value ?? NSNull(), options: [.fragmentsAllowed])
        guard encoded.count <= 1_000_000 else { throw MangaExtensionError.oversized }
        return ["value": String(decoding: encoded, as: UTF8.self)]
    }
    func close() async {
        guard !closed else { return }; closed = true
        web.stopLoading(); web.navigationDelegate = nil
        web.configuration.userContentController.removeScriptMessageHandler(forName: handlerName)
        web.configuration.userContentController.removeAllUserScripts()
        web.configuration.userContentController.removeAllContentRuleLists()
        events.removeAll(); eventBytes = 0
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            web.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        if currentProfile { MangaSourceCookieJar.shared.replace(source: sourceKey, cookies: cookies) }
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == handlerName, let payload = message.body as? [String: Any],
              let frameURL = message.frameInfo.request.url, MangaBrowserPolicy.allowed(frameURL) else { return }
        if payload["type"] as? String == "request", let id = payload["requestID"] as? Int,
           let text = payload["url"] as? String, let url = URL(string: text),
           let method = payload["method"] as? String, method.utf8.count <= 32,
           let headers = payload["headers"] as? [[String]], headers.count <= 128 {
            guard MangaBrowserPolicy.allowed(url), (10..<1_000_000).contains(id),
                  headers.allSatisfy({ $0.count == 2 && $0[0].utf8.count <= 256 && $0[1].utf8.count <= 16_384 }) else {
                let reply = MangaBrowserCommand(op: "decision", id: command.id, requestID: id, allow: false)
                Task { try? await decide(reply) }; return
            }
            enqueue(["type": "request", "requestID": id, "url": text, "method": method, "headers": headers, "mainFrame": false])
            return
        }
        guard let name = payload["name"] as? String, (command.bridges ?? []).contains(name),
              let value = payload["message"] as? String, value.utf8.count <= 1_000_000,
              let method = payload["method"] as? String, ["post", "postMessage"].contains(method) else { return }
        enqueue(["type": "message", "name": name, "method": method, "message": value])
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        enqueue(["type": "finished", "url": webView.url?.absoluteString ?? home.absoluteString])
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { enqueue(["type": "error"]) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { enqueue(["type": "error"]) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { enqueue(["type": "error"]) }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, MangaBrowserPolicy.allowed(url) else { decisionHandler(.cancel); return }
        if action.targetFrame == nil { webView.load(action.request); decisionHandler(.cancel) }
        else { decisionHandler(.allow) }
    }
}
