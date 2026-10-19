import XCTest
import WebKit
import AnimeCore
@testable import AnimeCompanion

final class MangaWebsiteSessionTests: XCTestCase {
    @MainActor
    func testSourceProfilesArePrivateAndCookiesDoNotCrossSources() async throws {
        let one = "owned-one-" + UUID().uuidString, two = "owned-two-" + UUID().uuidString
        let first = MangaWebsiteProfiles.store(one), second = MangaWebsiteProfiles.store(two)
        defer { MangaWebsiteProfiles.stores[one] = nil; MangaWebsiteProfiles.stores[two] = nil }
        XCTAssertFalse(first.isPersistent)
        XCTAssertFalse(second.isPersistent)
        XCTAssertFalse(first === second)
        XCTAssertFalse(first === WKWebsiteDataStore.default())
        XCTAssertTrue(first === MangaWebsiteProfiles.store(one))
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.name: "owned_session", .value: "one", .domain: "owned.example", .path: "/", .secure: "TRUE"]))
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            first.httpCookieStore.setCookie(cookie) { continuation.resume() }
        }
        let firstCookies = await withCheckedContinuation { continuation in
            first.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        let secondCookies = await withCheckedContinuation { continuation in
            second.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(firstCookies.first(where: { $0.name == "owned_session" })?.value, "one")
        XCTAssertFalse(secondCookies.contains(where: { $0.name == "owned_session" }))
    }
}
