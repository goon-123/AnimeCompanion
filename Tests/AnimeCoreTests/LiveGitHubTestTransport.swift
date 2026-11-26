import Foundation
import XCTest
import AnimeCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// CI-only authentication avoids anonymous GitHub API limits on shared runner
/// addresses. The application and APK/CDN downloads continue to be anonymous.
struct LiveGitHubTestTransport: HTTPTransport {
    let token: String?
    let base: any HTTPTransport
    init(token: String? = ProcessInfo.processInfo.environment["ANIMECOMPANION_GITHUB_READ_TOKEN"],
         base: any HTTPTransport = URLSessionTransport()) { self.token = token; self.base = base }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var checked = request
        if let url = request.url, url.scheme == "https", url.host == "api.github.com",
           url.port == nil || url.port == 443, url.user == nil, url.password == nil,
           url.path.hasPrefix("/repos/keiyoushi/extensions/releases/tags/"), let token, !token.isEmpty {
            checked.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await base.data(for: checked)
        if response.statusCode >= 400 {
            let remaining = response.value(forHTTPHeaderField: "x-ratelimit-remaining") ?? "unknown"
            throw ServiceError.message("Live provider HTTP \(response.statusCode) at \(request.url?.host ?? "unknown")\(request.url?.path ?? "") (GitHub rate-limit remaining: \(remaining)).")
        }
        return (data, response)
    }
}

final class LiveGitHubTestTransportTests: XCTestCase {
    private actor Capture: HTTPTransport {
        var authorization: String?
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            authorization = request.value(forHTTPHeaderField: "Authorization")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        func header() -> String? { authorization }
    }
    func testCITokenIsRestrictedToTheTrustedReleaseMetadataEndpoint() async throws {
        let capture = Capture()
        let transport = LiveGitHubTestTransport(token: "synthetic-ci-key", base: capture)
        _ = try await transport.data(for: URLRequest(url: URL(string: "https://api.github.com/repos/keiyoushi/extensions/releases/tags/owned")!))
        let allowed = await capture.header(); XCTAssertEqual(allowed, "Bearer synthetic-ci-key")
        for url in ["https://github.com/keiyoushi/extensions/releases/download/owned/source.apk",
                    "https://release-assets.githubusercontent.com/owned.apk", "http://api.github.com/repos/keiyoushi/extensions/releases/tags/owned",
                    "https://api.github.com.evil.test/repos/keiyoushi/extensions/releases/tags/owned",
                    "https://api.github.com/repos/other/extensions/releases/tags/owned"] {
            _ = try await transport.data(for: URLRequest(url: URL(string: url)!))
            let rejected = await capture.header(); XCTAssertNil(rejected, url)
        }
    }
    func testMissingTokenPreservesTheAnonymousClientPath() async throws {
        let capture = Capture()
        let transport = LiveGitHubTestTransport(token: nil, base: capture)
        _ = try await transport.data(for: URLRequest(url: URL(string: "https://api.github.com/repos/keiyoushi/extensions/releases/tags/owned")!))
        let header = await capture.header(); XCTAssertNil(header)
    }
}
