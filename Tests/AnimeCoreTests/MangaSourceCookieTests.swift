import XCTest
@testable import AnimeCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MangaSourceCookieTests: XCTestCase {
    func testBrowserCompletionPreservesLaterNativeUpdatesAdditionsAndDeletions() throws {
        let jar = MangaSourceCookieJar(), url = URL(string: "https://source.example/")!
        jar.receive(source: "one", url: url, headers: ["Set-Cookie": "session=old; Path=/; Secure"])
        jar.receive(source: "one", url: url, headers: ["Set-Cookie": "deleted=old; Path=/; Secure"])
        let initial = jar.cookies(source: "one")
        jar.receive(source: "one", url: url, headers: ["Set-Cookie": "session=new; Path=/; Secure"])
        jar.receive(source: "one", url: url, headers: ["Set-Cookie": "native=added; Path=/; Secure"])
        jar.receive(source: "one", url: url, headers: ["Set-Cookie": "deleted=; Path=/; Max-Age=0"])
        let browser = try XCTUnwrap(HTTPCookie(properties: [.name: "browser", .value: "added", .domain: "source.example", .path: "/", .secure: "TRUE"]))
        jar.replace(source: "two", cookies: [browser])
        jar.reconcileBrowser(source: "one", initial: initial, cookies: initial + [browser])
        XCTAssertEqual(Dictionary(jar.cookies(source: "one").map { ($0.name, $0.value) }, uniquingKeysWith: { _, value in value }),
            ["session": "new", "native": "added", "browser": "added"])
        XCTAssertEqual(jar.header(source: "two", url: url), "browser=added")
    }
    func testBrowserChangesAndDeletionsAreImportedWhenNativeCookiesHaveNotChanged() throws {
        let jar = MangaSourceCookieJar(), url = URL(string: "https://source.example/")!
        jar.receive(source: "one", url: url, headers: ["Set-Cookie": "session=old; Path=/; Secure"])
        jar.receive(source: "one", url: url, headers: ["Set-Cookie": "deleted=old; Path=/; Secure"])
        let initial = jar.cookies(source: "one")
        let changed = try XCTUnwrap(HTTPCookie(properties: [.name: "session", .value: "browser", .domain: "source.example", .path: "/", .secure: "TRUE"]))
        jar.reconcileBrowser(source: "one", initial: initial, cookies: [changed])
        XCTAssertEqual(jar.header(source: "one", url: url), "session=browser")
    }
    func testExplicitCookiePrecedenceAndMalformedNamesCannotCrashMerging() {
        XCTAssertEqual(MangaSourceCookieJar.merging(explicit: "session=source", session: "session=browser; verification=owned"), "session=source; verification=owned")
        XCTAssertEqual(MangaSourceCookieJar.merging(explicit: "=; ;;", session: "verification=owned"), "=; ;;; verification=owned")
        XCTAssertEqual(MangaSourceCookieJar.merging(explicit: nil, session: "session=owned"), "session=owned")
    }
    func testSessionsRespectSourceHostPathExpiryAndHTTPS() throws {
        let jar = MangaSourceCookieJar()
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.name: "session", .value: "owned", .domain: ".source.example", .path: "/reader", .secure: "TRUE"]))
        jar.replace(source: "one", cookies: [cookie])
        XCTAssertEqual(jar.header(source: "one", url: URL(string: "https://source.example/reader/1")!), "session=owned")
        XCTAssertEqual(jar.header(source: "one", url: URL(string: "https://cdn.source.example/reader")!), "session=owned")
        for text in ["http://source.example/reader", "https://othersource.example/reader", "https://source.example/reader-ad", "https://source.example/other"] {
            XCTAssertNil(jar.header(source: "one", url: URL(string: text)!))
        }
        XCTAssertNil(jar.header(source: "two", url: URL(string: "https://source.example/reader")!))
        jar.clear(source: "one")
        XCTAssertNil(jar.header(source: "one", url: URL(string: "https://source.example/reader")!))
    }
    func testHTTPResponsesCannotSetCookiesForUnrelatedHostsAndCanDeleteTheirOwn() {
        let jar = MangaSourceCookieJar(), url = URL(string: "https://source.example/reader")!
        jar.receive(source: "one", url: url, headers: ["Set-Cookie": "session=owned; Path=/; Secure; HttpOnly"])
        XCTAssertEqual(jar.header(source: "one", url: url), "session=owned")
        XCTAssertNil(jar.header(source: "one", url: URL(string: "https://cdn.source.example/reader")!))
        jar.receive(source: "one", url: url, headers: ["Set-Cookie": "stolen=bad; Domain=other.example; Path=/"])
        XCTAssertNil(jar.header(source: "one", url: URL(string: "https://other.example/")!))
        jar.receive(source: "one", url: url, headers: ["Set-Cookie": "session=; Path=/; Max-Age=0"])
        XCTAssertNil(jar.header(source: "one", url: url))
        jar.receive(source: "one", url: url, headers: ["Set-Cookie": "session=new; Path=/; Max-Age=3600; Expires=Thu, 01 Jan 1970 00:00:00 GMT"])
        XCTAssertEqual(jar.header(source: "one", url: url), "session=new")
    }
}
