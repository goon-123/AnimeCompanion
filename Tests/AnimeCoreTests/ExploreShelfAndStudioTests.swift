import XCTest
@testable import AnimeCore

final class ExploreShelfAndStudioTests: XCTestCase {
    func testPreviousSeasonRollsBackAcrossTheYearAndTopAnimeHasNoSeasonLimit() throws {
        let selection = SeasonSelection(season: .winter, year: 2026)
        let previous = DiscoveryFilters(category: .previousSeason, selection: selection)
        XCTAssertEqual(previous.year, 2025); XCTAssertEqual(previous.season, .fall)
        XCTAssertEqual(previous.sort, .popularity); XCTAssertNil(previous.status)
        let top = DiscoveryFilters(category: .topRated, selection: selection)
        XCTAssertNil(top.year); XCTAssertNil(top.season); XCTAssertNil(top.status)
        XCTAssertEqual(top.sort, .rating)
        XCTAssertTrue(DiscoveryCategory.previousSeason.label(season: selection).contains("Fall 2025"))
    }
    func testExploreRequestsBothNewShelvesWithThePreviousSeasonAndContentPolicy() async throws {
        let transport = MockTransport([.json(#"{"data":{"seasonal":{},"trending":{},"upcoming":{},"previousSeason":{"media":[{"id":1}]},"topRated":{"media":[{"id":2}]}}}"#)])
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        let response = try await api.explore(SeasonSelection(season: .winter, year: 2026))
        XCTAssertEqual(response.media(for: .previousSeason).map(\.id), [1])
        XCTAssertEqual(response.media(for: .topRated).map(\.id), [2])
        let requests = await transport.recorded()
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests.first?.httpBody)) as? [String: Any])
        let variables = try XCTUnwrap(body["variables"] as? [String: Any])
        XCTAssertEqual(variables["previousYear"] as? Int, 2025)
        XCTAssertEqual(variables["previousSeason"] as? String, "FALL")
        XCTAssertEqual(variables["isAdult"] as? Bool, false)
        XCTAssertTrue((body["query"] as? String)?.contains("sort: [SCORE_DESC, POPULARITY_DESC]") == true)
    }
    func testStudioUsesItsOwnIDAndPaginationWhileFilteringAdultAndNonAnimeNodes() async throws {
        let json = #"{"data":{"Studio":{"media":{"nodes":[{"id":1,"type":"ANIME","isAdult":false},{"id":2,"type":"ANIME","isAdult":true},{"id":3,"type":"MANGA"}],"pageInfo":{"hasNextPage":true}}}}}"#
        let transport = MockTransport([.json(json), .json(json)])
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        let safe = try await api.studioAnime(id: 44, page: 2, sort: .rating)
        XCTAssertEqual(safe.media?.map(\.id), [1]); XCTAssertEqual(safe.pageInfo?.hasNextPage, true)
        let adult = try await api.studioAnime(id: 44, page: 3, includeAdult: true)
        XCTAssertEqual(adult.media?.map(\.id), [1, 2])
        let requests = await transport.recorded()
        XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests.first?.httpBody)) as? [String: Any])
        let variables = try XCTUnwrap(body["variables"] as? [String: Any])
        XCTAssertEqual(variables["id"] as? Int, 44); XCTAssertEqual(variables["page"] as? Int, 2)
        XCTAssertEqual(variables["sort"] as? String, "SCORE_DESC")
        XCTAssertNil(variables["search"])
    }
    func testMissingOrInvalidStudioFailsWithoutInventingAnEmptyCatalog() async throws {
        let transport = MockTransport([.json(#"{"data":{"Studio":null}}"#)])
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        do { _ = try await api.studioAnime(id: 0); XCTFail("Invalid studio accepted") } catch {}
        let invalidRequests = await transport.recorded()
        XCTAssertTrue(invalidRequests.isEmpty)
        do { _ = try await api.studioAnime(id: 44); XCTFail("Missing studio accepted") } catch {}
    }
}
