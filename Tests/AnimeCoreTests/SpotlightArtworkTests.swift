import XCTest
@testable import AnimeCore

final class SpotlightArtworkTests: XCTestCase {
    func testOnlyTheReportedBakedInPosterLogoUsesItsVerifiedTextlessArtwork() throws {
        let clean = "https://image.tmdb.org/t/p/original/gyWFWI2ks2OFaWYDS5hnZK4iVLG.jpg"
        for size in ["small", "medium", "large"] {
            let url = try XCTUnwrap(URL(string: "https://images.metahub.space/poster/\(size)/tt15483602/img"))
            XCTAssertEqual(SeriesArtworkQuality.spotlight(url)?.absoluteString, clean)
        }
        XCTAssertEqual(SeriesArtworkQuality.spotlight(URL(string: "https://image.tmdb.org/t/p/original/yZ3VZVc7iyF7KtIjERBGEedVXqA.jpg"))?.absoluteString, clean)
        for raw in ["https://images.metahub.space/logo/medium/tt15483602/img",
                    "https://images.metahub.space/background/large/tt15483602/img",
                    "https://images.metahub.space/poster/large/tt15483602/img?signature=public-test",
                    "https://images.metahub.space.example/poster/large/tt15483602/img",
                    "https://image.tmdb.org/t/p/original/another-poster.jpg"] {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertEqual(SeriesArtworkQuality.spotlight(url), url)
        }
    }
    func testEnlargedMetahubArtLeavesLogosSignedRequestsAndOtherHostsIntact() throws {
        for kind in ["poster", "background"] {
            let source = URL(string: "https://images.metahub.space/\(kind)/small/tt7441658/img")!
            XCTAssertEqual(SeriesArtworkQuality.spotlight(source)?.path, "/\(kind)/large/tt7441658/img")
        }
        for raw in ["https://images.metahub.space/logo/medium/tt7441658/img",
                    "https://images.metahub.space/poster/medium/tt7441658/img?signature=public-test",
                    "https://images.metahub.space.example/poster/medium/tt7441658/img",
                    "https://artworks.thetvdb.com/posters/original.jpg"] {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertEqual(SeriesArtworkQuality.spotlight(url), url)
        }
    }
    func testSpotlightPrefersTextlessArtAndDoesNotUseAnUnverifiedPosterBehindTheLogo() throws {
        let anime = try JSONDecoder().decode(Anime.self, from: Data(#"{"id":97940,"bannerImage":"https://anilist.co/banner.jpg","coverImage":{"extraLarge":"https://anilist.co/cover.jpg"}}"#.utf8))
        let poster = URL(string: "https://art.example/poster.jpg")!, backdrop = URL(string: "https://art.example/backdrop.jpg")!
        let defaults = SeriesArtworkPreferences()
        let art = SeriesArtwork(backdrop: backdrop, poster: poster)
        XCTAssertEqual(defaults.spotlightURL(artwork: art, anime: anime, landscape: false), backdrop)
        XCTAssertEqual(defaults.spotlightURL(artwork: art, anime: anime, landscape: true), backdrop)
        let cleanPortrait = URL(string: "https://image.tmdb.org/t/p/original/clean-portrait.jpg")!
        let cleanLandscape = URL(string: "https://image.tmdb.org/t/p/original/clean-landscape.jpg")!
        let clean = SeriesArtwork(poster: poster, spotlightPoster: cleanPortrait, spotlightBackdrop: cleanLandscape)
        XCTAssertEqual(defaults.spotlightURL(artwork: clean, anime: anime, landscape: false), cleanPortrait)
        XCTAssertEqual(defaults.spotlightURL(artwork: clean, anime: anime, landscape: true), cleanLandscape)
        XCTAssertNil(defaults.spotlightURL(artwork: SeriesArtwork(poster: poster), anime: anime, landscape: false))
        XCTAssertEqual(defaults.posterURL(artwork: clean, anime: anime), poster, "Series posters must remain unchanged")
        XCTAssertNil(defaults.spotlightURL(artwork: SeriesArtwork(), anime: anime, landscape: false))
        XCTAssertEqual(SeriesArtworkPreferences(poster: true).spotlightURL(artwork: SeriesArtwork(), anime: anime, landscape: false), anime.coverURL)
        XCTAssertEqual(SeriesArtworkPreferences(banner: true).spotlightURL(artwork: SeriesArtwork(), anime: anime, landscape: true)?.absoluteString, anime.bannerImage)
    }
    func testMappedPostersCannotSilentlyReintroduceDisabledAniListCovers() throws {
        let anime = try JSONDecoder().decode(Anime.self, from: Data(#"{"id":97940}"#.utf8))
        let json = #"{"mappings":{"anilist_id":97940},"images":[{"coverType":"Poster","url":"https://s4.anilist.co/cover.jpg"},{"coverType":"Poster","url":"https://artworks.thetvdb.com/original.jpg"}]}"#
        XCTAssertEqual(try SeriesArtworkDecoding.aniZip(Data(json.utf8), anime: anime).poster?.host, "artworks.thetvdb.com")
    }
}
