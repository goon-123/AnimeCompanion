import XCTest
import AnimeCore
@testable import AnimeCompanion

@MainActor
final class MangaBrowseModelTests: XCTestCase {
    private let source = MangaSourceReference(extensionID: "owned", sourceID: "1", name: "Owned", language: "en", homeURL: "https://owned.invalid")

    func testPaginationAppendsAndStopsWhenSourceEnds() async {
        let client = OwnedCatalog([.success(page("a", next: true)), .success(page("b", next: false))]), model = MangaBrowseModel()
        await load(model, client, reset: true)
        await load(model, client)
        await load(model, client)
        XCTAssertEqual(client.calls.map(\.page), [1, 2])
        XCTAssertEqual(model.mangas.map(\.url), ["a", "b"])
        XCTAssertFalse(model.loading)
        XCTAssertFalse(model.hasNext)
    }
    func testRepeatsPauseAutomaticRequestsButPermitOneExplicitNextPage() async {
        let client = OwnedCatalog([.success(page("a", next: true)), .success(page("a", next: true)), .success(page("b", next: false))])
        let model = MangaBrowseModel()
        await load(model, client, reset: true)
        await load(model, client, automatic: true)
        for _ in 0..<5 { await load(model, client, automatic: true) }
        XCTAssertEqual(client.calls.map(\.page), [1, 2])
        XCTAssertTrue(model.stalled)
        XCTAssertFalse(model.loading)
        await load(model, client)
        XCTAssertEqual(client.calls.map(\.page), [1, 2, 3])
        XCTAssertEqual(model.mangas.map(\.url), ["a", "b"])
    }
    func testFailedPageRetriesTheSamePageAndNeverClearsLoadedEntries() async {
        let client = OwnedCatalog([.success(page("a", next: true)), .failure(URLError(.timedOut)), .success(page("b", next: false))])
        let model = MangaBrowseModel()
        await load(model, client, reset: true)
        await load(model, client, automatic: true)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.mangas.map(\.url), ["a"])
        await load(model, client, automatic: true)
        XCTAssertEqual(client.calls.count, 2, "Errors must not automatically retry forever")
        await load(model, client)
        XCTAssertEqual(client.calls.map(\.page), [1, 2, 2])
        XCTAssertNil(model.error)
        XCTAssertEqual(model.mangas.map(\.url), ["a", "b"])
    }
    func testCancelledNextPageCanResumeWithoutSkippingOrDuplicatingARequest() async {
        let client = OwnedCatalog([.success(page("a", next: true)), .success(page("b", next: false))]), model = MangaBrowseModel()
        await load(model, client, reset: true)
        let started = expectation(description: "Second page started")
        client.holdNext = true; client.started = started
        let request = Task { await load(model, client) }
        await fulfillment(of: [started], timeout: 3)
        XCTAssertTrue(model.loading)
        await load(model, client)
        XCTAssertEqual(client.calls.count, 2, "Two visible footer events must not overlap")
        request.cancel()
        client.finish(page("b", next: false))
        await request.value
        XCTAssertEqual(model.pagination.page, 1)
        XCTAssertEqual(model.mangas.map(\.url), ["a"])
        XCTAssertNil(model.error)
        XCTAssertFalse(model.loading)
        await load(model, client)
        XCTAssertEqual(client.calls.map(\.page), [1, 2, 2])
        XCTAssertEqual(model.mangas.map(\.url), ["a", "b"])
    }
    func testChangingSearchIgnoresLateResultsAndOldFooterRequests() async {
        let client = OwnedCatalog([.success(page("new", next: false))]), model = MangaBrowseModel()
        let started = expectation(description: "Old search started")
        client.holdNext = true; client.started = started
        let old = Task { await load(model, client, reset: true, query: "old") }
        await fulfillment(of: [started], timeout: 3)
        await load(model, client, reset: true, query: "new")
        client.finish(page("old", next: true))
        await old.value
        await load(model, client, query: "old")
        XCTAssertEqual(client.calls.map(\.query), ["old", "new"])
        XCTAssertEqual(model.mangas.map(\.url), ["new"])
        XCTAssertFalse(model.loading)
    }
    func testReturningToAnEmptyCompletedSearchDoesNotFetchItForever() async {
        let client = OwnedCatalog([.success(.init(mangas: [], hasNext: false))]), model = MangaBrowseModel()
        await model.loadIfNeeded(source, extensions: client, mode: "search", query: "missing")
        await model.loadIfNeeded(source, extensions: client, mode: "search", query: "missing")
        XCTAssertEqual(client.calls.count, 1)
        XCTAssertNil(model.error)
    }
    func testAnimeShortcutReplacesOnlyMangaPathAndKeepsAnimeNavigation() {
        let navigation = AppNavigationStore()
        navigation.selectedTab = .library
        navigation.library.path.append(AnimeRoute(id: 7))
        navigation.manga.path.append(AnimeRoute(id: 123))
        navigation.openMangaSearch(for: Anime(id: 7, title: "Owned title"))
        XCTAssertEqual(navigation.selectedTab, .manga)
        XCTAssertEqual(navigation.manga.path.count, 1)
        XCTAssertEqual(navigation.library.path.count, 1)
        navigation.selectedTab = .explore
        navigation.openMangaSearch(for: Anime(id: 8, title: "Another title"))
        XCTAssertEqual(navigation.manga.path.count, 1, "A second shortcut must not stack an old title search")
    }
    private func load(_ model: MangaBrowseModel, _ client: OwnedCatalog, reset: Bool = false, automatic: Bool = false, query: String = "") async {
        await model.load(source, extensions: client, mode: query.isEmpty ? "popular" : "search", query: query, reset: reset, automatic: automatic)
    }
    private func page(_ url: String, next: Bool) -> SourceMangaPage {
        .init(mangas: [.init(url: url, title: url)], hasNext: next)
    }
}

@MainActor
private final class OwnedCatalog: MangaCatalogLoading {
    struct Call { let page: Int; let query: String }
    var calls: [Call] = []
    var holdNext = false
    var started: XCTestExpectation?
    private var pending: CheckedContinuation<SourceMangaPage, Error>?
    private var results: [Result<SourceMangaPage, Error>]
    init(_ results: [Result<SourceMangaPage, Error>]) { self.results = results }
    func browse(extensionID: String, sourceID: String, mode: String, query: String, page: Int) async throws -> SourceMangaPage {
        calls.append(.init(page: page, query: query))
        if holdNext {
            holdNext = false
            return try await withCheckedThrowingContinuation { continuation in
                pending = continuation; started?.fulfill(); started = nil
            }
        }
        guard !results.isEmpty else { XCTFail("Unexpected extra catalog request"); throw URLError(.badServerResponse) }
        return try results.removeFirst().get()
    }
    func finish(_ page: SourceMangaPage) { pending?.resume(returning: page); pending = nil }
}
