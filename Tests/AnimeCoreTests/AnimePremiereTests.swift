import XCTest
@testable import AnimeCore

final class AnimePremiereTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func anime(_ json: String) throws -> Anime { try JSONDecoder().decode(Anime.self, from: Data(json.utf8)) }
    func testUpcomingTotalsAndUnannouncedDatesDoNotImplyAvailableEpisodes() throws {
        let value = try anime(#"{"id":1,"status":"NOT_YET_RELEASED","episodes":24,"season":"WINTER","seasonYear":2099}"#)
        XCTAssertTrue(AnimePremiere.defersEpisodes(for: value, now: now))
        XCTAssertEqual(AnimePremiere.dateLabel(for: value), "Winter 2099")
        XCTAssertNil(AnimePremiere.exactAiring(for: value))
        let delayed = try anime(#"{"id":2,"status":"NOT_YET_RELEASED","startDate":{"year":2020,"month":1,"day":1}}"#)
        XCTAssertTrue(AnimePremiere.defersEpisodes(for: delayed, now: now), "A past planned date does not prove a delayed series aired")
    }
    func testExactEpisodeOneTimeResumesAtPremiereWithoutWaitingForStatusToCatchUp() throws {
        let value = try anime(#"{"id":1,"status":"NOT_YET_RELEASED","nextAiringEpisode":{"episode":1,"airingAt":1700000600}}"#)
        XCTAssertTrue(AnimePremiere.defersEpisodes(for: value, now: now))
        XCTAssertFalse(AnimePremiere.defersEpisodes(for: value, now: Date(timeIntervalSince1970: 1_700_000_600)))
    }
    func testPartialDatesRemainPartialAndAiredShowsAreNotBlocked() throws {
        let partial = try anime(#"{"id":1,"startDate":{"year":2099,"month":1}}"#)
        XCTAssertTrue(AnimePremiere.defersEpisodes(for: partial, now: now))
        XCTAssertTrue(AnimePremiere.dateLabel(for: partial).contains("2099"))
        for json in [#"{"id":2,"status":"FINISHED","startDate":{"year":2099,"month":1,"day":1}}"#,
                     #"{"id":3,"status":"RELEASING","nextAiringEpisode":{"episode":5,"airingAt":1700000600}}"#] {
            XCTAssertFalse(AnimePremiere.defersEpisodes(for: try anime(json), now: now))
        }
    }
    func testMissingAssetsFallbackDoesNotReplaceAvailableArtworkOrRunDuringResolution() throws {
        let value = try anime(#"{"id":1,"coverImage":{"extraLarge":"https://art.example/cover.jpg"}}"#)
        let banner = URL(string: "https://art.example/banner.jpg")!, logo = URL(string: "https://art.example/logo.png")!
        let complete = CinematicArtworkPresentation(artwork: .init(logo: logo, backdrop: banner), anime: value)
        XCTAssertEqual(complete.banner, banner); XCTAssertFalse(complete.blurredCover); XCTAssertFalse(complete.textTitle)
        let missing = CinematicArtworkPresentation(artwork: .init(), anime: value)
        XCTAssertEqual(missing.banner, value.coverURL); XCTAssertEqual(missing.poster, value.coverURL)
        XCTAssertTrue(missing.blurredCover); XCTAssertTrue(missing.textTitle)
        let partial = CinematicArtworkPresentation(artwork: .init(backdrop: banner), anime: value)
        XCTAssertEqual(partial.banner, banner); XCTAssertFalse(partial.blurredCover); XCTAssertTrue(partial.textTitle)
        let loading = CinematicArtworkPresentation(artwork: .init(), anime: value, resolved: false)
        XCTAssertNil(loading.banner); XCTAssertFalse(loading.blurredCover); XCTAssertFalse(loading.textTitle)
    }
}
