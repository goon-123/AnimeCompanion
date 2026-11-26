import XCTest
@testable import AnimeCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MangaSearchProgressTests: XCTestCase {
    private func title(source: String = "owned") -> MangaTitleReference {
        .init(source: .init(extensionID: source, sourceID: "en", name: "Owned", language: "en", homeURL: "https://owned.example"), manga: .init(url: "/story", title: "Owned story"))
    }
    private func link(account: String = "account-one", source: String = "owned", date: Double = 100) -> MangaSourceLink {
        .init(library: .init(accountID: account, seriesID: 81, title: "Owned story", searchTitles: ["Owned story"]), title: title(source: source), updatedAt: Date(timeIntervalSince1970: date))
    }
    func testAutomaticNumbersRequireClearWholeChaptersAndRejectMismatches() {
        for name in ["Chapter 18", "Ch. 18: Story", "Chapter #18"] {
            XCTAssertEqual(MangaProgressPolicy.automaticChapter(.init(url: "/18", name: name)), 18)
        }
        XCTAssertEqual(MangaProgressPolicy.automaticChapter(.init(url: "/18", name: "A new beginning", chapterNumber: 18)), 18)
        for chapter in [SourceMangaChapter(url: "/x", name: "Extra 18", chapterNumber: 18),
                        .init(url: "/x", name: "Chapter 18.5", chapterNumber: 18.5),
                        .init(url: "/x", name: "Chapter 17", chapterNumber: 18),
                        .init(url: "/x", name: "Unnumbered chapter"),
                        .init(url: "/x", name: "Volume 18", chapterNumber: 18),
                        .init(url: "/x", name: "Chapter 18 Part 1", chapterNumber: 18),
                        .init(url: "/x", name: "Chapter 10001"),
                        .init(url: "/x", name: "Chapter 0")] {
            XCTAssertNil(MangaProgressPolicy.automaticChapter(chapter))
        }
    }
    func testProgressOnlyMovesForwardAndAcceptsManualFractionalChapters() throws {
        XCTAssertTrue(MangaProgressPolicy.shouldAdvance(current: 17, proposed: 18))
        XCTAssertTrue(MangaProgressPolicy.shouldAdvance(current: nil, proposed: 1))
        XCTAssertFalse(MangaProgressPolicy.shouldAdvance(current: 20, proposed: 18))
        XCTAssertFalse(MangaProgressPolicy.shouldAdvance(current: 18, proposed: 18))
        XCTAssertFalse(MangaProgressPolicy.shouldAdvance(current: 0, proposed: .infinity))
        let patch = try MangaBakaProgressUpdate(chapter: 18.5)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(patch)) as? [String: Double])
        XCTAssertEqual(body, ["progress_chapter": 18.5])
        for invalid in [0.0, -1, .nan, .infinity, 10001] { XCTAssertThrowsError(try MangaBakaProgressUpdate(chapter: invalid)) }
    }
    func testConsentIsScopedToAccountSourceAndLinkRevisionAndSurvivesRelaunch() throws {
        let original = link()
        let restored = try JSONDecoder().decode(MangaSourceLink.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(MangaProgressPolicy.consentKey(for: original), MangaProgressPolicy.consentKey(for: restored))
        for different in [link(account: "account-two"), link(source: "other"), link(date: 101)] {
            XCTAssertNotEqual(MangaProgressPolicy.consentKey(for: original), MangaProgressPolicy.consentKey(for: different))
        }
        XCTAssertFalse(DeviceSyncPreferences.keys.contains(MangaProgressPolicy.consentKey(for: original)))
        XCTAssertTrue(DeviceSyncPreferences.keys.contains(MangaSearchPreferences.storageKey))
    }
    func testSourceMatchingNeverChoosesAnotherAccountsLink() {
        let one = link(), two = link(account: "account-two", date: 200)
        XCTAssertEqual(MangaProgressPolicy.link(for: title().id, accountID: "account-one", links: [one, two]), one)
        XCTAssertNil(MangaProgressPolicy.link(for: title().id, accountID: nil, links: [one, two]))
        XCTAssertNil(MangaProgressPolicy.link(for: title(source: "other").id, accountID: "account-one", links: [one, two]))
    }
    func testSearchSelectionHasAnExplicitBoundAndRoundTripsInSavedOrder() {
        let selected = MangaSearchPreferences(sourceIDs: ["", "a", "a", "b", "c", "d", "e", "f"])
        XCTAssertEqual(selected.sourceIDs, ["a", "b", "c", "d", "e"])
        XCTAssertEqual(MangaSearchPreferences(saved: selected.saved), selected)
        XCTAssertTrue(MangaSearchPreferences(saved: "{bad").sourceIDs.isEmpty)
        XCTAssertTrue(MangaSearchPreferences(saved: nil).sourceIDs.isEmpty)
        XCTAssertTrue(StorySearchScope.sources.needsInstalledSources)
        XCTAssertFalse(StorySearchScope.sources.needsAnime || StorySearchScope.sources.needsReading)
        XCTAssertFalse(StorySearchScope.anime.needsInstalledSources || StorySearchScope.novels.needsInstalledSources)
    }
    func testSearchSelectionExcludesDisabledMissingAndHiddenAdultSources() throws {
        func installed(_ name: String, adult: Bool = false, enabled: Bool = true) throws -> InstalledMangaExtension {
            let package = "eu.kanade.tachiyomi.extension.en." + name
            let source: [String: Any] = ["index": 0, "id": name, "name": name, "language": "en", "homeURL": "https://owned.example", "supportsLatest": true]
            let descriptor: [String: Any] = ["name": name, "packageName": package, "apiVersion": "1.6", "versionCode": 1, "versionName": "1.6.0", "apkURL": "https://owned.example/source.apk", "contentWarning": adult ? 2 : 0, "sha256": String(repeating: "a", count: 64), "sources": [source]]
            let inspection: [String: Any] = ["packageName": package, "versionName": "1.6.0", "sources": [source]]
            return try .init(descriptor: JSONDecoder().decode(MangaExtensionDescriptor.self, from: JSONSerialization.data(withJSONObject: descriptor)),
                inspection: JSONDecoder().decode(MangaExtensionInspection.self, from: JSONSerialization.data(withJSONObject: inspection)), enabled: enabled)
        }
        let safe = try installed("safe"), adult = try installed("adult", adult: true), disabled = try installed("disabled", enabled: false)
        func reference(_ value: InstalledMangaExtension) -> MangaSourceReference { .init(installation: value, source: value.sources[0]) }
        let prefs = MangaSearchPreferences(sourceIDs: [reference(disabled).id, reference(adult).id, "removed", reference(safe).id])
        XCTAssertEqual(prefs.sources(in: [safe, adult, disabled], allowMature: false).map(\.id), [reference(safe).id])
        XCTAssertEqual(prefs.sources(in: [safe, adult, disabled], allowMature: true).map(\.id), [reference(adult).id, reference(safe).id])
    }
    func testAutomaticLinkRequiresExactlyOneExplicitlyEnabledTarget() {
        let one = link(), otherAccount = link(account: "account-two")
        let two = MangaSourceLink(library: .init(accountID: "account-one", seriesID: 82, title: "Other edition", searchTitles: []), title: title(), updatedAt: Date(timeIntervalSince1970: 200))
        let enabled = Set([one, otherAccount].map(MangaProgressPolicy.consentKey))
        XCTAssertEqual(MangaProgressPolicy.automaticLink(for: title().id, accountID: "account-one", links: [one, two, otherAccount], enabledKeys: enabled), one)
        XCTAssertNil(MangaProgressPolicy.automaticLink(for: title().id, accountID: "account-one", links: [one, two], enabledKeys: Set([one, two].map(MangaProgressPolicy.consentKey))))
        XCTAssertNil(MangaProgressPolicy.automaticLink(for: title().id, accountID: "account-one", links: [one, two], enabledKeys: []))
    }
    func testRevokedAuthorizationStopsProgressAtTheNetworkBoundary() async throws {
        let transport = ProgressTransport()
        let client = MangaBakaClient(transport: transport, directory: nil, minimumRequestInterval: 0)
        do {
            try await client.updateChapterProgress(id: 81, chapter: 18, credential: .init(kind: .apiKey, secret: "owned-test-key"), isAllowed: { false })
            XCTFail("Revoked progress authorization must cancel before transport")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let count = await transport.requests.count
        XCTAssertEqual(count, 0)
    }
    func testProgressHTTPPatchContainsOnlyChapterAndKeepsCredentialAtCorrectHost() async throws {
        let transport = ProgressTransport()
        let client = MangaBakaClient(transport: transport, directory: nil, minimumRequestInterval: 0)
        try await client.updateChapterProgress(id: 81, chapter: 18, credential: .init(kind: .apiKey, secret: "owned-test-key"))
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.absoluteString, "https://api.mangabaka.org/v1/my/library/81")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "owned-test-key")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Double], ["progress_chapter": 18])
        do { try await client.updateChapterProgress(id: 81, chapter: -1, credential: .init(kind: .apiKey, secret: "owned-test-key")); XCTFail("Invalid progress must not be sent") } catch {}
        let finalCount = await transport.requests.count
        XCTAssertEqual(finalCount, 1)
    }
}

private actor ProgressTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return (Data(#"{"data":true}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
