import Foundation
import AnimeCore
import AnimeMangaRuntime
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A fresh, bounded interpreter per call, always off the UI thread. The C
/// boundary exchanges owned JSON; VM object pointers never escape a call.
enum MangaRuntime {
    static func sessionKey(apkSHA256: String, sourceID: String) -> String { apkSHA256 + ":" + sourceID }
    private static let queue = DispatchQueue(label: "com.animecompanion.manga-runtime", qos: .userInitiated)
    static func inspect(_ apk: Data, modern: Bool) async throws -> MangaExtensionInspection {
        try await run(apk, command: ["op": "inspect", "modern": modern], networking: false)
    }
    static func browse(_ apk: Data, source: MangaRuntimeSource, modern: Bool, mode: String, query: String, page: Int, settings: MangaSourceSettings = .init()) async throws -> SourceMangaPage {
        try await run(apk, command: ["op": mode, "source": source.index, "modern": modern, "query": query, "page": page], networking: true, sourceID: source.id, settings: settings)
    }
    static func details(_ apk: Data, source: MangaRuntimeSource, modern: Bool, manga: SourceManga, settings: MangaSourceSettings = .init()) async throws -> SourceManga {
        try await run(apk, command: ["op": "details", "source": source.index, "modern": modern, "manga": ["url": manga.url, "title": manga.title]], networking: true, sourceID: source.id, settings: settings)
    }
    static func chapters(_ apk: Data, source: MangaRuntimeSource, modern: Bool, manga: SourceManga, settings: MangaSourceSettings = .init()) async throws -> [SourceMangaChapter] {
        try await run(apk, command: ["op": "chapters", "source": source.index, "modern": modern, "manga": ["url": manga.url, "title": manga.title]], networking: true, sourceID: source.id, settings: settings)
    }
    static func pages(_ apk: Data, source: MangaRuntimeSource, modern: Bool, chapter: SourceMangaChapter, settings: MangaSourceSettings = .init()) async throws -> [SourceMangaImage] {
        try await run(apk, command: ["op": "pages", "source": source.index, "modern": modern, "chapter": ["url": chapter.url, "name": chapter.name]], networking: true, sourceID: source.id, settings: settings)
    }
    static func book(_ apk: Data, source: MangaRuntimeSource, modern: Bool, manga: SourceManga, settings: MangaSourceSettings = .init()) async throws -> MangaBook {
        try await run(apk, command: ["op": "book", "source": source.index, "modern": modern,
                                    "manga": ["url": manga.url, "title": manga.title]], networking: true, sourceID: source.id, settings: settings)
    }
    static func image(_ apk: Data, source: MangaRuntimeSource, modern: Bool, image: SourceMangaImage, settings: MangaSourceSettings = .init()) async throws -> Data {
        let response: MangaImageEnvelope = try await run(apk, command: ["op": "image", "source": source.index, "modern": modern,
            "image": ["index": image.index, "url": image.url, "imageURL": image.imageURL]], networking: true, sourceID: source.id, settings: settings)
        guard let data = Data(base64Encoded: response.bodyBase64), !data.isEmpty, data.count <= 16_000_000 else { throw ArtworkError.invalidData }
        return data
    }
    static func sourceSettings(_ apk: Data, source: MangaRuntimeSource, modern: Bool, settings: MangaSourceSettings) async throws -> MangaSourceSettingsSchema {
        try await run(apk, command: ["op": "settings", "source": source.index, "modern": modern], networking: false, sourceID: source.id, settings: settings)
    }
    private static func run<T: Decodable>(_ apk: Data, command inputCommand: [String: Any], networking: Bool,
                                         sourceID: String? = nil, settings: MangaSourceSettings = .init()) async throws -> T {
        var command = inputCommand
        if let sourceID {
            let encoded = try settings.encoded()
            guard let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { throw MangaExtensionError.invalidSourceSettings }
            command["settingsSourceID"] = sourceID
            command["settings"] = object["values"]
        }
        let input = try JSONSerialization.data(withJSONObject: command)
        guard let json = String(data: input, encoding: .utf8) else { throw MangaExtensionError.runtimeFailure }
        let digest = SHA256.hash(data: apk).map { String(format: "%02x", $0) }.joined()
        let host = MangaRuntimeHTTP(networking: networking, sourceKey: sessionKey(apkSHA256: digest, sourceID: sourceID ?? "inspection"))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    defer { host.finish() }
                    do {
                        try host.checkCancellation()
                        let response: Data = try apk.withUnsafeBytes { bytes in
                            try json.withCString { command in
                                let pointer = ac_manga_execute(bytes.bindMemory(to: UInt8.self).baseAddress, apk.count, command,
                                    mangaHTTPCallback, mangaHTTPRelease, Unmanaged.passUnretained(host).toOpaque())
                                guard let pointer else { throw MangaExtensionError.runtimeFailure }
                                defer { ac_manga_free_string(pointer) }
                                return Data(bytes: pointer, count: strlen(pointer))
                            }
                        }
                        try host.checkCancellation()
                        let envelope = try JSONDecoder().decode(MangaRuntimeEnvelope<T>.self, from: response)
                        guard envelope.ok, let value = envelope.data else {
                            // Runtime diagnostics can contain private request URLs.
                            // Show only host-generated errors, never raw VM traces.
                            throw host.failure ?? MangaExtensionError.runtimeFailure
                        }
                        continuation.resume(returning: value)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { host.cancel() }
    }
}

private struct MangaImageEnvelope: Decodable { let bodyBase64: String }
private struct MangaRuntimeEnvelope<T: Decodable>: Decodable { let ok: Bool; let data: T? }
private let mangaHTTPCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? = { context, input in
    guard let context, let input else { return nil }
    return Unmanaged<MangaRuntimeHTTP>.fromOpaque(context).takeUnretainedValue().request(input)
}
private let mangaHTTPRelease: @convention(c) (UnsafeMutablePointer<CChar>?) -> Void = { free($0) }

private final class MangaRuntimeHTTP: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct Request: Decodable { let url: String; let method: String; let headers: [[String]]; let body: String? }
    private let networking: Bool
    private let sourceKey: String
    private let browser: MangaRuntimeBrowser
    private let deadline = Date().addingTimeInterval(60)
    private let lock = NSLock()
    private var stopped = false
    private var storedFailure: Error?
    private var requestCount = 0
    private var transferred = 0
    private var ownedSession: URLSession?
    private var requests: [Int: MangaNetworkRequest] = [:]
    init(networking: Bool, sourceKey: String) { self.networking = networking; self.sourceKey = sourceKey; self.browser = MangaRuntimeBrowser(sourceKey: sourceKey); super.init() }
    var failure: Error? { lock.lock(); defer { lock.unlock() }; return storedFailure }
    private var session: URLSession {
        lock.lock(); defer { lock.unlock() }
        if let ownedSession { return ownedSession }
        let config = URLSessionConfiguration.ephemeral
        config.urlCredentialStorage = nil; config.urlCache = nil
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 25
        config.httpMaximumConnectionsPerHost = 2
        let value = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        ownedSession = value; return value
    }
    func finish() { lock.lock(); let value = ownedSession; ownedSession = nil; lock.unlock(); value?.invalidateAndCancel(); browser.finish() }
    func cancel() { lock.lock(); stopped = true; let value = ownedSession; lock.unlock(); value?.invalidateAndCancel(); browser.finish() }
    func checkCancellation() throws {
        lock.lock(); let cancelled = stopped; lock.unlock()
        if cancelled { throw CancellationError() }
        if Date() >= deadline { throw URLError(.timedOut) }
    }
    private func record(_ error: Error) { lock.lock(); if storedFailure == nil { storedFailure = error }; lock.unlock() }
    private func validURL(_ text: String) -> URL? {
        guard let parts = URLComponents(string: text), parts.scheme?.lowercased() == "https",
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.port == nil || parts.port == 443, let host = parts.host,
              SeanimeNetworkPolicy.publicHost(host) != nil else { return nil }
        return parts.url
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, validURL(url.absoluteString) != nil else { completionHandler(nil); return }
        var redirected = request
        saveCookies(response)
        redirected.setValue(nil, forHTTPHeaderField: "Cookie")
        if request.url?.host?.lowercased() != response.url?.host?.lowercased() {
            // Never forward extension credentials across a redirect to another host.
            redirected.allHTTPHeaderFields = redirected.allHTTPHeaderFields?.filter { key, _ in
                !["authorization", "proxy-authorization", "cookie", "x-api-key"].contains(key.lowercased())
            }
        }
        applyCookies(to: &redirected)
        completionHandler(redirected)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        let request = requests[dataTask.taskIdentifier]
        request?.response = response as? HTTPURLResponse
        let oversized = response.expectedContentLength > 16_000_000
        if oversized { request?.error = MangaExtensionError.oversized }
        lock.unlock()
        if let response = response as? HTTPURLResponse { saveCookies(response) }
        completionHandler(oversized ? .cancel : .allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let request = requests[dataTask.taskIdentifier]
        transferred += data.count
        let oversized = (request?.data.count ?? 0) + data.count > 16_000_000 || transferred > 32_000_000
        if oversized { request?.error = MangaExtensionError.oversized }
        else { request?.data.append(data) }
        lock.unlock()
        if oversized { dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let request = requests.removeValue(forKey: task.taskIdentifier); lock.unlock()
        guard let request else { return }
        request.result.set(data: request.data, response: request.response, error: request.error ?? error)
        request.semaphore.signal()
    }
    func request(_ input: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>? {
        do {
            try checkCancellation()
            guard networking else { throw MangaExtensionError.runtimeFailure }
            let request = try JSONDecoder().decode(Request.self, from: Data(bytes: input, count: strlen(input)))
            if request.method == "AC_BROWSER", request.url == "ac-manga-browser://command", let body = request.body {
                let data = try browser.request(Data(body.utf8), remaining: deadline.timeIntervalSinceNow)
                let result = try JSONSerialization.data(withJSONObject: ["code": 200, "headers": [], "bodyBase64": data.base64EncodedString()])
                return String(decoding: result, as: UTF8.self).withCString { strdup($0) }
            }
            guard let url = validURL(request.url), ["GET", "POST", "HEAD", "PUT", "PATCH", "DELETE", "OPTIONS"].contains(request.method),
                  (request.body?.utf8.count ?? 0) <= 1_000_000 else { throw MangaExtensionError.sourceUnavailable }
            lock.lock(); requestCount += 1; let count = requestCount; lock.unlock()
            guard count <= 24 else { throw MangaExtensionError.oversized }
            var outbound = URLRequest(url: url); outbound.httpMethod = request.method
            outbound.httpBody = request.body.map { Data($0.utf8) }
            outbound.timeoutInterval = max(1, min(20, deadline.timeIntervalSinceNow))
            outbound.setValue(MangaSourceCookieJar.browserUserAgent, forHTTPHeaderField: "User-Agent")
            for pair in request.headers where pair.count == 2 {
                guard !["host", "content-length", "connection", "accept-encoding"].contains(pair[0].lowercased()) else { continue }
                outbound.setValue(pair[1], forHTTPHeaderField: pair[0])
            }
            applyCookies(to: &outbound)
            let pending = MangaNetworkRequest()
            let task = session.dataTask(with: outbound)
            lock.lock(); requests[task.taskIdentifier] = pending; lock.unlock()
            task.resume()
            guard pending.semaphore.wait(timeout: .now() + max(1, min(22, deadline.timeIntervalSinceNow))) == .success else {
                task.cancel(); throw URLError(.timedOut)
            }
            try checkCancellation()
            let (data, response) = try pending.result.get()
            let headers = response.allHeaderFields.compactMap { key, value -> [String]? in
                guard let key = key as? String else { return nil }; return [key, String(describing: value)]
            }.filter { !["content-encoding", "content-length"].contains($0[0].lowercased()) }
            if response.statusCode >= 400 { record(ServiceError.http(response.statusCode)) }
            let result = try JSONSerialization.data(withJSONObject: ["code": response.statusCode, "headers": headers, "bodyBase64": data.base64EncodedString()])
            return String(data: result, encoding: .utf8).flatMap { strdup($0) }
        } catch {
            record(error)
            return strdup("{\"code\":599,\"headers\":[],\"bodyBase64\":\"\"}")
        }
    }
    private func applyCookies(to request: inout URLRequest) {
        guard let url = request.url,
              let header = MangaSourceCookieJar.shared.header(source: sourceKey, url: url) else { return }
        // Explicit source cookies retain precedence. Session cookies otherwise
        // follow the same domain/path rules on initial requests and redirects.
        request.setValue(MangaSourceCookieJar.merging(explicit: request.value(forHTTPHeaderField: "Cookie"), session: header), forHTTPHeaderField: "Cookie")
        if header.split(separator: ";").contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("cf_clearance=") }) {
            request.setValue(MangaSourceCookieJar.browserUserAgent, forHTTPHeaderField: "User-Agent")
        }
    }
    private func saveCookies(_ response: HTTPURLResponse) {
        guard let url = response.url else { return }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String { result[key] = String(describing: pair.value) }
        }
        MangaSourceCookieJar.shared.receive(source: sourceKey, url: url, headers: headers)
    }
}

/// Mutable buffers are touched only under the owning delegate's lock.
private final class MangaNetworkRequest {
    var data = Data()
    var response: HTTPURLResponse?
    var error: Error?
    let result = MangaHTTPResult()
    let semaphore = DispatchSemaphore(value: 0)
}

private final class MangaHTTPResult: @unchecked Sendable {
    private let lock = NSLock()
    private var value: (Data?, URLResponse?, Error?) = (nil, nil, nil)
    func set(data: Data?, response: URLResponse?, error: Error?) { lock.lock(); value = (data, response, error); lock.unlock() }
    func get() throws -> (Data, HTTPURLResponse) {
        lock.lock(); let (data, response, error) = value; lock.unlock()
        if let error { throw error }
        guard let data, let response = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        return (data, response)
    }
}
