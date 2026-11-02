import XCTest
@testable import AnimeCore

final class SeanimeCompatibilityTests: XCTestCase {
    func testEmptyHashesDoNotCollapseDifferentTorrentsAndNumericStringsDecode() throws {
        let raw = Data(#"[{"name":"First release","infoHash":"","magnetLink":" ","link":"https://provider.example/1","seeders":"300","size":"1073741824","episodeNumber":"4"},{"name":"Second release","infoHash":"","magnetLink":"","link":"https://provider.example/2","seeders":30},{"name":"Unknown counts","seeders":"unlisted","size":"NaN"}]"#.utf8)
        let rows = try JSONDecoder().decode([SeanimeTorrent].self, from: raw)
        XCTAssertEqual(Set(rows.map(\.id)).count, 3)
        XCTAssertNil(rows[0].infoHash); XCTAssertNil(rows[0].magnetLink)
        XCTAssertEqual(rows[0].seeders, 300); XCTAssertEqual(rows[0].size, 1_073_741_824); XCTAssertEqual(rows[0].episodeNumber, 4)
        XCTAssertNil(rows[2].seeders); XCTAssertNil(rows[2].size)
    }
    func testBenignGETHeadersAreAcceptedAndSensitiveOrInjectedHeadersAreRejected() throws {
        let headers = try SeanimeRequestHeaders.validated(["Accept": "application/json", "User-Agent": "Owned fixture", "Referer": "https://provider.example/"])
        XCTAssertEqual(headers["accept"], "application/json")
        for invalid in [["Authorization": "private"], ["Cookie": "private"], ["Host": "other.example"], ["Accept": "x\r\nOther: y"], ["Origin": "http://127.0.0.1"]] {
            XCTAssertThrowsError(try SeanimeRequestHeaders.validated(invalid))
        }
    }
    func testReviewedUpdatesKeepProviderIdentityConfigurationAndDisabledStateWithoutDuplicatingSource() throws {
        let manifest = try JSONDecoder().decode(SeanimeManifest.self, from: Data(#"{"id":"owned","name":"Owned fixture","version":"1","type":"anime-torrent-provider","language":"typescript","payload":"class Provider {}","userConfig":{"requiresConfig":true,"fields":[{"name":"feed","type":"text","default":"default"}]}}"#.utf8))
        let old = SeanimeInstallation(manifestURL: URL(string: "https://provider.example/manifest.json")!, manifest: manifest,
            source: "old reviewed code", enabled: false, preferences: ["feed": "configured", "obsolete": "old"], allowedHosts: ["provider.example"], adult: false)
        let candidate = SeanimeInstallation(manifestURL: old.manifestURL, manifest: manifest, source: "new reviewed code",
            preferences: ["feed": "default"], allowedHosts: ["reviewed.example"], adult: false)
        let updated = old.replacingReviewedCode(with: candidate)
        XCTAssertEqual(updated.id, old.id); XCTAssertFalse(updated.enabled)
        XCTAssertEqual(updated.preferences, ["feed": "configured"])
        XCTAssertEqual(updated.allowedHosts, ["reviewed.example"]); XCTAssertFalse(updated.needsConfiguration)
        XCTAssertNil(updated.manifest.payload); XCTAssertEqual(updated.source, "new reviewed code")
        let roundtrip = try JSONDecoder().decode(SeanimeInstallation.self, from: JSONEncoder().encode(updated))
        XCTAssertEqual(roundtrip.id, old.id); XCTAssertEqual(roundtrip.source, "new reviewed code")
        XCTAssertEqual(roundtrip.preferences["feed"], "configured")
    }
    func testWidgetDesignsMigrateIndependentlyFromCountsVisibilityAndShortcuts() {
        var value = HomePreferences(saved: #"{"version":3,"order":["nextEpisode","reading"],"hidden":["reading"],"shortcuts":["community","airing",""]}"#)
        XCTAssertEqual(value.layout(for: .nextEpisode), .banner)
        value.setLayout(.compact, for: .nextEpisode); value.setLayout(.poster, for: .seasonCountdown)
        value.setSize(.expanded, for: .reading)
        let reopened = HomePreferences(saved: value.saved)
        XCTAssertEqual(reopened.layout(for: .nextEpisode), .compact)
        XCTAssertEqual(reopened.layout(for: .seasonCountdown), .poster)
        XCTAssertEqual(reopened.size(for: .reading), .expanded); XCTAssertTrue(reopened.hidden.contains(.reading))
        XCTAssertEqual(reopened.shortcuts, [.community, .airing, nil]); XCTAssertEqual(reopened, value)
        value.setLayout(.compact, for: .greeting)
        XCTAssertEqual(value.layout(for: .greeting), .banner)
    }
}
