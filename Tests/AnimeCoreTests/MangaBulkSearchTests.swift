import XCTest
@testable import AnimeCore

final class MangaBulkSearchTests: XCTestCase {
    private func source(_ id: String, extensionID: String = "owned") -> MangaSourceReference {
        .init(extensionID: extensionID, sourceID: id, name: id, language: "en", homeURL: "https://owned.example")
    }
    private func installed(_ id: String, adult: Bool = false, enabled: Bool = true) throws -> InstalledMangaExtension {
        let package = "eu.kanade.tachiyomi.extension.en." + id
        let source: [String: Any] = ["index": 0, "id": id, "name": id, "language": "en", "homeURL": "https://owned.example", "supportsLatest": true]
        let descriptor: [String: Any] = ["name": id, "packageName": package, "apiVersion": "1.6", "versionCode": 1, "versionName": "1.6.0", "apkURL": "https://owned.example/source.apk", "contentWarning": adult ? 2 : 0, "sha256": String(repeating: "a", count: 64), "sources": [source]]
        let inspection: [String: Any] = ["packageName": package, "versionName": "1.6.0", "sources": [source]]
        return try .init(descriptor: JSONDecoder().decode(MangaExtensionDescriptor.self, from: JSONSerialization.data(withJSONObject: descriptor)),
            inspection: JSONDecoder().decode(MangaExtensionInspection.self, from: JSONSerialization.data(withJSONObject: inspection)), enabled: enabled)
    }
    func testAllEnabledSourcesHaveNoFiveSourceLimitAndRespectContentPreferences() throws {
        let safe = try (0..<8).map { try installed("safe\($0)") }
        let adult = try installed("adult", adult: true), disabled = try installed("disabled", enabled: false)
        let values = safe + [adult, disabled, safe[0]]
        let sources = MangaBulkSearch.sources(in: values, allowMature: false, pinned: [], pinnedOnly: false)
        XCTAssertEqual(sources.count, 8)
        XCTAssertEqual(Set(sources.map(\.id)).count, 8)
        XCTAssertEqual(MangaBulkSearch.sources(in: values, allowMature: true, pinned: [], pinnedOnly: false).count, 9)
    }
    func testPinnedFilterUsesCompositeIDsAndDoesNotFallBackToAllWhenEmpty() throws {
        let a = try installed("a"), b = try installed("b"), hidden = try installed("hidden", adult: true)
        let ref = MangaSourceReference(installation: b, source: b.sources[0])
        let hiddenRef = MangaSourceReference(installation: hidden, source: hidden.sources[0])
        XCTAssertEqual(MangaBulkSearch.sources(in: [a, b, hidden], allowMature: false, pinned: [ref.id, hiddenRef.id, "removed"], pinnedOnly: true), [ref])
        XCTAssertTrue(MangaBulkSearch.sources(in: [a, b], allowMature: false, pinned: [b.sources[0].id], pinnedOnly: true).isEmpty)
        XCTAssertEqual(MangaBulkSearch.sources(in: [a, b], allowMature: false, pinned: [ref.id], pinnedOnly: false).first, ref)
        XCTAssertTrue(DeviceSyncPreferences.keys.contains(MangaBulkSearch.pinnedOnlyKey))
    }
    @MainActor
    func testBulkSearchStreamsFastResultsAndContinuesPastFailureWithTwoRequestsAtATime() async {
        var active = 0, maximum = 0
        var finished: [String] = []
        var failed: [String] = []
        var started: [String] = []
        let sources = (0..<8).map { source(String($0)) }
        await MangaBulkSearch.run(query: "  Harbor  ", sources: sources + [sources[0]], search: { source, query in
            XCTAssertEqual(query, "Harbor")
            active += 1; maximum = max(maximum, active)
            defer { active -= 1 }
            try await Task.sleep(for: .milliseconds(source.sourceID == "0" ? 100 : 5))
            if source.sourceID == "2" { throw URLError(.notConnectedToInternet) }
            return .init(mangas: [.init(url: "/one", title: "One"), .init(url: "", title: "Invalid"), .init(url: "/one", title: "Duplicate")], hasNext: true)
        }) { event in
            switch event {
            case .started(let source): started.append(source.id)
            case .failed(let source, _): failed.append(source.sourceID)
            case .results(let source, let page):
                finished.append(source.sourceID)
                XCTAssertEqual(page.mangas.map(\.url), ["/one"])
                XCTAssertTrue(page.hasNext)
            }
        }
        XCTAssertEqual(maximum, 2)
        XCTAssertEqual(active, 0)
        XCTAssertEqual(started.count, 8)
        XCTAssertEqual(Set(started).count, 8)
        XCTAssertEqual(finished.count, 7)
        XCTAssertEqual(failed, ["2"])
        XCTAssertEqual(finished.first, "1", "A slow first source must not hold back other results")
    }
    @MainActor
    func testCancellationDoesNotPublishLatePagesOrStartQueuedSources() async {
        var starts = 0, completions = 0
        let sources = (0..<8).map { source(String($0)) }
        let task = Task {
            await MangaBulkSearch.run(query: "Harbor", sources: sources, search: { _, _ in
                starts += 1
                // Simulate a source that ignores cancellation and returns late.
                while !Task.isCancelled { await Task.yield() }
                return .init(mangas: [.init(url: "/late", title: "Late")], hasNext: false)
            }) { event in
                if case .started = event {} else { completions += 1 }
            }
        }
        for _ in 0..<10000 {
            if starts == 2 { break }
            await Task.yield()
        }
        XCTAssertEqual(starts, 2)
        task.cancel()
        await task.value
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(completions, 0)
    }
    @MainActor
    func testEmptyQueryMakesNoSourceRequests() async {
        await MangaBulkSearch.run(query: " \n ", sources: [source("one")], search: { _, _ in
            XCTFail("Empty query must not be sent")
            return .init(mangas: [], hasNext: false)
        }) { _ in XCTFail("An empty query has no search state") }
    }
}
