import XCTest
@testable import AnimeCore

final class SeriesPresentationTests: XCTestCase {
    func testSynopsisCollapsesRepeatedHTMLParagraphBreaksAndIndentation() {
        let raw = "<p> First paragraph.</p>\n  \n<br /><br>\n\n<p>Second&nbsp;  paragraph.</p>"
        XCTAssertEqual(TextSanitizer.synopsis(raw), "First paragraph.\n\nSecond paragraph.")
        XCTAssertEqual(TextSanitizer.synopsis(" A\r\n\r\n\r\n B "), "A\n\nB")
        XCTAssertEqual(TextSanitizer.synopsis("<b>Story</b> &amp; people"), "Story & people")
    }
    func testPosterURLSkipsBlankAndMalformedPreferredSizes() throws {
        let anime = try JSONDecoder().decode(Anime.self, from: Data(#"{"id":1,"coverImage":{"extraLarge":"  ","large":"https://art.example/large.jpg","medium":"https://art.example/medium.jpg"}}"#.utf8))
        XCTAssertEqual(anime.coverURL?.absoluteString, "https://art.example/large.jpg")
        let invalid = try JSONDecoder().decode(Anime.self, from: Data(#"{"id":2,"coverImage":{"extraLarge":"not-a-url","large":"","medium":"https://art.example/medium.jpg"}}"#.utf8))
        XCTAssertEqual(invalid.coverURL?.absoluteString, "https://art.example/medium.jpg")
    }
}
