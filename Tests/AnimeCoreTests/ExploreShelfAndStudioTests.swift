import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AnimeCore

final class ExploreShelfAndStudioTests: XCTestCase {
    func testStudioDirectoryUsesOneBatchedRequestAndSafeRepresentativeCovers() async throws {
        let json = #"{"data":{"Page":{"studios":[{"id":569,"name":"MAPPA","media":{"nodes":[{"id":1,"type":"ANIME","isAdult":true},{"id":2,"type":"MANGA"},{"id":3,"type":"ANIME","isAdult":false}]}}]}}}"#
        let transport = ExploreStudioTransport([.json(json)])
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        let result = try await api.studioCollections()
        XCTAssertEqual(result.map(\.studio.id), [569])
        XCTAssertEqual(result.first?.anime.map(\.id), [3])
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 1)
        XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests.first?.httpBody)) as? [String: Any])
        let query = try XCTUnwrap(body["query"] as? String)
        XCTAssertTrue(query.contains("studios(id_in: $ids)"))
        XCTAssertFalse(query.contains("s569:"))
        let variables = try XCTUnwrap(body["variables"] as? [String: Any])
        XCTAssertEqual(variables["ids"] as? [Int], AnimeStudioCollection.featured.map(\.id))
    }
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
    func testStudioDirectoryStopsAtRateLimitsInsteadOfRetryingEveryStudio() async throws {
        for responses in [[ExploreStudioTransport.Response.json("{}", status: 429)],
                          [.json("{}", status: 400), .json("{}", status: 429)]] {
            let transport = ExploreStudioTransport(responses)
            let api = AniListClient(transport: transport, minimumRequestInterval: 0)
            do { _ = try await api.studioCollections(); XCTFail("Rate limit was swallowed") }
            catch let error as ServiceError {
                guard case .rateLimited = error else { return XCTFail("Unexpected error: \(error)") }
            }
            let requests = await transport.recorded()
            XCTAssertEqual(requests.count, responses.count)
        }
    }
    func testExploreRequestsBothNewShelvesWithThePreviousSeasonAndContentPolicy() async throws {
        let transport = ExploreStudioTransport([.json(#"{"data":{"seasonal":{},"trending":{},"upcoming":{},"previousSeason":{"media":[{"id":1}]},"topRated":{"media":[{"id":2}]}}}"#)])
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
        let transport = ExploreStudioTransport([.json(json), .json(json)])
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
        let transport = ExploreStudioTransport([.json(#"{"data":{"Studio":null}}"#)])
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        do { _ = try await api.studioAnime(id: 0); XCTFail("Invalid studio accepted") } catch {}
        let invalidRequests = await transport.recorded()
        XCTAssertTrue(invalidRequests.isEmpty)
        do { _ = try await api.studioAnime(id: 44); XCTFail("Missing studio accepted") } catch {}
    }
}

private actor ExploreStudioTransport: HTTPTransport {
    struct Response: Sendable {
        let data: Data; let status: Int; let headers: [String: String]
        static func json(_ value: String, status: Int = 200, headers: [String: String] = [:]) -> Self {
            Self(data: Data(value.utf8), status: status, headers: headers)
        }
    }
    private var queue: [Response]
    private var requests: [URLRequest] = []
    init(_ queue: [Response]) { self.queue = queue }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !queue.isEmpty else { throw ServiceError.message("Unexpected extra request") }
        let next = queue.removeFirst()
        return (next.data, HTTPURLResponse(url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: next.headers)!)
    }
    func recorded() -> [URLRequest] { requests }
}
