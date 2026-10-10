import XCTest
@testable import AnimeCore
import Foundation

final class GenreNavigationTests: XCTestCase {
    func testGenreShortcutSearchesAllYearsAndSeasonsWithNoStaleTextOrStatus() throws {
        let filters = DiscoveryFilters(genre: "Sci-Fi")
        let variables = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(filters.variables(page: 1))) as? [String: Any])
        XCTAssertEqual(variables["genre"] as? String, "Sci-Fi")
        XCTAssertEqual(variables["sort"] as? String, DiscoverySort.popularity.rawValue)
        for key in ["search", "year", "season", "status", "format"] { XCTAssertNil(variables[key], key) }
    }
    func testRelatedGenresAreOptionalAndDecodeForBothSupportingSections() throws {
        let old = try JSONDecoder().decode(RelatedAnime.self, from: Data(#"{"id":1,"title":{"english":"Legacy record"}}"#.utf8))
        XCTAssertNil(old.genres)
        let title = try JSONDecoder().decode(Anime.self, from: Data(#"{"id":2,"relations":{"edges":[{"node":{"id":1,"genres":["Action","Sci-Fi"]}}]},"recommendations":{"nodes":[{"id":3,"mediaRecommendation":{"id":4,"genres":["Drama"]}}]}}"#.utf8))
        XCTAssertEqual(title.relations?.edges?.first?.node?.genres, ["Action", "Sci-Fi"])
        XCTAssertEqual(title.recommendations?.nodes?.first?.mediaRecommendation?.genres, ["Drama"])
    }
}
