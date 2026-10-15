import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ArtworkError: LocalizedError, Equatable {
    case invalidURL, invalidData, tooLarge
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "This image address is unavailable."
        case .invalidData: return "This image could not be opened."
        case .tooLarge: return "This image is too large to open."
        }
    }
}

public struct ArtworkData: Sendable {
    public let data: Data
    public let expiresAt: Date
}

/// Public artwork only. Account and playback sessions never use this session or cache.
public actor ArtworkDataClient {
    private struct Key: Hashable, Sendable { let url: URL; let refresh: Bool }
    private let transport: any HTTPTransport
    private let httpCache: URLCache?
    private var cache = BoundedCache<URL, ArtworkData>(maximumCount: 64, maximumCost: 24_000_000)
    private let requests = RequestCoalescer<Key, ArtworkData>()
    private var generation: UInt64 = 0
    private var refreshing: [URL: UUID] = [:]
    private var latestWrites: [URL: UUID] = [:]

    public init(transport: (any HTTPTransport)? = nil) {
        if let transport { self.transport = transport; httpCache = nil }
        else {
            let configuration = URLSessionConfiguration.default
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            configuration.urlCache = URLCache(memoryCapacity: 8_000_000, diskCapacity: 128_000_000,
                                              diskPath: "AnimeCompanion-public-artwork")
            httpCache = configuration.urlCache
            configuration.requestCachePolicy = .useProtocolCachePolicy
            self.transport = URLSessionTransport(session: URLSession(configuration: configuration))
        }
    }
    public func image(at url: URL, refresh: Bool = false) async throws -> ArtworkData {
        try Task.checkCancellation()
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
              url.user == nil, url.password == nil else { throw ArtworkError.invalidURL }
        let refresh = refresh || refreshing[url] != nil
        if !refresh, let value = cache.value(for: url) { return value }
        // A retry never joins a normal request that URLCache may be satisfying from disk.
        return try await requests.value(for: Key(url: url, refresh: refresh)) {
            try await self.fetch(url, refresh: refresh)
        }
    }
    private func fetch(_ url: URL, refresh: Bool) async throws -> ArtworkData {
        if !refresh, let value = cache.value(for: url) { return value }
        let started = generation
        let write = UUID(); latestWrites[url] = write
        if refresh { refreshing[url] = write; cache.remove(url) }
        defer {
            if refreshing[url] == write { refreshing.removeValue(forKey: url) }
            if latestWrites[url] == write { latestWrites.removeValue(forKey: url) }
        }
        var request = URLRequest(url: url, cachePolicy: refresh ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy,
                                 timeoutInterval: 25)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        try HTTPValidation.check(response)
        guard !data.isEmpty else { throw ArtworkError.invalidData }
        // This bounds retained bytes after download; it is not a streaming download limit.
        guard data.count <= 12_000_000 else { throw ArtworkError.tooLarge }
        if let mime = response.mimeType?.lowercased(), !mime.hasPrefix("image/"), mime != "application/octet-stream" {
            throw ArtworkError.invalidData
        }
        let now = Date()
        let value = ArtworkData(data: data, expiresAt: now.addingTimeInterval(Self.lifetime(response, now: now)))
        if generation == started, latestWrites[url] == write {
            cache.insert(value, for: url, cost: data.count, expiresAt: value.expiresAt, now: now)
        }
        return value
    }
    public func clearMemory() { generation &+= 1; cache.removeAll() }
    public func discard(_ url: URL) {
        cache.remove(url)
        httpCache?.removeCachedResponse(for: URLRequest(url: url))
    }

    /// Keep memory entries no longer than the server allows, with a five-minute ceiling.
    static func lifetime(_ response: HTTPURLResponse, now: Date) -> TimeInterval {
        let control = (response.value(forHTTPHeaderField: "Cache-Control") ?? "").lowercased()
        let directives = control.split(separator: ",").map { directive in
            directive.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        if directives.contains(where: { ["no-store", "no-cache"].contains($0[0]) }) { return 0 }
        if response.value(forHTTPHeaderField: "Vary")?.trimmingCharacters(in: .whitespaces) == "*" { return 0 }
        let suppliedAge = Double(response.value(forHTTPHeaderField: "Age") ?? "0") ?? 0
        guard suppliedAge.isFinite else { return 0 }
        let serverDate = response.value(forHTTPHeaderField: "Date").flatMap(httpDate)
        let age = max(0, suppliedAge, serverDate.map { now.timeIntervalSince($0) } ?? 0)
        if let maxAge = directives.first(where: { $0[0] == "max-age" }) {
            guard maxAge.count == 2 else { return 0 }
            let raw = maxAge[1].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            guard let seconds = Double(raw), seconds.isFinite, age.isFinite else { return 0 }
            return max(0, min(300, seconds - age))
        }
        if let expires = response.value(forHTTPHeaderField: "Expires") {
            guard let date = httpDate(expires) else { return 0 }
            return max(0, min(300, date.timeIntervalSince(now)))
        }
        return 300
    }
    private static func httpDate(_ value: String) -> Date? {
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return format.date(from: value)
    }
}

public enum ArtworkSizing {
    /// Bucket pixel dimensions so minor layout changes reuse an existing decoded bitmap.
    public static func pixelLimit(points: Double, scale: Double) -> Int {
        guard points.isFinite, scale.isFinite, points > 0, scale > 0 else { return 128 }
        let pixels = min(3200, points * min(scale, 4))
        return [128, 256, 512, 1024, 1600, 2400, 3200].first { Double($0) >= pixels } ?? 3200
    }
}
