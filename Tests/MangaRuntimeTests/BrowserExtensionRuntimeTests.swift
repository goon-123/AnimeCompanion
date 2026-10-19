import XCTest
import WebKit
import AnimeCore
import AnimeMangaRuntime
@testable import AnimeCompanion

final class BrowserExtensionRuntimeTests: XCTestCase {
    @MainActor
    func testClearingTheProfileStopsItsBrowserAndDoesNotRestoreOldCookies() async throws {
        let key = "owned-cleared-" + UUID().uuidString
        let url = try XCTUnwrap(URL(string: "https://owned.example"))
        let command = MangaBrowserCommand(op: "load", id: 1, url: url.absoluteString, html: "<html></html>")
        let session = try MangaBrowserSession(sourceKey: key, command: command, url: url)
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.name: "old_session", .value: "one", .domain: "owned.example", .path: "/", .secure: "TRUE"]))
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.web.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { continuation.resume() }
        }
        MangaWebsiteProfiles.stores[key] = nil
        MangaSourceCookieJar.shared.clear(source: key)
        let event = await session.next()
        XCTAssertEqual(event["type"] as? String, "error")
        await session.close()
        XCTAssertTrue(MangaSourceCookieJar.shared.cookies(source: key).isEmpty)
    }
    @MainActor
    func testSourceCanInterceptFetchAndReceiveItsResponseWithoutAWebsiteRequest() async throws {
        let key = "owned-intercept-" + UUID().uuidString
        let url = try XCTUnwrap(URL(string: "https://owned.example"))
        let command = MangaBrowserCommand(op: "load", id: 1, url: url.absoluteString,
            html: "<html><script>fetch('/data').then(r => r.text()).then(text => android.post(text));</script></html>", bridges: ["android"])
        let session = try MangaBrowserSession(sourceKey: key, command: command, url: url)
        var intercepted = false, received = false
        for _ in 0..<100 {
            let event = await session.next()
            if event["type"] as? String == "request" {
                XCTAssertEqual(event["url"] as? String, "https://owned.example/data")
                let response = MangaBrowserResponse(mimeType: "text/plain", encoding: "utf-8", status: 200, headers: [], bodyBase64: Data("Owned response".utf8).base64EncodedString())
                try await session.decide(MangaBrowserCommand(op: "decision", id: 1, requestID: try XCTUnwrap(event["requestID"] as? Int), allow: false, response: response))
                intercepted = true
            }
            if event["type"] as? String == "message" {
                XCTAssertEqual(event["message"] as? String, "Owned response")
                received = true; break
            }
            XCTAssertNotEqual(event["type"] as? String, "error")
        }
        XCTAssertTrue(intercepted); XCTAssertTrue(received)
        await session.close()
        let ended = await session.next()
        XCTAssertEqual(ended["type"] as? String, "error")
        MangaWebsiteProfiles.stores[key] = nil
    }
    func testRealBrowserExtensionsReturnCatalogsThroughWebKitAndTheCBridge() async throws {
        let bundle = Bundle(for: Self.self)
        let apks = try XCTUnwrap(bundle.url(forResource: "Fixtures", withExtension: nil))
        let fixtures = try XCTUnwrap(bundle.url(forResource: "OwnedFixtures", withExtension: nil))
        let history = try String(contentsOf: fixtures.appendingPathComponent("cubari-history.json"), encoding: .utf8)
        let catalog = try String(contentsOf: fixtures.appendingPathComponent("comix-catalog.json"), encoding: .utf8)
        for name in ["tachiyomi-all.cubari-v1.6.0.apk", "tachiyomi-en.comix-v1.6.54.apk", "tachiyomi-all.mangaup-v1.6.3.apk"] {
            let key = "owned-browser-" + UUID().uuidString
            let apk = try Data(contentsOf: apks.appendingPathComponent(name))
            let browser = MangaRuntimeBrowser(sourceKey: key) { web, url in
                if name.contains("cubari") {
                    web.loadSimulatedRequest(URLRequest(url: url), responseHTML: "<html><script>window.globalHistoryHandler = {getAllPinnedSeries: async () => \(history), getAllUnpinnedSeries: async () => []};</script></html>")
                } else if name.contains("comix") {
                    web.loadSimulatedRequest(URLRequest(url: url), responseHTML: "<html><script id='initial-data' type='application/json'>{\"queries\":{\"owned\":\(catalog)}}</script></html>")
                } else {
                    XCTFail("Unexpected page navigation for Manga UP!'s local storage read")
                }
            }
            let host = OwnedBrowserExtensionHost(apk: apk, browser: browser)
            let page = try await host.popular()
            browser.finish()
            await MainActor.run { MangaWebsiteProfiles.stores[key] = nil }
            XCTAssertEqual(page.mangas.count, 1, name)
            XCTAssertEqual(page.mangas.first?.title, "Owned story", name)
            XCTAssertFalse(page.mangas.first?.thumbnailURL.isEmpty ?? true, name)
            XCTAssertGreaterThan(host.browserCalls, 0, name)
            XCTAssertEqual(host.apiCalls, name.contains("mangaup") ? 1 : 0, name)
        }
    }

    @MainActor
    func testLocalStorageBelongsOnlyToTheSelectedSourceAndIsReadWithoutNavigatingTheSite() async throws {
        let firstKey = "owned-storage-" + UUID().uuidString, secondKey = "owned-storage-" + UUID().uuidString
        let url = try XCTUnwrap(URL(string: "https://owned.example"))
        let command = MangaBrowserCommand(op: "load", id: 1, url: url.absoluteString, html: "<html></html>", bridges: ["android"])
        let first = try MangaBrowserSession(sourceKey: firstKey, command: command, url: url)
        _ = await first.next()
        try await waitForFinish(first)
        let written = try await first.evaluate("localStorage.setItem('owned', 'one'); localStorage.getItem('owned')")
        XCTAssertEqual(written["value"] as? String, "\"one\"")
        await first.close()
        let reloaded = try MangaBrowserSession(sourceKey: firstKey, command: command, url: url)
        _ = await reloaded.next(); try await waitForFinish(reloaded)
        let retained = try await reloaded.evaluate("localStorage.getItem('owned')")
        XCTAssertEqual(retained["value"] as? String, "\"one\"")
        let isolated = try MangaBrowserSession(sourceKey: secondKey, command: command, url: url)
        _ = await isolated.next(); try await waitForFinish(isolated)
        let absent = try await isolated.evaluate("localStorage.getItem('owned')")
        XCTAssertEqual(absent["value"] as? String, "null")
        await reloaded.close(); await isolated.close()
        MangaWebsiteProfiles.stores[firstKey] = nil; MangaWebsiteProfiles.stores[secondKey] = nil
    }
    @MainActor private func waitForFinish(_ session: MangaBrowserSession) async throws {
        for _ in 0..<100 {
            let event = await session.next()
            if event["type"] as? String == "finished" { return }
            if event["type"] as? String == "error" { XCTFail("Owned browser load failed"); return }
        }
        XCTFail("Owned browser load timed out")
    }
}

