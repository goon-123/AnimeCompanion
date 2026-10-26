import XCTest
@testable import AnimeCore

final class ContentAndLibraryPreferencesTests: XCTestCase {
    private func book(_ id: Int, title: String = "Story", content: String? = "safe", chapter: Double = 4,
                      total: Double? = 10, rating: Int? = nil, updated: String? = nil) throws -> MangaBakaLibraryEntry {
        var series: [String: Any] = ["id": id, "title": title, "type": "manga"]
        series["content_rating"] = content; series["total_chapters"] = total
        var record: [String: Any] = ["series_id": id, "series": series, "state": "reading", "progress_chapter": chapter]
        record["rating"] = rating; record["updated_at"] = updated
        return try JSONDecoder().decode(MangaBakaLibraryEntry.self, from: JSONSerialization.data(withJSONObject: record))
    }
    func testEveryRatingCombinationIsIndependentAndPersistsWithoutBroadening() throws {
        for mask in 0..<16 {
            let selected = Set(MangaBakaContentRating.allCases.enumerated().compactMap { mask & (1 << $0.offset) == 0 ? nil : $0.element })
            let filter = MangaBakaContentFilter(ratings: selected)
            let restored = MangaBakaContentFilter(saved: filter.saved, legacyIncludeAdult: true)
            XCTAssertEqual(restored, filter)
            for rating in MangaBakaContentRating.allCases {
                XCTAssertEqual(try book(1, content: rating.rawValue).series?.isVisible(contentFilter: restored), selected.contains(rating))
            }
            XCTAssertFalse(restored.includes(nil)); XCTAssertFalse(restored.includes("future_rating"))
        }
    }
    func testLegacyMigrationAndUnratedChoiceAreExplicit() {
        XCTAssertEqual(MangaBakaContentFilter(saved: nil).ratings, [.safe, .suggestive])
        XCTAssertEqual(MangaBakaContentFilter(saved: nil, legacyIncludeAdult: true), .legacy(includeAdult: true))
        let selected = MangaBakaContentFilter(ratings: [.suggestive, .erotica], includeUnrated: true)
        let saved = MangaBakaContentFilter(saved: selected.saved, legacyIncludeAdult: false)
        XCTAssertEqual(saved, selected); XCTAssertTrue(saved.includes(nil)); XCTAssertTrue(saved.includes(" Erotica "))
        XCTAssertFalse(saved.includes("safe")); XCTAssertFalse(saved.includes("pornographic"))
        XCTAssertEqual(MangaBakaContentFilter(saved: "damaged"), .init())
    }
    func testSearchCuratedAndFacetRequestsKeepExactEnabledRatings() throws {
        let filter = MangaBakaContentFilter(ratings: [.suggestive, .erotica])
        for query in [MangaBakaQuery(text: "Letters"), .init(shelf: .rising), .init(format: .novel), .init(tags: [.init(id: 12, name: "fiction")])] {
            let url = MangaBakaClient.browseURL(query, page: 2, limit: 24, contentFilter: filter)
            let values = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(values.filter { $0.name == "content_rating" }.compactMap(\.value), ["suggestive", "erotica"])
        }
        let gems = MangaBakaClient.browseURL(.init(shelf: .hiddenGems), page: 1, limit: 24, contentFilter: filter)
        XCTAssertEqual(gems.path, "/v2/series/discover/hidden-gems")
        let values = try XCTUnwrap(URLComponents(url: gems, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(values.filter { $0.name == "not_content_rating" }.compactMap(\.value), ["safe", "pornographic"])
        let query = MangaBakaQuery(contentRatings: [.safe, .erotica])
        XCTAssertEqual(query.allowedRatings(contentFilter: filter), [.erotica])
        XCTAssertFalse(query.includes(try XCTUnwrap(book(1).series), contentFilter: filter))
    }
    func testCachedRecommendationsRefilterImmediatelyWithoutChangingWeeklyTimestamp() throws {
        let values = try [book(1, content: "safe"), book(2, content: "suggestive"), book(3, content: "erotica"), book(4, content: "pornographic")].compactMap(\.series)
        let account = UUID(), date = Date(timeIntervalSince1970: 1_000_000)
        var state = MangaBakaRecommendationsState()
        let request = try XCTUnwrap(state.begin(account: account, contentFilter: .legacy(includeAdult: true), now: date))
        XCTAssertTrue(state.complete(values, for: request, now: date)); state.finish(request)
        XCTAssertNil(state.begin(account: account, contentFilter: .init(ratings: [.suggestive, .erotica]), now: date.addingTimeInterval(10)))
        XCTAssertEqual(state.items.map(\.id), [2, 3]); XCTAssertEqual(state.fetchedAt, date)
        XCTAssertNil(state.begin(account: account, contentFilter: .init(ratings: []), now: date.addingTimeInterval(20)))
        XCTAssertTrue(state.items.isEmpty); XCTAssertEqual(state.fetchedAt, date)
    }
    func testCombinedAndExploreApplyMangaBakaSettingsIndependentlyOfAnime() throws {
        let adult = try JSONDecoder().decode(LibraryEntry.self, from: Data(#"{"id":1,"mediaId":1,"status":"CURRENT","media":{"id":1,"isAdult":true,"title":{"english":"Owned anime"}}}"#.utf8))
        let books = try [book(1, content: "erotica"), book(2, content: "pornographic"), book(3, content: "safe")]
        let filter = MangaBakaContentFilter(ratings: [.erotica])
        XCTAssertEqual(CombinedLibraryItem.merge(anime: [adult], reading: books, includeAdult: false, contentFilter: filter).map(\.id), ["mangabaka:1"])
        XCTAssertEqual(Set(CombinedLibraryItem.merge(anime: [adult], reading: books, includeAdult: true, contentFilter: filter).map(\.id)), ["anilist:1", "mangabaka:1"])
        let stories = ExploreStory.mix(anime: [try XCTUnwrap(adult.media)], reading: books.compactMap(\.series), includeAdult: false, contentFilter: filter)
        XCTAssertEqual(stories.map(\.id), ["mangabaka:1"])
    }
    func testOpeningDefaultsAreActiveAndSavedIndependently() throws {
        let name = "library-preferences-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name)); defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(LibraryScope.anime.openingStatus(in: defaults), "CURRENT")
        XCTAssertEqual(LibraryScope.reading.openingStatus(in: defaults), "reading")
        XCTAssertEqual(LibraryScope.combined.openingStatus(in: defaults), "active")
        defaults.set("completed", forKey: LibraryScope.reading.defaultStatusKey)
        defaults.set("all", forKey: LibraryScope.combined.defaultStatusKey)
        XCTAssertEqual(LibraryScope.reading.openingStatus(in: defaults), "completed")
        XCTAssertEqual(LibraryScope.combined.openingStatus(in: defaults), "all")
        defaults.set("retired-status", forKey: LibraryScope.anime.defaultStatusKey)
        XCTAssertEqual(LibraryScope.anime.openingStatus(in: defaults), "CURRENT")
    }
    func testSortDirectionAndMissingValuesRemainStable() throws {
        let values = try [book(1, title: "Zulu", rating: 20), book(2, title: "Alpha", rating: 90), book(3, title: "Bravo")]
        XCTAssertEqual(ReadingLibrarySort.score.sorted(values, ascending: false).map(\.id), [2, 1, 3])
        XCTAssertEqual(ReadingLibrarySort.score.sorted(values, ascending: true).map(\.id), [1, 2, 3])
        XCTAssertEqual(ReadingLibrarySort.title.sorted(values, ascending: true).map(\.id), [2, 3, 1])
        XCTAssertEqual(ReadingLibrarySort.title.sorted(values, ascending: false).map(\.id), [1, 3, 2])
    }
    func testLastUpdatedParsesTimezonesFractionalDatesAndPutsUnknownLastInBothDirections() throws {
        let values = try [book(1, updated: "2026-10-25T20:00:00-07:00"), book(2, updated: "2026-10-26T03:00:01.500Z"), book(3)]
        XCTAssertEqual(ReadingLibrarySort.updated.sorted(values, ascending: false).map(\.id), [2, 1, 3])
        XCTAssertEqual(ReadingLibrarySort.updated.sorted(values, ascending: true).map(\.id), [1, 2, 3])
    }
    func testCombinedCompletionUsesFractionsInsteadOfComparingChaptersWithEpisodes() throws {
        let anime = try JSONDecoder().decode(LibraryEntry.self, from: Data(#"{"id":1,"mediaId":1,"status":"CURRENT","progress":6,"media":{"id":1,"episodes":12,"title":{"english":"Anime"}}}"#.utf8))
        let values: [CombinedLibraryItem] = try [.anime(anime), .reading(book(2, chapter: 40, total: 100)), .reading(book(3, chapter: 10, total: nil))]
        XCTAssertEqual(ReadingLibrarySort.completion.sorted(values, ascending: false).map(\.id), ["anilist:1", "mangabaka:2", "mangabaka:3"])
        XCTAssertEqual(ReadingLibrarySort.completion.sorted(values, ascending: true).map(\.id), ["mangabaka:2", "anilist:1", "mangabaka:3"])
    }
}
