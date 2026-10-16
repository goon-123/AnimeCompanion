import XCTest
@testable import AnimeCore

final class TorrentSortTests: XCTestCase {
    private func torrent(_ name: String, seeders: Int? = nil, hash: String? = nil) throws -> SeanimeTorrent {
        var fields: [String: Any] = ["name": name]
        if let seeders { fields["seeders"] = seeders }
        if let hash { fields["infoHash"] = hash }
        return try JSONDecoder().decode(SeanimeTorrent.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    private func sorted(_ values: [SeanimeTorrent], by sort: TorrentSort = .seeders) -> [SeanimeTorrent] {
        sort.sorted(values, torrent: { $0 }, audio: { StreamAudioInfo(texts: [$0.name]) })
    }

    func testHighestSeedersWithinEnglishAndOtherAudioGroups() throws {
        let values = try [torrent("Japanese · Audio: ja", seeders: 1000),
                          torrent("English Softsubs", seeders: 5000),
                          torrent("Low · Audio: en", seeders: 2),
                          torrent("High · English dub", seeders: 250),
                          torrent("Dual · Audio: en / ja", seeders: 150),
                          torrent("Unlisted", seeders: 10000)]
        XCTAssertEqual(sorted(values).map(\.name), [values[3], values[4], values[2], values[5], values[1], values[0]].map(\.name))
    }

    func testMissingAndInvalidCountsFollowKnownZeroWithoutOverflow() throws {
        let values = try [torrent("Missing EN"), torrent("Invalid EN", seeders: -3), torrent("Zero EN", seeders: 0),
                          torrent("Largest EN", seeders: Int.max), torrent("One EN", seeders: 1), torrent("Extreme EN", seeders: Int.min)]
        XCTAssertEqual(sorted(values).map(\.name), ["Largest EN", "One EN", "Zero EN", "Missing EN", "Invalid EN", "Extreme EN"])
        XCTAssertEqual(values[0].seederSummary, "Seeders unlisted")
        XCTAssertEqual(values[1].seederSummary, "Seeders unlisted")
        XCTAssertEqual(values[2].seederSummary, "0 seeders")
    }

    func testEqualSeederCountsKeepProviderOrderAcrossRepeatedSorts() throws {
        let values = try [torrent("Zulu EN", seeders: 20), torrent("Alpha EN", seeders: 20),
                          torrent("Zulu JA", seeders: 20), torrent("Alpha JA", seeders: 20)]
        XCTAssertEqual(sorted(sorted(values)).map(\.name), values.map(\.name))
    }

    func testReleaseNameUsesNaturalNumbersAndStillPrioritizesEnglish() throws {
        let values = try [torrent("Episode 1 JA", seeders: 5000), torrent("Episode 10 EN", seeders: 10),
                          torrent("Episode 2 EN", seeders: 1), torrent("Episode 3 JA", seeders: 6000)]
        XCTAssertEqual(sorted(values, by: .name).map(\.name), ["Episode 2 EN", "Episode 10 EN", "Episode 1 JA", "Episode 3 JA"])
    }

    func testProviderOrderKeepsOriginalOrderWithinEachAudioGroup() throws {
        let values = try [torrent("First JA", seeders: 100), torrent("First EN", seeders: 1),
                          torrent("Second EN", seeders: 500), torrent("Unlisted", seeders: 1000), torrent("Second JA", seeders: 10)]
        XCTAssertEqual(sorted(values, by: .provider).map(\.name), ["First EN", "Second EN", "First JA", "Unlisted", "Second JA"])
    }

    func testReorderingRetainsExactProviderAndTorrentIdentityIncludingSharedReleases() throws {
        let shared = try torrent("Shared EN", seeders: 10, hash: String(repeating: "a", count: 40))
        let popular = try torrent("Popular EN", seeders: 100, hash: String(repeating: "b", count: 40))
        let values = [(provider: "Provider 1", torrent: shared), (provider: "Provider 2", torrent: shared),
                      (provider: "Provider 3", torrent: popular)]
        let ordered = TorrentSort.seeders.sorted(values, torrent: { $0.torrent }, audio: { StreamAudioInfo(texts: [$0.torrent.name]) })
        XCTAssertEqual(ordered.map(\.provider), ["Provider 3", "Provider 1", "Provider 2"])
        XCTAssertEqual(ordered.map { $0.torrent.infoHash }, [popular.infoHash, shared.infoHash, shared.infoHash])
        XCTAssertEqual(ordered.map { $0.torrent.id }, [popular.id, shared.id, shared.id])
    }

    func testEmptyAndFilteredResultsRemainValidForEveryOrder() throws {
        let values = try [torrent("Japanese JA", seeders: 5000), torrent("Low EN", seeders: 1), torrent("High EN", seeders: 100)]
        for sort in TorrentSort.allCases {
            XCTAssertTrue(sorted([], by: sort).isEmpty)
            let onlyEnglish = values.filter { StreamAudioInfo(texts: [$0.name]).english }
            let result = sorted(onlyEnglish, by: sort)
            XCTAssertEqual(Set(result.map(\.id)), Set(onlyEnglish.map(\.id)))
            XCTAssertTrue(result.allSatisfy { StreamAudioInfo(texts: [$0.name]).english })
        }
    }
}
