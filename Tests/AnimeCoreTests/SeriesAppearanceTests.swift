import XCTest
@testable import AnimeCore

final class SeriesAppearanceTests: XCTestCase {
    private var anime: Anime {
        get throws { try JSONDecoder().decode(Anime.self, from: Data(#"{"id":1,"bannerImage":"https://art.example/anilist-banner.jpg","coverImage":{"large":"https://art.example/anilist-poster.jpg"}}"#.utf8)) }
    }
    func testCinematicAndNoArtworkFallbackAreTheDefaults() throws {
        XCTAssertEqual(AnimeSeriesStyle(preference: ""), .cinematic)
        XCTAssertEqual(AnimeSeriesStyle(preference: "unknown"), .cinematic)
        let settings = SeriesArtworkPreferences()
        XCTAssertFalse(settings.logo); XCTAssertFalse(settings.banner); XCTAssertFalse(settings.poster)
        XCTAssertNil(settings.bannerURL(artwork: SeriesArtwork(), anime: try anime))
        XCTAssertNil(settings.posterURL(artwork: SeriesArtwork(), anime: try anime))
    }
    func testArtworkFallbackSwitchesAreIndependentAndRichArtworkWins() throws {
        let series = try anime
        let bannerOnly = SeriesArtworkPreferences(banner: true)
        XCTAssertEqual(bannerOnly.bannerURL(artwork: .init(), anime: series)?.lastPathComponent, "anilist-banner.jpg")
        XCTAssertNil(bannerOnly.posterURL(artwork: .init(), anime: series))
        let posterOnly = SeriesArtworkPreferences(poster: true)
        XCTAssertNil(posterOnly.bannerURL(artwork: .init(), anime: series))
        XCTAssertEqual(posterOnly.posterURL(artwork: .init(), anime: series)?.lastPathComponent, "anilist-poster.jpg")
        let rich = SeriesArtwork(backdrop: URL(string: "https://art.example/rich.jpg"), poster: URL(string: "https://art.example/poster.jpg"))
        XCTAssertEqual(SeriesArtworkPreferences().bannerURL(artwork: rich, anime: series), rich.backdrop)
        XCTAssertEqual(posterOnly.posterURL(artwork: rich, anime: series), rich.poster)
        XCTAssertNotEqual(AnimeSeriesStyle.storageKey, SeriesArtworkPreferences.bannerKey)
    }
    func testMoreInfoDefaultsAndSavedCustomizationStaySeparateFromClassic() {
        var info = SeriesMoreInfoPreferences()
        XCTAssertEqual(info.visible, [.information, .related, .news, .artwork, .links])
        let classic = SeriesDetailLayout(page: .anime).saved
        info.setVisible(.trailer, true)
        info.setVisible(.related, false)
        info.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        let reopened = SeriesMoreInfoPreferences(saved: info.saved)
        XCTAssertEqual(reopened, info)
        XCTAssertEqual(reopened.visible.first, .artwork)
        XCTAssertFalse(reopened.visible.contains(.related))
        XCTAssertEqual(SeriesDetailLayout(page: .anime, saved: classic), SeriesDetailLayout(page: .anime))
        XCTAssertNotEqual(SeriesMoreInfoPreferences.storageKey, SeriesDetailPage.anime.storageKey)
    }
    func testCorruptMoreInfoCannotIntroduceForeignOrDuplicateSections() {
        let settings = SeriesMoreInfoPreferences(saved: #"{"order":["news","chapters","news","information"],"hidden":["chapters"]}"#)
        XCTAssertEqual(Array(settings.order.prefix(2)), [.news, .information])
        XCTAssertEqual(Set(settings.order).count, SeriesMoreInfoPreferences.sections.count)
        XCTAssertFalse(settings.hidden.contains(.chapters))
        XCTAssertEqual(SeriesMoreInfoPreferences(saved: "{broken").visible, SeriesMoreInfoPreferences.defaults)
    }
    func testLibrarySizingUsesOneBoundedGridAndListPolicy() {
        XCTAssertEqual(LibraryArtworkSizing.gridMinimum(accessible: false), 140)
        XCTAssertGreaterThanOrEqual(LibraryArtworkSizing.gridMinimum(accessible: true), 190)
        XCTAssertEqual(LibraryArtworkSizing.gridMinimum(preferred: .nan, accessible: false), 140)
        XCTAssertLessThanOrEqual(LibraryArtworkSizing.listWidth(preferred: 128, availableWidth: 280, accessible: false), 280 * 0.38)
        XCTAssertEqual(LibraryArtworkSizing.listWidth(preferred: 128, availableWidth: 390, accessible: false), 128)
        XCTAssertLessThanOrEqual(LibraryArtworkSizing.listWidth(preferred: 128, availableWidth: 390, accessible: true), 100)
    }
}
