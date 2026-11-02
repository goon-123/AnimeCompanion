import XCTest
@testable import AnimeCore

final class AnimeEpisodeFilterTests: XCTestCase {
    func testUnwatchedRowsBeyondFirstMetadataPageRemainAvailableWithoutInventedDetails() throws {
        let anime = try JSONDecoder().decode(Anime.self, from: Data(#"{"id":1,"status":"FINISHED","episodes":500}"#.utf8))
        let metadata = (1...100).map { AnimeEpisodeMetadata(number: $0, title: "Real title \($0)") }
        let rows = AnimeEpisodeReleaseGroups.listedEpisodes(anime: anime, metadata: metadata, watched: 250)
        let unwatched = rows.filter { AnimeEpisodeFilter.unwatched.includes(episode: $0.number, watchedThrough: 250) }
        XCTAssertEqual(unwatched.first?.number, 251)
        XCTAssertEqual(unwatched.count, 250)
        XCTAssertNil(unwatched.first?.title); XCTAssertNil(unwatched.first?.airDate); XCTAssertNil(unwatched.first?.imageURL)
        XCTAssertEqual(rows.first?.title, "Real title 1")
    }
    func testUnknownReleaseCountsDoNotFillPlannedButUnconfirmedRowsFromPartialMetadata() throws {
        let anime = try JSONDecoder().decode(Anime.self, from: Data(#"{"id":1,"status":"RELEASING","episodes":500}"#.utf8))
        let rows = AnimeEpisodeReleaseGroups.listedEpisodes(anime: anime, metadata: [AnimeEpisodeMetadata(number: 1)], watched: 0)
        XCTAssertEqual(rows.map(\.number), [1])
    }
    func testInitialAndInvalidDefaultsUseUnwatchedAndExplicitChoicesSurviveSaving() {
        for value in ["", "invalid", "Unwatched"] {
            XCTAssertEqual(AnimeEpisodeFilter.defaultValue(saved: value), .unwatched)
        }
        for filter in AnimeEpisodeFilter.allCases {
            XCTAssertEqual(AnimeEpisodeFilter.defaultValue(saved: filter.rawValue), filter)
        }
    }
    func testFiltersRespectCumulativeProgressAndUnwatchMakesLaterRowsUnwatched() {
        let episodes = Array(1...6)
        XCTAssertEqual(episodes.filter { AnimeEpisodeFilter.unwatched.includes(episode: $0, watchedThrough: 4) }, [5, 6])
        XCTAssertEqual(episodes.filter { AnimeEpisodeFilter.watched.includes(episode: $0, watchedThrough: 4) }, [1, 2, 3, 4])
        XCTAssertEqual(episodes.filter { AnimeEpisodeFilter.all.includes(episode: $0, watchedThrough: 4) }, episodes)
        XCTAssertEqual(episodes.filter { AnimeEpisodeFilter.unwatched.includes(episode: $0, watchedThrough: 2) }, [3, 4, 5, 6])
    }
    func testOriginalBroadcastWidgetOnlyAppliesToCurrentlyReleasingSeries() throws {
        for status in ["RELEASING", "FINISHED", "NOT_YET_RELEASED", "CANCELLED", "HIATUS"] {
            let anime = try JSONDecoder().decode(Anime.self, from: JSONSerialization.data(withJSONObject: ["id": 1, "status": status]))
            XCTAssertEqual(AnimeSeriesContent.showsOriginalBroadcast(for: anime), status == "RELEASING")
        }
        XCTAssertFalse(AnimeSeriesContent.showsOriginalBroadcast(for: Anime(id: 1, title: "Unknown status")))
    }
}
