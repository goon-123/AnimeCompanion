import XCTest
@testable import AnimeCore

final class PosterAccentTests: XCTestCase {
    func testParsesCoverColorsAndRejectsMissingOrMalformedValues() throws {
        let warm = try XCTUnwrap(PosterAccent(hex: " #FFCC33 \n"))
        XCTAssertEqual(warm.red, 1)
        XCTAssertEqual(warm.green, 0.8, accuracy: 0.0001)
        XCTAssertEqual(warm.blue, 0.2, accuracy: 0.0001)
        XCTAssertEqual(warm, PosterAccent(hex: "ffcc33"))
        for input in [nil, "", "#fff", "##ffcc33", "zz0000", "12345678"] as [String?] {
            XCTAssertNil(PosterAccent(hex: input))
        }
    }
    func testWarmAndCoolCoversProduceDistinctReadableBackgrounds() throws {
        let warm = try XCTUnwrap(PosterAccent(hex: "#ffcc33")).backdrop
        let cool = try XCTUnwrap(PosterAccent(hex: "#80c8e0")).backdrop
        XCTAssertGreaterThan(warm.red, warm.green)
        XCTAssertGreaterThan(warm.green, warm.blue)
        XCTAssertGreaterThan(cool.blue, cool.green)
        XCTAssertGreaterThan(cool.green, cool.red)
        XCTAssertNotEqual(warm, cool)
        for hex in ["#ffffff", "#000000", "#ffcc33", "#80c8e0", "#ff00ff", "#00ff00"] {
            let color = try XCTUnwrap(PosterAccent(hex: hex)).backdrop
            XCTAssertGreaterThanOrEqual(1.05 / (color.luminance + 0.05), 4.5)
        }
    }
    func testInvalidChannelsAreFiniteAndBounded() {
        let color = PosterAccent(red: .nan, green: -.infinity, blue: 42).backdrop
        XCTAssertTrue(color.luminance.isFinite)
        XCTAssertTrue((0...1).contains(color.red))
        XCTAssertTrue((0...1).contains(color.green))
        XCTAssertTrue((0...1).contains(color.blue))
    }
    func testOlderMetadataWithoutColorStillDecodes() throws {
        let anime = try JSONDecoder().decode(Anime.self, from: Data(#"{"id":1,"coverImage":{"large":"https://image.example/poster.jpg"}}"#.utf8))
        XCTAssertNil(anime.coverImage?.color)
        XCTAssertNotNil(anime.coverURL)
    }
}
