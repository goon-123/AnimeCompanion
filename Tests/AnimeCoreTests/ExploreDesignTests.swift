import XCTest
@testable import AnimeCore

final class ExploreDesignTests: XCTestCase {
    private func book(_ id: Int, format: String = "manga", rating: String? = "safe") throws -> MangaBakaSeries {
        var value: [String: Any] = ["id": id, "title": "Story \(id)", "type": format]
        if let rating { value["content_rating"] = rating }
        return try JSONDecoder().decode(MangaBakaSeries.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func testNewAndInvalidPreferencesUseCombinedDiscoveryAndAllChoicesRoundTrip() {
        XCTAssertEqual(ExploreDesign(preference: nil), .discover)
        XCTAssertEqual(ExploreDesign(preference: "unknown"), .discover)
        for design in ExploreDesign.allCases { XCTAssertEqual(ExploreDesign(preference: design.rawValue), design) }
    }
    func testMixedDiscoveryIncludesEachFormatEarlyAndKeepsAdaptationsDistinct() throws {
        let items = ExploreStory.mix(anime: [Anime(id: 1, title: "Adaptation"), Anime(id: 2, title: "Other anime")],
            reading: [try book(1), try book(2)], novels: [try book(3, format: "novel")], includeAdult: false)
        XCTAssertEqual(items.map(\.id), ["anilist:1", "mangabaka:1", "mangabaka:3", "anilist:2", "mangabaka:2"])
        XCTAssertEqual(items.prefix(3).map(\.format), ["Anime", "Manga", "Novels"])
    }
    func testRepeatedPagesAndShelfOverlapsNeverDuplicateAProviderIdentity() throws {
        let novel = try book(2, format: "novel"), manga = try book(1)
        let items = ExploreStory.mix(anime: [Anime(id: 1, title: "A"), Anime(id: 1, title: "A")],
            reading: [manga, novel, manga], novels: [novel, novel], includeAdult: false)
        XCTAssertEqual(items.map(\.id), ["anilist:1", "mangabaka:1", "mangabaka:2"])
    }
    func testAdultAndUnratedBooksAreFilteredBeforeMixedSelection() throws {
        let adult = try JSONDecoder().decode(Anime.self, from: Data(#"{"id":8,"title":{"english":"Adult"},"isAdult":true}"#.utf8))
        let books = [try book(1), try book(2, rating: "pornographic"), try book(3, rating: nil)]
        XCTAssertEqual(ExploreStory.mix(anime: [adult], reading: books, includeAdult: false).map(\.id), ["mangabaka:1"])
        XCTAssertEqual(Set(ExploreStory.mix(anime: [adult], reading: books, includeAdult: true).map(\.id)), Set(["anilist:8", "mangabaka:1", "mangabaka:2", "mangabaka:3"]))
    }
    func testOneUnavailableCatalogDoesNotRemoveTheOtherFormats() throws {
        XCTAssertTrue(ExploreStory.mix(anime: [], reading: [], includeAdult: false).isEmpty)
        XCTAssertEqual(ExploreStory.mix(anime: [Anime(id: 1, title: "A")], reading: [], includeAdult: false).map(\.id), ["anilist:1"])
        XCTAssertEqual(ExploreStory.mix(anime: [], reading: [try book(1, format: "novel"), try book(2)], includeAdult: false).map(\.id), ["mangabaka:2", "mangabaka:1"])
    }
}
