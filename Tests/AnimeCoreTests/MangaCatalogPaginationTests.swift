import XCTest
@testable import AnimeCore

final class MangaCatalogPaginationTests: XCTestCase {
    func testOverlappingPagesAppendOnlyNewURLsInSourceOrder() {
        var catalog = MangaCatalogPagination()
        catalog.append(.init(mangas: [manga("a"), manga("a"), manga(""), manga("  "), manga("b")], hasNext: true))
        catalog.append(.init(mangas: [manga("b"), manga("c"), manga("d")], hasNext: true))
        XCTAssertEqual(catalog.mangas.map(\.url), ["a", "b", "c", "d"])
        XCTAssertEqual(catalog.page, 2)
        XCTAssertEqual(catalog.continuation, .more)
    }
    func testRepeatedPagePausesWithoutPretendingTheSourceEnded() {
        var catalog = MangaCatalogPagination()
        catalog.append(.init(mangas: [manga("a")], hasNext: true))
        catalog.append(.init(mangas: [manga("a")], hasNext: true))
        XCTAssertEqual(catalog.mangas.count, 1)
        XCTAssertEqual(catalog.continuation, .stalled)
        catalog.append(.init(mangas: [manga("b")], hasNext: false))
        XCTAssertEqual(catalog.mangas.map(\.url), ["a", "b"])
        XCTAssertEqual(catalog.page, 3)
        XCTAssertEqual(catalog.continuation, .end)
    }
    func testEmptyPageWithHasNextAlsoPausesIncludingTheFirstPage() {
        var catalog = MangaCatalogPagination()
        catalog.append(.init(mangas: [], hasNext: true))
        XCTAssertEqual(catalog.continuation, .stalled)
        XCTAssertEqual(catalog.page, 1)
    }
    func testTrueLastPageAndFreshSearchHaveIndependentState() {
        var catalog = MangaCatalogPagination()
        catalog.append(.init(mangas: [manga("a")], hasNext: false))
        XCTAssertEqual(catalog.continuation, .end)
        catalog = MangaCatalogPagination()
        XCTAssertEqual(catalog.page, 0)
        catalog.append(.init(mangas: [manga("a")], hasNext: true))
        XCTAssertEqual(catalog.mangas.count, 1)
        XCTAssertEqual(catalog.continuation, .more)
    }
    func testEmptyLastPageIsAnEndNotAnErrorOrLoop() {
        var catalog = MangaCatalogPagination()
        catalog.append(.init(mangas: [], hasNext: false))
        XCTAssertEqual(catalog.continuation, .end)
    }
    func testAnimeSearchSuggestionsKeepOriginalNamesAndRemoveBlankDuplicates() throws {
        let anime = try JSONDecoder().decode(Anime.self, from: Data(#"{"id":99,"title":{"english":"  A Story  ","userPreferred":"a story","romaji":"Monogatari"}}"#.utf8))
        XCTAssertEqual(MangaSearchTitles.suggestions(for: anime), ["A Story", "Monogatari"])
        let untitled = try JSONDecoder().decode(Anime.self, from: Data(#"{"id":99,"title":{"english":" "}}"#.utf8))
        XCTAssertEqual(MangaSearchTitles.suggestions(for: untitled), [], "An anime ID is not a manga search title")
    }
    private func manga(_ url: String) -> SourceManga { .init(url: url, title: url) }
}
