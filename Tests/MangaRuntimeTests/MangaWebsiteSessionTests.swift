import XCTest
import WebKit
import AnimeCore
@testable import AnimeCompanion

final class MangaWebsiteSessionTests: XCTestCase {
    @MainActor
    func testChangingAWebsiteSessionInvalidatesOnlyThatSourcesImageIdentity() {
        let store = MangaExtensionStore()
        let one = MangaSourceReference(extensionID: "owned-one", sourceID: "1", name: "One", language: "en", homeURL: "https://owned.example", adult: false)
        let two = MangaSourceReference(extensionID: "owned-two", sourceID: "2", name: "Two", language: "en", homeURL: "https://owned.example", adult: false)
        let first = store.imageVersion(one), second = store.imageVersion(two)
        store.sourceSessionChanged(one)
        XCTAssertNotEqual(store.imageVersion(one), first)
        XCTAssertEqual(store.imageVersion(two), second)
    }
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
