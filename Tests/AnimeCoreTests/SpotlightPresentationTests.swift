import XCTest
@testable import AnimeCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class SpotlightPresentationTests: XCTestCase {
    func testCachedLogoIsTheFirstPresentationWithoutATextFrame() {
        var state = SpotlightTitlePresentation()
        XCTAssertEqual(state.title(for: 1), .checkingCache)
        state.checkedCache(for: 1, hasLogo: true)
        XCTAssertEqual(state.title(for: 1), .logo)
    }
    func testVisibleFallbackCannotChangeUntilItLeavesTheViewport() {
        var state = SpotlightTitlePresentation()
        state.checkedCache(for: 1, hasLogo: false)
        state.preparedLogo(for: 1, protected: [1])
        XCTAssertEqual(state.title(for: 1), .text)
        state.revealOffscreen(protected: [1, 2])
        XCTAssertEqual(state.title(for: 1), .text)
        state.revealOffscreen(protected: [2])
        XCTAssertEqual(state.title(for: 1), .logo)
    }
    func testPartlyVisibleNeighborsStayFrozenDuringASwipe() {
        var state = SpotlightTitlePresentation()
        for id in 1...3 { state.checkedCache(for: id, hasLogo: false) }
        for id in 1...3 { state.preparedLogo(for: id, protected: [1, 2]) }
        XCTAssertEqual(state.title(for: 1), .text)
        XCTAssertEqual(state.title(for: 2), .text)
        XCTAssertEqual(state.title(for: 3), .logo)
        state.revealOffscreen(protected: [2])
        XCTAssertEqual(state.title(for: 1), .logo)
        XCTAssertEqual(state.title(for: 2), .text)
    }
    func testLeavingExploreCommitsReadyLogosAndRechecksMissingTitles() {
        var state = SpotlightTitlePresentation()
        state.checkedCache(for: 1, hasLogo: false)
        state.checkedCache(for: 2, hasLogo: false)
        state.preparedLogo(for: 1, protected: [1])
        state.leaveViewport()
        XCTAssertEqual(state.title(for: 1), .logo)
        XCTAssertEqual(state.title(for: 2), .checkingCache)
        state.checkedCache(for: 2, hasLogo: true)
        XCTAssertEqual(state.title(for: 2), .logo)
        state.retain([2])
        XCTAssertEqual(state.title(for: 1), .checkingCache)
    }
    func testArtworkCacheProbeNeverStartsANetworkRequest() async throws {
        let transport = SpotlightImageTransport()
        let client = ArtworkDataClient(transport: transport)
        let url = URL(string: "https://art.example/clearlogo.png")!
        let missing = await client.cachedImage(at: url)
        XCTAssertNil(missing)
        let before = await transport.count
        XCTAssertEqual(before, 0)
        let fetched = try await client.image(at: url)
        let cached = await client.cachedImage(at: url)
        XCTAssertEqual(cached?.data, fetched.data)
        let after = await transport.count
        XCTAssertEqual(after, 1)
    }
}

private actor SpotlightImageTransport: HTTPTransport {
    private(set) var count = 0
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        count += 1
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        return (Data("owned-image-bytes".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "image/png", "Cache-Control": "public, max-age=3600"])!)
    }
}
