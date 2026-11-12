import XCTest
import Combine
import AnimeCore
@testable import AnimeCompanion

final class TabResponsivenessTests: XCTestCase {
    @MainActor func testTabSelectionOnlyPublishesToItsNarrowObserver() {
        let navigation = AppNavigationStore()
        var broadUpdates = 0
        var selectionUpdates = 0
        let broad = navigation.objectWillChange.sink { broadUpdates += 1 }
        let narrow = navigation.tabSelection.objectWillChange.sink { selectionUpdates += 1 }
        defer { broad.cancel(); narrow.cancel() }
        navigation.selectedTab = .explore
        navigation.selectedTab = .explore
        navigation.selectedTab = .library
        XCTAssertEqual(navigation.selectedTab, .library)
        XCTAssertEqual(broadUpdates, 0, "A dock tap must not invalidate every routing consumer")
        XCTAssertEqual(selectionUpdates, 2, "Repeated selections should not publish again")
    }

    @MainActor func testLeavingThePageDoesNotAbandonTheSharedCatalog() async {
        let transport = CountingReadingTransport(delay: .milliseconds(80))
        let api = MangaBakaClient(transport: transport, directory: nil, minimumRequestInterval: 0)
        let model = MangaBakaHomeModel()
        let page = Task { await model.load(api: api, contentFilter: .init(ratings: [.safe])) }
        try? await Task.sleep(for: .milliseconds(20))
        page.cancel()
        await page.value
        XCTAssertEqual(model.items.count, MangaBakaHomeModel.shelves.count)
        XCTAssertFalse(model.items[.trending, default: []].isEmpty)
        XCTAssertTrue(model.loading.isEmpty)
        XCTAssertTrue(model.errors.isEmpty)
    }

    @MainActor func testReadingCatalogReusesTypedRowsAndPublicDiskCacheWithoutLosingFilters() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = CountingReadingTransport()
        let api = MangaBakaClient(transport: transport, directory: directory, minimumRequestInterval: 0)
        let filter = MangaBakaContentFilter(ratings: [.safe])
        let model = MangaBakaHomeModel()
        await model.load(api: api, contentFilter: filter)
        XCTAssertTrue(model.errors.isEmpty)
        XCTAssertEqual(model.items.count, MangaBakaHomeModel.shelves.count)
        XCTAssertFalse(model.items[.trending, default: []].isEmpty)
        let original = model.items
        let firstCount = await transport.count
        XCTAssertEqual(firstCount, 7)
        await model.load(api: api, contentFilter: filter)
        let revisitCount = await transport.count
        XCTAssertEqual(revisitCount, firstCount)
        XCTAssertEqual(model.items, original)
        // A new session uses the existing provider byte cache, decoded off-main.
        let restartedAPI = MangaBakaClient(transport: transport, directory: directory, minimumRequestInterval: 0)
        let restarted = MangaBakaHomeModel()
        await restarted.load(api: restartedAPI, contentFilter: filter)
        let restartedCount = await transport.count
        XCTAssertEqual(restartedCount, firstCount)
        XCTAssertEqual(restarted.items, original)
        await restarted.load(api: restartedAPI, contentFilter: .init(ratings: [.suggestive]))
        XCTAssertTrue(restarted.items.values.allSatisfy(\.isEmpty), "Safe rows cannot leak into a different content filter")
        let changedCount = await transport.count
        XCTAssertGreaterThan(changedCount, firstCount)
        await model.load(api: api, contentFilter: filter, refresh: true)
        let refreshedCount = await transport.count
        XCTAssertGreaterThan(refreshedCount, changedCount, "Explicit refresh still reaches the provider")
    }
}
private actor CountingReadingTransport: HTTPTransport {
    private(set) var count = 0
    let delay: Duration
    init(delay: Duration = .zero) { self.delay = delay }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        count += 1
        if delay > .zero { try await Task.sleep(for: delay) }
        return try await UnifiedReadingPreviewTransport().data(for: request)
    }
}