/// Actual APK + actual WebKit; only the test page/API content is owned data.
private final class OwnedBrowserExtensionHost: @unchecked Sendable {
    let apk: Data
    let browser: MangaRuntimeBrowser
    var browserCalls = 0
    var apiCalls = 0
    init(apk: Data, browser: MangaRuntimeBrowser) { self.apk = apk; self.browser = browser }
    func popular() async throws -> SourceMangaPage {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                defer { self.browser.finish() }
                do {
                    let data = try self.apk.withUnsafeBytes { bytes in
                        try "{\"op\":\"popular\",\"modern\":true}".withCString { input -> Data in
                            let pointer = try XCTUnwrap(ac_manga_execute(bytes.bindMemory(to: UInt8.self).baseAddress, self.apk.count,
                                input, ownedBrowserCallback, ownedBrowserRelease, Unmanaged.passUnretained(self).toOpaque()))
                            defer { ac_manga_free_string(pointer) }
                            return Data(bytes: pointer, count: strlen(pointer))
                        }
                    }
                    let result = try JSONDecoder().decode(Envelope.self, from: data)
                    guard result.ok, let page = result.data else { throw NSError(domain: "OwnedBrowser", code: 1, userInfo: [NSLocalizedDescriptionKey: result.error ?? "Missing catalog"]) }
                    continuation.resume(returning: page)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func request(_ input: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>? {
        do {
            let request = try JSONDecoder().decode(Request.self, from: Data(bytes: input, count: strlen(input)))
            let body: Data
            if request.method == "AC_BROWSER", let payload = request.body {
                browserCalls += 1
                body = try browser.request(Data(payload.utf8), remaining: 20)
            } else {
                guard request.url.hasPrefix("https://global-api.manga-up.com/api/search?") else { throw URLError(.badURL) }
                apiCalls += 1
                let title = Data([8,1]) + proto(2, Data("Owned story".utf8)) + proto(3, Data("/owned-cover.jpg".utf8)) + Data([56,1]) + proto(9, Data("Oct 19, 2026".utf8))
                body = proto(2, title)
            }
            let response: [String: Any] = ["code": 200, "headers": [], "bodyBase64": body.base64EncodedString()]
            let encoded = try JSONSerialization.data(withJSONObject: response)
            return String(decoding: encoded, as: UTF8.self).withCString { strdup($0) }
        } catch { return strdup("{\"code\":599,\"headers\":[],\"bodyBase64\":\"\"}") }
    }
    private func proto(_ field: UInt8, _ body: Data) -> Data {
        precondition(body.count < 128)
        return Data([field << 3 | 2, UInt8(body.count)]) + body
    }
    private struct Request: Decodable { let url: String; let method: String; let body: String? }
    private struct Envelope: Decodable { let ok: Bool; let data: SourceMangaPage?; let error: String? }
}
private let ownedBrowserCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? = { context, input in
    guard let context, let input else { return nil }
    return Unmanaged<OwnedBrowserExtensionHost>.fromOpaque(context).takeUnretainedValue().request(input)
}
private let ownedBrowserRelease: @convention(c) (UnsafeMutablePointer<CChar>?) -> Void = { free($0) }
