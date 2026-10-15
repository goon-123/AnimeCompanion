import XCTest
@testable import AnimeCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MultipleAddonTests: XCTestCase {
    private func addon(_ path: String, name: String = "Provider") throws -> InstalledAddon {
        let manifest = try JSONDecoder().decode(AddonManifest.self, from: Data("{\"id\":\"same.manifest\",\"name\":\"\(name)\",\"types\":[\"series\",\"movie\"],\"resources\":[\"stream\"],\"idPrefixes\":[\"anilist:\"]}".utf8))
        return InstalledAddon(endpoint: try AddonEndpoint("https://addon.example/\(path)"), manifest: manifest)
    }
    private func anime() throws -> Anime { try JSONDecoder().decode(Anime.self, from: Data(#"{"id":1,"idMal":2,"episodes":12,"format":"TV"}"#.utf8)) }
    private func collection(_ count: Int = 2) throws -> AddonCollection {
        var result = AddonCollection()
        for index in 0..<count { result.install(try addon("p\(index)", name: "Provider \(index)")) }
        return result
    }
    func testDifferentConfigurationsOfSameManifestStayInstalled() throws {
        var saved = try collection()
        let first = saved.installations[0].id
        saved.install(try addon("p0/manifest.json", name: "Updated provider"))
        XCTAssertEqual(saved.installations.count, 2)
        XCTAssertEqual(saved.installations[0].id, first)
        XCTAssertEqual(saved.installations[0].addon.manifest.name, "Updated provider")
        XCTAssertEqual(saved.installations[1].addon.manifest.id, saved.installations[0].addon.manifest.id)
        XCTAssertNotEqual(saved.installations[0].addon.endpoint, saved.installations[1].addon.endpoint)
    }
    func testPerAddonDisableRemoveAndReinstallPreserveOtherEntries() throws {
        var saved = try collection()
        let first = saved.installations[0], second = saved.installations[1]
        saved.setEnabled(false, id: first.id)
        XCTAssertEqual(saved.enabled.map(\.id), [second.id])
        saved.install(first.addon)
        XCTAssertEqual(saved.enabled.count, 2)
        XCTAssertEqual(saved.installations[0].id, first.id)
        saved.remove(id: first.id)
        XCTAssertEqual(saved.installations.map(\.id), [second.id])
        saved.remove(id: UUID()); XCTAssertEqual(saved.installations.count, 1)
    }
    func testLegacySingleKeychainPayloadMigratesAndRoundTripsWithStableIdentity() throws {
        let legacy = try JSONEncoder().encode(addon("opaque%2Bconfig?token=a%26b"))
        var migrated = try JSONDecoder().decode(AddonCollection.self, from: legacy)
        XCTAssertEqual(migrated.installations.count, 1)
        let id = migrated.installations[0].id
        migrated.setEnabled(false, id: id)
        migrated.install(try addon("another"))
        let restored = try JSONDecoder().decode(AddonCollection.self, from: JSONEncoder().encode(migrated))
        XCTAssertEqual(restored.installations.map(\.id), migrated.installations.map(\.id))
        XCTAssertFalse(restored.installations[0].enabled)
        XCTAssertEqual(restored.installations[0].addon.endpoint, migrated.installations[0].addon.endpoint)
        XCTAssertTrue(restored.installations[0].addon.supportsAnime)
    }
    func testEmptyCollectionPersistsAndCorruptDuplicateIdentitiesAreRejected() throws {
        let empty = try JSONDecoder().decode(AddonCollection.self, from: JSONEncoder().encode(AddonCollection()))
        XCTAssertTrue(empty.installations.isEmpty)
        let entry = AddonInstallation(addon: try addon("p0"))
        let json = try JSONEncoder().encode(["installations": [entry, entry]])
        XCTAssertThrowsError(try JSONDecoder().decode(AddonCollection.self, from: json))
        XCTAssertThrowsError(try JSONDecoder().decode(AddonCollection.self, from: Data(#"{"installations":"invalid"}"#.utf8)))
    }
    func testProvidersPublishProgressivelyInInstalledOrderWithStableSourceIdentity() async throws {
        let saved = try collection(), transport = AddonGateTransport(), updates = AddonUpdates()
        let client = StremioClient(transport: transport)
        let media = try anime()
        let task = Task { try await client.streams(installations: saved.installations, anime: media, episode: 4) { await updates.append($0) } }
        try await multiWait { await transport.count == 2 }
        try await transport.finish("p1", body: #"{"streams":[{"name":"Beta en","url":"https://video.example/beta","description":"Audio: en"}]}"#)
        try await multiWait { await updates.latest?.sources.count == 1 }
        let latest = await updates.readLatest()
        let partial = try XCTUnwrap(latest)
        XCTAssertEqual(partial.pendingCount, 1)
        XCTAssertEqual(partial.sources.first?.stream.videoURL?.path, "/beta")
        let betaID = partial.sources[0].id
        try await transport.finish("p0", body: #"{"streams":[{"name":"Alpha ja","url":"https://video.example/alpha","description":"Audio: ja"}]}"#)
        let final = try await task.value
        XCTAssertEqual(final.sources.map { $0.stream.videoURL!.path }, ["/alpha", "/beta"])
        XCTAssertEqual(final.sources[1].id, betaID)
        XCTAssertEqual(final.pendingCount, 0)
        let ranked = StreamSourceSelection.indices(in: final.sources.map(\.stream), audio: .english)
        XCTAssertEqual(ranked, [1]); XCTAssertEqual(final.sources[ranked[0]].id, betaID)
        let requests = await transport.recorded()
        XCTAssertTrue(requests.allSatisfy { $0.url?.lastPathComponent == "anilist:1:4.json" })
    }
    func testOneFailedProviderKeepsItsOwnPreviousSourcesWhileSuccessfulEmptyProviderClearsItsOldOnes() async throws {
        let saved = try collection(), media = try anime()
        let initial = try await StremioClient(transport: AddonImmediateTransport()).streams(installations: saved.installations, anime: media, episode: 4)
        let next = try await StremioClient(transport: AddonImmediateTransport(failed: ["p0"], empty: ["p1"])).streams(
            installations: saved.installations, anime: media, episode: 4, previous: initial.sources)
        XCTAssertEqual(next.sources.map { $0.id.addonID }, [saved.installations[0].id])
        XCTAssertEqual(next.issues.count, 1); XCTAssertTrue(next.issues[0].usingSavedSources)
        XCTAssertEqual(next.issues[0].error, .unavailable); XCTAssertEqual(next.pendingCount, 0)
    }
    func testDisabledAndRemovedProvidersAreNotRequestedOrRestoredFromPreviousResults() async throws {
        var saved = try collection()
        let media = try anime(), client = StremioClient(transport: AddonImmediateTransport())
        let initial = try await client.streams(installations: saved.installations, anime: media, episode: 1)
        saved.setEnabled(false, id: saved.installations[0].id)
        let transport = AddonImmediateTransport()
        let next = try await StremioClient(transport: transport).streams(installations: saved.installations, anime: media, episode: 1, previous: initial.sources)
        let requested = await transport.providers; XCTAssertEqual(requested, ["p1"])
        XCTAssertEqual(next.sources.count, 1); XCTAssertEqual(next.sources[0].id.addonID, saved.installations[1].id)
        saved.remove(id: saved.installations[1].id)
        let disabled = try await client.streams(installations: saved.installations, anime: media, episode: 1, previous: initial.sources)
        XCTAssertTrue(disabled.sources.isEmpty); XCTAssertEqual(disabled.pendingCount, 0)
    }
    func testAllFailuresRemainDistinctFromConfirmedEmptyResultsWithoutLeakingURLs() async throws {
        let saved = try collection()
        let result = try await StremioClient(transport: AddonImmediateTransport(failed: ["p0", "p1"])).streams(installations: saved.installations, anime: anime(), episode: 1)
        XCTAssertTrue(result.sources.isEmpty); XCTAssertEqual(result.issues.count, 2)
        XCTAssertTrue(result.issues.allSatisfy { !$0.error.localizedDescription.contains("private-token") })
        XCTAssertEqual(result.pendingCount, 0)
        let empty = try await StremioClient(transport: AddonImmediateTransport(empty: ["p0", "p1"])).streams(installations: saved.installations, anime: anime(), episode: 1)
        XCTAssertTrue(empty.sources.isEmpty); XCTAssertTrue(empty.issues.isEmpty)
    }
    func testConcurrencyIsBoundedAndCancellationStopsQueuedProviderRequests() async throws {
        let saved = try collection(7), media = try anime(), transport = AddonGateTransport()
        let task = Task { try await StremioClient(transport: transport).streams(installations: saved.installations, anime: media, episode: 1) }
        try await multiWait { await transport.count == 4 }
        try await transport.finish("p0", body: #"{"streams":[]}"#)
        try await multiWait { await transport.count == 5 }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {}
        let count = await transport.count; XCTAssertEqual(count, 5)
        let cancelled = await transport.cancelled; XCTAssertEqual(cancelled, 4)
    }
    func testFailedProviderDoesNotBlockOtherProvidersFromReturningPlayableSources() async throws {
        let saved = try collection(), media = try anime(), transport = AddonGateTransport(), updates = AddonUpdates()
        let task = Task { try await StremioClient(transport: transport).streams(installations: saved.installations, anime: media, episode: 1) { await updates.append($0) } }
        try await multiWait { await transport.count == 2 }
        try await transport.finish("p0", body: "{}", status: 503)
        try await multiWait { await updates.latest?.issues.count == 1 }
        let latest = await updates.readLatest()
        let partial = try XCTUnwrap(latest); XCTAssertEqual(partial.pendingCount, 1)
        try await transport.finish("p1", body: #"{"streams":[{"url":"https://video.example/ok","description":"Audio: en"}]}"#)
        let result = try await task.value
        XCTAssertEqual(result.sources.count, 1); XCTAssertEqual(result.issues.count, 1)
        XCTAssertNil(result.sources[0].stream.unavailableReason)
    }
}

private actor AddonUpdates {
    private(set) var latest: AddonStreamSnapshot?
    func append(_ value: AddonStreamSnapshot) { latest = value }
    func readLatest() -> AddonStreamSnapshot? { latest }
}
private enum AddonTestError: Error { case timeout, missingRequest }
private func multiWait(_ condition: () async -> Bool) async throws {
    let deadline = Date().addingTimeInterval(3)
    while !(await condition()) {
        guard Date() < deadline else { throw AddonTestError.timeout }
        await Task.yield()
    }
}
private actor AddonImmediateTransport: HTTPTransport {
    let failed: Set<String>, empty: Set<String>
    private(set) var providers: [String] = []
    init(failed: Set<String> = [], empty: Set<String> = []) { self.failed = failed; self.empty = empty }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!, provider = request.url!.pathComponents[1]
        providers.append(provider)
        if failed.contains(provider) { throw URLError(.timedOut, userInfo: [NSURLErrorFailingURLStringErrorKey: "https://addon.example/private-token"]) }
        let body = empty.contains(provider) ? #"{"streams":[]}"# : "{\"streams\":[{\"name\":\"\(provider)\",\"url\":\"https://video.example/\(provider)\"}]}"
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
private actor AddonGateTransport: HTTPTransport {
    private var requests: [URLRequest] = []
    private var pending: [String: CheckedContinuation<(Data, HTTPURLResponse), Error>] = [:]
    private(set) var cancelled = 0
    var count: Int { requests.count }
    func recorded() -> [URLRequest] { requests }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let provider = request.url!.pathComponents[1]
        requests.append(request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); cancelled += 1 }
                else { pending[provider] = continuation }
            }
        } onCancel: { Task { await self.cancel(provider) } }
    }
    private func cancel(_ provider: String) {
        guard let continuation = pending.removeValue(forKey: provider) else { return }
        cancelled += 1; continuation.resume(throwing: CancellationError())
    }
    func finish(_ provider: String, body: String, status: Int = 200) throws {
        guard let continuation = pending.removeValue(forKey: provider), let request = requests.first(where: { $0.url?.pathComponents[1] == provider }) else { throw AddonTestError.missingRequest }
        continuation.resume(returning: (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!))
    }
}
