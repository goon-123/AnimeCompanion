import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Public artwork only. This client has no account tokens, browser cookies or tracking operations.
public actor AnimeVisualsClient {
    private let persistence = AppDataSession()
    private struct Key: Hashable, Codable, Sendable { let aniList: Int; let mal: Int? }
    private struct Record: Codable, Sendable {
        let key: Key
        let images: [AnimeVisual]
        let notice: String?
        let fetchedAt: Date
        let complete: Bool
        var checkedAt: Date? = nil
    }
    private struct LiveResult { let images: [AnimeVisual]; let partial: Bool }
    private let galleryTransport: any HTTPTransport
    private let mapping: VisualsMappingClient
    private let cacheFile: URL?
    private let minimumRequestInterval: TimeInterval
    private var cache: [Key: Record] = [:]
    private let requests = RequestCoalescer<Key, Record>()
    private var restored = false
    private var nextRequest: [String: Date] = [:]
    private var blockedUntil: [String: Date] = [:]

    public init(transport: any HTTPTransport = AnimeVisualsClient.publicTransport(),
                galleryTransport: (any HTTPTransport)? = nil,
                directory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("AnimeCompanion-visuals"),
                minimumRequestInterval: TimeInterval = 1) {
        self.galleryTransport = galleryTransport ?? transport
        self.minimumRequestInterval = max(0, minimumRequestInterval)
        mapping = VisualsMappingClient(transport: transport, directory: directory)
        // Do not reuse old negative results or galleries containing other sources.
        cacheFile = directory?.appendingPathComponent("livechart-galleries-v2.json")
    }
    public nonisolated static func publicTransport() -> URLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        return URLSessionTransport(session: URLSession(configuration: configuration))
    }

    public func gallery(for anime: Anime, refresh: Bool = false) async -> AnimeVisualGallery {
        let local = AnimeVisualGallery.aniListImages(anime)
        guard anime.id > 0 else { return AnimeVisualGallery(images: local) }
        restoreCache()
        let key = Key(aniList: anime.id, mal: anime.idMal.flatMap { $0 > 0 ? $0 : nil })
        if !refresh, let record = cache[key], Date().timeIntervalSince(record.checkedAt ?? record.fetchedAt) < (record.complete ? 21600 : 300) {
            return gallery(record, local: local)
        }
        do {
            let record = try await requests.value(for: key) {
                let record = try await self.fetch(key)
                try Task.checkCancellation()
                return await self.remember(record)
            }
            return gallery(record, local: local)
        } catch {
            // Leaving a lazy shelf releases only that caller; an open full
            // gallery keeps its shared request. Cancelled work is never cached.
            return cachedGallery(for: anime)
        }
    }
    /// AniList art and previously loaded LiveChart visuals are usable before a
    /// network request finishes, including on a cold/offline return visit.
    public func cachedGallery(for anime: Anime) -> AnimeVisualGallery {
        restoreCache()
        let local = AnimeVisualGallery.aniListImages(anime)
        let key = Key(aniList: anime.id, mal: anime.idMal.flatMap { $0 > 0 ? $0 : nil })
        guard let record = cache[key] else { return AnimeVisualGallery(images: local) }
        return gallery(record, local: local)
    }
    private func remember(_ record: Record) -> Record {
        var result = record
        if !record.complete, let old = cache[record.key], !old.images.isEmpty,
           Date().timeIntervalSince(old.fetchedAt) < 7 * 86400 {
            result = Record(key: record.key, images: Array(merged(record.images, old.images).prefix(500)),
                notice: "LiveChart could not refresh. Previously loaded LiveChart artwork has been kept.",
                fetchedAt: record.images.isEmpty ? old.fetchedAt : record.fetchedAt, complete: false,
                checkedAt: Date())
        }
        cache[record.key] = result; saveCache()
        return result
    }
    private func gallery(_ record: Record, local: [AnimeVisual]) -> AnimeVisualGallery {
        AnimeVisualGallery(images: merged(record.images, local), notice: record.notice,
            isStale: !record.complete && !record.images.isEmpty || Date().timeIntervalSince(record.fetchedAt) >= 21600)
    }
    private func merged(_ remote: [AnimeVisual], _ local: [AnimeVisual]) -> [AnimeVisual] {
        var seen = Set<String>()
        return (remote + local).filter { seen.insert($0.id).inserted }
    }
    private func fetch(_ key: Key) async throws -> Record {
        var images: [AnimeVisual] = []
        var reason = "LiveChart artwork could not load. Try refreshing later."
        var complete = false
        do {
            if let id = try await mapping.id(aniListID: key.aniList, malID: key.mal) {
                let result = try await liveChart(id)
                images = result.images; complete = !result.partial
                if !images.isEmpty {
                    return Record(key: key, images: images,
                        notice: result.partial ? "Some LiveChart visuals could not load. Pull to refresh later." : nil,
                        fetchedAt: Date(), complete: complete)
                }
                reason = "This title has no LiveChart visuals listed yet."
                complete = !result.partial
            } else { reason = "No matching LiveChart gallery is available for this title." }
        } catch is CancellationError { throw CancellationError()
        } catch AnimeVisualsError.http(let status) where [401, 403, 429].contains(status) {
            reason = "LiveChart is temporarily limiting artwork requests. Try refreshing later."
        } catch AnimeVisualsError.coolingDown {
            reason = "LiveChart is temporarily limiting artwork requests. Try refreshing later."
        } catch {
            try Task.checkCancellation()
            // A failed request is different from a confirmed empty gallery.
        }
        return Record(key: key, images: images, notice: reason, fetchedAt: Date(), complete: complete)
    }

    private func liveChart(_ id: Int) async throws -> LiveResult {
        var page: URL? = URL(string: "https://www.livechart.me/anime/\(id)/visuals")!
        var seenPages = Set<URL>(), seenImages = Set<String>(), images: [AnimeVisual] = []
        while let url = page {
            guard seenPages.insert(url).inserted, seenPages.count <= 10 else { return LiveResult(images: images, partial: true) }
            do {
                let data = try await request(url, accept: "text/html", maximumBytes: 2_000_000)
                let result = try AnimeVisualParser.liveChart(data, pageURL: url, liveChartID: id)
                images += result.images.filter { seenImages.insert($0.id).inserted }
                if images.count > 500 { return LiveResult(images: Array(images.prefix(500)), partial: true) }
                page = result.nextPage
            } catch {
                try Task.checkCancellation()
                if images.isEmpty { throw error }
                return LiveResult(images: images, partial: true)
            }
        }
        return LiveResult(images: images, partial: false)
    }

    private func request(_ url: URL, accept: String, maximumBytes: Int) async throws -> Data {
        let host = url.host ?? ""
        if let until = blockedUntil[host], until > Date() { throw AnimeVisualsError.coolingDown }
        let start = max(Date(), nextRequest[host] ?? .distantPast)
        nextRequest[host] = start.addingTimeInterval(minimumRequestInterval)
        let delay = start.timeIntervalSinceNow
        guard delay <= 30 else { throw AnimeVisualsError.coolingDown }
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        try Task.checkCancellation()
        if let until = blockedUntil[host], until > Date() { throw AnimeVisualsError.coolingDown }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("AnimeCompanion/0.57.3 (Artwork gallery)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await pageData(for: request)
        try Task.checkCancellation()
        if [401, 403, 429].contains(response.statusCode) {
            let retry = min(86400, max(60, Double(response.value(forHTTPHeaderField: "Retry-After") ?? "900") ?? 900))
            blockedUntil[host] = Date().addingTimeInterval(retry)
        }
        guard response.statusCode == 200 else { throw AnimeVisualsError.http(response.statusCode) }
        guard let final = response.url, VisualURL.sameGallery(final, as: url) else { throw AnimeVisualsError.invalidResponse }
        guard data.count <= maximumBytes else { throw AnimeVisualsError.oversized }
        return data
    }

    private func pageData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        for attempt in 0...1 {
            do {
                let result = try await galleryTransport.data(for: request)
                guard attempt == 0, [502, 503, 504].contains(result.1.statusCode),
                      result.1.value(forHTTPHeaderField: "Retry-After") == nil else { return result }
            } catch let error as URLError where attempt == 0 &&
                [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code) {
                // One bounded retry for an interrupted public page. Denials,
                // offline errors and rate limits never take another route.
            }
            try await Task.sleep(nanoseconds: UInt64(max(0.3, minimumRequestInterval) * 1_000_000_000))
            try Task.checkCancellation()
        }
        throw AnimeVisualsError.invalidResponse
    }

    private func restoreCache() {
        guard !restored else { return }; restored = true
        guard let file = cacheFile, let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000,
              let data = try? Data(contentsOf: file), let records = try? JSONDecoder().decode([Record].self, from: data), records.count <= 40 else { return }
        for record in records where Date().timeIntervalSince(record.fetchedAt) >= 0 && Date().timeIntervalSince(record.fetchedAt) < 7 * 86400 {
            guard record.images.count <= 500, record.key.aniList > 0,
                  record.images.allSatisfy({ $0.source == .liveChart && VisualURL.image($0.imageURL.absoluteString, source: .liveChart) != nil && VisualURL.image($0.thumbnailURL.absoluteString, source: .liveChart) != nil }) else { continue }
            cache[record.key] = record
        }
    }
    private func saveCache() {
        cache = cache.filter { Date().timeIntervalSince($0.value.fetchedAt) < 7 * 86400 }
        var records = cache.values.sorted { $0.fetchedAt > $1.fetchedAt }
        if records.count > 40 { records = Array(records.prefix(40)) }
        while let data = try? JSONEncoder().encode(records) {
            if data.count <= 2_000_000 {
                cache = Dictionary(uniqueKeysWithValues: records.map { ($0.key, $0) })
                if let file = cacheFile {
                    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? persistence.write(data, to: file, options: .atomic)
                }
                return
            }
            guard !records.isEmpty else { return }; records.removeLast()
        }
    }
}
