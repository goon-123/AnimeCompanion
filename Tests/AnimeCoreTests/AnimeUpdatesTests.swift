import XCTest
@testable import AnimeCore

final class AnimeUpdatesTests: XCTestCase {
    func testVisualsKeepSeasonOrderDeduplicateAndRespectContentPolicy() throws {
        let response = try JSONDecoder().decode(ExploreResponse.self, from: Data(#"{"seasonal":{"media":[{"id":1,"coverImage":{"large":"https://images.example/1.jpg"}},{"id":2,"isAdult":true,"coverImage":{"large":"https://images.example/2.jpg"}},{"id":3},{"id":4,"coverImage":{"large":"javascript:bad"}}]},"upcoming":{"media":[{"id":1,"coverImage":{"large":"https://images.example/1.jpg"}},{"id":5,"coverImage":{"large":"https://images.example/5.jpg"}}]},"trending":{"media":[{"id":9,"coverImage":{"large":"https://images.example/9.jpg"}}]}}"#.utf8))
        XCTAssertEqual(AnimeUpdates.visuals(in: response, includeAdult: false).map(\.id), [1, 5])
        XCTAssertEqual(AnimeUpdates.visuals(in: response, includeAdult: true).map(\.id), [1, 2, 5])
        XCTAssertTrue(AnimeUpdates.visuals(in: nil, includeAdult: false).isEmpty)
    }
    func testHeadlinesMatchAliasesPunctuationAndAccentsButNotPartialWords() throws {
        let anime = try JSONDecoder().decode(Anime.self, from: Data(#"{"id":1,"title":{"romaji":"Sora no Tabi","english":"Sky's Journey","userPreferred":"Café Adventure"}}"#.utf8))
        for title in ["New SKY’S JOURNEY trailer", "Sora-no-Tabi announces cast", "Cafe Adventure visual revealed"] {
            XCTAssertTrue(AnimeUpdates.headline(article(title), matches: anime), title)
        }
        XCTAssertFalse(AnimeUpdates.headline(article("Sora no Tabitha returns"), matches: anime))
        XCTAssertFalse(AnimeUpdates.headline(article("Another show's new visual"), matches: anime))
        XCTAssertFalse(AnimeUpdates.headline(article("Untitled story"), matches: try JSONDecoder().decode(Anime.self, from: Data(#"{"id":2}"#.utf8))))
    }
    func testShortAndNonLatinTitlesUseWholeTitleBoundaries() {
        XCTAssertTrue(AnimeUpdates.headline(article("86: New trailer"), matches: Anime(id: 1, title: "86")))
        XCTAssertFalse(AnimeUpdates.headline(article("186 releases announced"), matches: Anime(id: 1, title: "86")))
        XCTAssertTrue(AnimeUpdates.headline(article("「日本語」 新ビジュアル"), matches: Anime(id: 2, title: "日本語")))
    }
    private func article(_ title: String) -> NewsArticle {
        NewsArticle(title: title, url: URL(string: "https://www.animenewsnetwork.com/news/owned")!, publishedAt: nil, imageURL: nil)
    }
}
