import XCTest
@testable import AnimeCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class PerformanceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)
    private let url = URL(string: "https://images.example.test/poster.jpg")!
    private let page = Data(#"{"data":{"Page":{"media":[{"id":1}]}}}"#.utf8)

    func testCacheEnforcesCountAndEvictsLeastRecentlyUsedFreshEntry() {
        var cache = BoundedCache<String, Int>(maximumCount: 2, maximumCost: 100)
        let expiry = now.addingTimeInterval(60)
        cache.insert(1, for: "a", cost: 1, expiresAt: expiry, now: now)
        cache.insert(2, for: "b", cost: 1, expiresAt: expiry, now: now)
        XCTAssertEqual(cache.value(for: "a", now: now), 1)
        cache.insert(3, for: "c", cost: 1, expiresAt: expiry, now: now)
        XCTAssertNil(cache.value(for: "b", now: now))
        XCTAssertEqual(cache.count, 2)
    }
    func testCacheEnforcesCostReplacementExpiryAndOversizeLimits() {
        var cache = BoundedCache<String, Int>(maximumCount: 80, maximumCost: 10)
        let expiry = now.addingTimeInterval(60)
        cache.insert(1, for: "a", cost: 6, expiresAt: expiry, now: now)
        cache.insert(2, for: "b", cost: 6, expiresAt: expiry, now: now)
        XCTAssertNil(cache.value(for: "a", now: now))
        cache.insert(3, for: "b", cost: 3, expiresAt: expiry, now: now)
        XCTAssertEqual(cache.totalCost, 3)
        cache.insert(4, for: "oversize", cost: Int.max, expiresAt: expiry, now: now)
        cache.insert(4, for: "expired", cost: 1, expiresAt: now, now: now)
        XCTAssertEqual(cache.count, 1)
        XCTAssertNil(cache.value(for: "b", now: expiry))
        XCTAssertEqual(cache.totalCost, 0)
    }
    func testCachePrunesExpiredEntriesAndCanClearSelectedVariants() {
        var cache = BoundedCache<String, Int>(maximumCount: 4, maximumCost: 100)
        cache.insert(1, for: "old", cost: 1, expiresAt: now.addingTimeInterval(1), now: now)
        cache.insert(2, for: "poster-128", cost: 2, expiresAt: now.addingTimeInterval(60), now: now.addingTimeInterval(2))
        cache.insert(3, for: "poster-512", cost: 3, expiresAt: now.addingTimeInterval(60), now: now)
        XCTAssertEqual(cache.count, 2)
        cache.remove { $0.hasPrefix("poster-") }
        XCTAssertEqual(cache.totalCost, 0)
        cache.removeAll(); XCTAssertEqual(cache.count, 0)
    }
    func testIdenticalRequestsShareWorkAndOneCancelledWaiterDoesNotCancelTheOther() async throws {
        let work = RequestCoalescer<String, Int>()
        let gate = ValueGate()
        let first = Task { try await work.value(for: "poster") { try await gate.run() } }
        try await eventually { await gate.starts == 1 }
        let second = Task { try await work.value(for: "poster") { try await gate.run() } }
        try await eventually { await work.waiterCount(for: "poster") == 2 }
        first.cancel()
        do { _ = try await first.value; XCTFail("Cancelled caller must return immediately") } catch is CancellationError {}
        let starts = await gate.starts; XCTAssertEqual(starts, 1)
        await gate.finish(42)
        let result = try await second.value; XCTAssertEqual(result, 42)
    }
    func testLastCancelledWaiterCancelsOperationAndLateCompletionCannotRemoveNewFlight() async throws {
        let work = RequestCoalescer<String, Int>()
        let old = ValueGate(), replacement = ValueGate()
        let first = Task { try await work.value(for: "key") { try await old.run() } }
        try await eventually { await old.starts == 1 }
        first.cancel()
        do { _ = try await first.value; XCTFail("Expected cancellation") } catch is CancellationError {}
        let next = Task { try await work.value(for: "key") { try await replacement.run() } }
        try await eventually { await replacement.starts == 1 }
        await old.finish(1) // Deliberately uncooperative operation completes late.
        try await eventually { await old.wasCancelled }
        let count = await work.waiterCount(for: "key"); XCTAssertEqual(count, 1)
        await replacement.finish(2)
        let result = try await next.value; XCTAssertEqual(result, 2)
    }
    func testFailedSharedOperationCanBeRetried() async throws {
        let work = RequestCoalescer<String, Int>()
        do { _ = try await work.value(for: "key") { throw ServiceError.http(500) }; XCTFail("Expected error") }
        catch { XCTAssertEqual(error as? ServiceError, .http(500)) }
        let result = try await work.value(for: "key") { 7 }
        XCTAssertEqual(result, 7)
    }
    func testAlreadyCancelledCallerDoesNotStartWork() async throws {
        let work = RequestCoalescer<String, Int>(), gate = ValueGate()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await work.value(for: "key") { try await gate.run() }
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {}
        let starts = await gate.starts; XCTAssertEqual(starts, 0)
    }
    func testConcurrentAniListQueriesShareTransportButDistinctVariablesDoNot() async throws {
        let transport = HeldTransport()
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        let tasks = (0..<12).map { _ in Task { try await api.search("same") } }
        try await eventually { await transport.count == 1 }
        try await transport.complete(0, data: page)
        for task in tasks { let result = try await task.value; XCTAssertEqual(result.media?.first?.id, 1) }
        let count = await transport.count; XCTAssertEqual(count, 1)
        let other = Task { try await api.search("different") }
        try await eventually { await transport.count == 2 }
        try await transport.complete(1, data: page)
        _ = try await other.value
    }
    func testAniListRefreshBypassesSavedResultAndFailureIsNotCached() async throws {
        let transport = HeldTransport()
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        let filters = DiscoveryFilters(category: .trending)
        let first = Task { try await api.browse(filters) }
        try await eventually { await transport.count == 1 }
        try await transport.complete(0, data: page); _ = try await first.value
        _ = try await api.browse(filters)
        let refresh = Task { try await api.browse(filters, refresh: true) }
        try await eventually { await transport.count == 2 }
        try await transport.complete(1, data: Data(#"{"errors":[{"message":"Unavailable"}]}"#.utf8))
        do { _ = try await refresh.value; XCTFail("Expected GraphQL failure") } catch {}
        let retry = Task { try await api.browse(filters, refresh: true) }
        try await eventually { await transport.count == 3 }
        try await transport.complete(2, data: Data(#"{"data":{"Page":{"media":[{"id":2}]}}}"#.utf8))
        _ = try await retry.value
        let saved = try await api.browse(filters); XCTAssertEqual(saved.media?.first?.id, 2)
    }
    func testAccountReadsAndMutationsAreNeitherSharedNorCached() async throws {
        let transport = HeldTransport()
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        let reads = (0..<2).map { _ in Task { try await api.viewer(token: "synthetic-token") } }
        try await eventually { await transport.count == 2 }
        for index in 0..<2 { try await transport.complete(index, data: Data(#"{"data":{"Viewer":{"id":1,"name":"Fixture"}}}"#.utf8)) }
        for task in reads { _ = try await task.value }
        for index in 2..<4 {
            let mutation = Task { try await api.save(mediaId: 1, entryId: nil, progress: 1, status: .watching, token: "synthetic-token") }
            try await eventually { await transport.count == index + 1 }
            try await transport.complete(index, data: Data(#"{"data":{"SaveMediaListEntry":{"id":1,"mediaId":1,"progress":1}}}"#.utf8))
            _ = try await mutation.value
        }
        let requests = await transport.recorded()
        XCTAssertEqual(requests.count, 4)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-token" })
    }
    func testAniListCacheHasHardEightyEntryLimitEvenWhenEveryResponseIsFresh() async throws {
        let transport = ImmediateTransport(data: page)
        let api = AniListClient(transport: transport, minimumRequestInterval: 0)
        for index in 0..<81 { _ = try await api.search("query-\(index)") }
        _ = try await api.search("query-80")
        var count = await transport.count; XCTAssertEqual(count, 81)
        _ = try await api.search("query-0")
        count = await transport.count; XCTAssertEqual(count, 82)
    }
    func testRateLimitStillDelaysOtherQueriesAndWaitingQueriesCanBeCancelled() async throws {
        let transport = HeldTransport()
        let api = AniListClient(transport: transport, minimumRequestInterval: 0.05)
        let first = Task { try await api.search("first") }
        try await eventually { await transport.count == 1 }
        let second = Task { try await api.search("second") }
        try await transport.complete(0, data: Data(), status: 429, headers: ["Retry-After": "1"])
        do { _ = try await first.value; XCTFail("Expected rate limit") }
        catch { XCTAssertEqual(error as? ServiceError, .rateLimited(1)) }
        try await Task.sleep(nanoseconds: 100_000_000)
        let count = await transport.count; XCTAssertEqual(count, 1)
        second.cancel()
        do { _ = try await second.value; XCTFail("Expected cancellation while throttled") } catch is CancellationError {}
    }
    func testArtworkSharesBytesAndRetryBypassesMemoryAndHTTPResponseCache() async throws {
        let transport = HeldTransport(), bytes = Data([1, 2, 3])
        let client = ArtworkDataClient(transport: transport)
        let tasks = (0..<8).map { _ in Task { try await client.image(at: url) } }
        try await eventually { await transport.count == 1 }
        try await transport.complete(0, data: bytes, headers: ["Content-Type": "image/jpeg", "Cache-Control": "max-age=120"])
        for task in tasks { let value = try await task.value; XCTAssertEqual(value.data, bytes) }
        _ = try await client.image(at: url)
        let retry = Task { try await client.image(at: url, refresh: true) }
        try await eventually { await transport.count == 2 }
        let requests = await transport.recorded()
        XCTAssertEqual(requests[0].cachePolicy, .useProtocolCachePolicy)
        XCTAssertEqual(requests[1].cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        try await transport.complete(1, data: Data([4]), headers: ["Content-Type": "image/png"])
        _ = try await retry.value
        let saved = try await client.image(at: url); XCTAssertEqual(saved.data, Data([4]))
    }
    func testArtworkOlderNormalCompletionCannotOverwriteRefresh() async throws {
        let transport = HeldTransport()
        let client = ArtworkDataClient(transport: transport)
        let old = Task { try await client.image(at: url) }
        try await eventually { await transport.count == 1 }
        let fresh = Task { try await client.image(at: url, refresh: true) }
        try await eventually { await transport.count == 2 }
        try await transport.complete(1, data: Data([2]))
        _ = try await fresh.value
        try await transport.complete(0, data: Data([1]))
        _ = try await old.value
        let saved = try await client.image(at: url); XCTAssertEqual(saved.data, Data([2]))
    }
    func testArtworkRejectsInvalidURLsWithoutNetworkAccess() async throws {
        let transport = ImmediateTransport(data: Data([1]))
        let client = ArtworkDataClient(transport: transport)
        for raw in ["file:///tmp/image.png", "https://user:password@example.test/a", "data:image/png;base64,AA=="] {
            do { _ = try await client.image(at: URL(string: raw)!); XCTFail("Expected URL rejection") }
            catch { XCTAssertEqual(error as? ArtworkError, .invalidURL) }
        }
        let count = await transport.count; XCTAssertEqual(count, 0)
    }
    func testArtworkRejectsBadResponsesAndAllowsLaterSuccess() async throws {
        let transport = HeldTransport()
        let client = ArtworkDataClient(transport: transport)
        let cases: [(Data, Int, [String: String])] = [
            (Data(), 200, [:]), (Data([1]), 503, [:]),
            (Data([1]), 200, ["Content-Type": "text/html"]), (Data(repeating: 1, count: 12_000_001), 200, [:])]
        for (index, response) in cases.enumerated() {
            let task = Task { try await client.image(at: url) }
            try await eventually { await transport.count == index + 1 }
            try await transport.complete(index, data: response.0, status: response.1, headers: response.2)
            do { _ = try await task.value; XCTFail("Expected response rejection") } catch {}
        }
        let task = Task { try await client.image(at: url) }
        try await eventually { await transport.count == 5 }
        try await transport.complete(4, data: Data([9]))
        let result = try await task.value; XCTAssertEqual(result.data, Data([9]))
    }
    func testArtworkMemoryClearPreventsInflightRepopulation() async throws {
        let transport = HeldTransport()
        let client = ArtworkDataClient(transport: transport)
        let first = Task { try await client.image(at: url) }
        try await eventually { await transport.count == 1 }
        await client.clearMemory()
        try await transport.complete(0, data: Data([1])); _ = try await first.value
        let next = Task { try await client.image(at: url) }
        try await eventually { await transport.count == 2 }
        try await transport.complete(1, data: Data([2])); _ = try await next.value
    }
    func testCancelledArtworkFetchCannotRepopulateCacheOrRemoveItsReplacement() async throws {
        let transport = HeldTransport() // Deliberately ignores cancellation until explicitly completed.
        let client = ArtworkDataClient(transport: transport)
        let old = Task { try await client.image(at: url) }
        try await eventually { await transport.count == 1 }
        old.cancel()
        do { _ = try await old.value; XCTFail("Expected cancellation") } catch is CancellationError {}
        let fresh = Task { try await client.image(at: url) }
        try await eventually { await transport.count == 2 }
        try await transport.complete(0, data: Data([1]))
        try await transport.complete(1, data: Data([2])); _ = try await fresh.value
        let saved = try await client.image(at: url); XCTAssertEqual(saved.data, Data([2]))
        let count = await transport.count; XCTAssertEqual(count, 2)
    }
    func testArtworkHonorsNoStoreAndDoesNotRetainDiscardedData() async throws {
        let transport = ImmediateTransport(data: Data([1]), headers: ["Cache-Control": "no-store"])
        let client = ArtworkDataClient(transport: transport)
        _ = try await client.image(at: url); _ = try await client.image(at: url)
        let count = await transport.count; XCTAssertEqual(count, 2)
        let cachedTransport = ImmediateTransport(data: Data([2]))
        let cached = ArtworkDataClient(transport: cachedTransport)
        _ = try await cached.image(at: url); await cached.discard(url); _ = try await cached.image(at: url)
        let afterDiscard = await cachedTransport.count; XCTAssertEqual(afterDiscard, 2)
    }
    func testArtworkLifetimeRespectsHTTPFreshnessAndCeiling() throws {
        func lifetime(_ headers: [String: String]) throws -> TimeInterval {
            ArtworkDataClient.lifetime(try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)), now: now)
        }
        XCTAssertEqual(try lifetime(["Cache-Control": "public, max-age=600", "Age": "550"]), 50)
        XCTAssertEqual(try lifetime(["Cache-Control": "max-age=3600"]), 300)
        XCTAssertEqual(try lifetime(["Cache-Control": "No-Cache=\"image\", max-age=60"]), 0)
        XCTAssertEqual(try lifetime(["Cache-Control": "no-store"]), 0)
        XCTAssertEqual(try lifetime(["Cache-Control": "max-age=nan"]), 0)
        XCTAssertEqual(try lifetime(["Cache-Control": "max-age=1", "Age": "9"]), 0)
        XCTAssertEqual(try lifetime(["Cache-Control": "max-age = \"60\"", "Age": "10"]), 50)
        XCTAssertEqual(try lifetime(["Cache-Control": "max-age=60", "Date": "Thu, 01 Jan 1970 02:45:40 GMT"]), 0)
        XCTAssertEqual(try lifetime(["Cache-Control": "max-age=300", "Date": "Thu, 01 Jan 1970 02:45:40 GMT"]), 240)
        XCTAssertEqual(try lifetime(["Vary": "*"]), 0)
        XCTAssertEqual(try lifetime(["Expires": "invalid"]), 0)
        XCTAssertEqual(try lifetime([:]), 300)
    }
    func testPixelLimitsHandleScaleBucketsAndInvalidGeometry() {
        XCTAssertEqual(ArtworkSizing.pixelLimit(points: 145, scale: 3), 512)
        XCTAssertEqual(ArtworkSizing.pixelLimit(points: 146, scale: 3), 512)
        XCTAssertEqual(ArtworkSizing.pixelLimit(points: 1200, scale: 3), 3200)
        XCTAssertEqual(ArtworkSizing.pixelLimit(points: .greatestFiniteMagnitude, scale: 3), 3200)
        for value in [Double.nan, .infinity, -1, 0] {
            XCTAssertEqual(ArtworkSizing.pixelLimit(points: value, scale: 2), 128)
            XCTAssertEqual(ArtworkSizing.pixelLimit(points: 100, scale: value), 128)
        }
    }
}

private enum TestFailure: Error { case timeout, missingRequest }
private func eventually(_ condition: () async -> Bool) async throws {
    let deadline = Date().addingTimeInterval(3)
    while !(await condition()) {
        guard Date() < deadline else { XCTFail("Timed out waiting for deterministic test event"); throw TestFailure.timeout }
        await Task.yield()
    }
}
private actor ValueGate {
    private var continuation: CheckedContinuation<Int, Error>?
    private(set) var starts = 0
    private(set) var wasCancelled = false
    func run() async throws -> Int {
        starts += 1
        let result: Int = try await withCheckedThrowingContinuation { continuation = $0 }
        wasCancelled = Task.isCancelled
        return result
    }
    func finish(_ value: Int) { continuation?.resume(returning: value); continuation = nil }
}
private actor HeldTransport: HTTPTransport {
    private var requests: [URLRequest] = []
    private var pending: [Int: CheckedContinuation<(Data, HTTPURLResponse), Error>] = [:]
    var count: Int { requests.count }
    func recorded() -> [URLRequest] { requests }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let index = requests.count; requests.append(request)
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func complete(_ index: Int, data: Data, status: Int = 200, headers: [String: String] = [:]) throws {
        guard let continuation = pending.removeValue(forKey: index), let url = requests[index].url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers) else { throw TestFailure.missingRequest }
        continuation.resume(returning: (data, response))
    }
}
private actor ImmediateTransport: HTTPTransport {
    let data: Data
    let headers: [String: String]
    private(set) var count = 0
    init(data: Data, headers: [String: String] = [:]) { self.data = data; self.headers = headers }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        count += 1
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!)
    }
}
