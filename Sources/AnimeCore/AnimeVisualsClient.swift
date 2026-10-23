import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Public artwork only. This client has no account tokens, browser cookies or tracking operations.
public actor AnimeVisualsClient {
    private struct Key: Hashable, Codable, Sendable { let aniList: Int; let mal: Int? }
    private struct Record: Codable, Sendable {
        let key: Key
        let images: [AnimeVisual]
        let notice: String?
        let fetchedAt: Date
        let complete: Bool
    }
    private struct LiveResult { let images: [AnimeVisual]; let partial: Bool }
    private let transport: any HTTPTransport
    private let mapping: VisualsMappingClient
    private let cacheFile: URL?
    private let minimumRequestInterval: TimeInterval
    private var cache: [Key: Record] = [:]
    private var pending: [Key: Task<Record, Never>] = [:]
    private var restored = false
    private var nextRequest: [String: Date] = [:]
    private var blockedUntil: [String: Date] = [:]

    public init(transport: any HTTPTransport = AnimeVisualsClient.publicTransport(),
                directory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("AnimeCompanion-visuals"),
                minimumRequestInterval: TimeInterval = 1) {
        self.transport = transport; self.minimumRequestInterval = max(0, minimumRequestInterval)
        mapping = VisualsMappingClient(transport: transport, directory: directory)
        cacheFile = directory?.appendingPathComponent("galleries.json")
    }
    public nonisolated static func publicTransport() -> URLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil; configuration.urlCache = nil
        return URLSessionTransport(session: URLSession(configuration: configuration))
    }

    public func gallery(for anime: Anime, refresh: Bool = false) async -> AnimeVisualGallery {
        let local = AnimeVisualGallery.aniListImages(anime)
        guard anime.id > 0 else { return AnimeVisualGallery(images: local) }
        restoreCache()
        let key = Key(aniList: anime.id, mal: anime.idMal.flatMap { $0 > 0 ? $0 : nil })
        if !refresh, let record = cache[key], Date().timeIntervalSince(record.fetchedAt) < (record.complete ? 21600 : 300) {
            return gallery(record, local: local)
        }
        let record: Record
        let previous = cache[key]
        let ownsRequest: Bool
        if let task = pending[key] { ownsRequest = false; record = await task.value }
        else {
            ownsRequest = true
            let task = Task { await self.fetch(key) }
            pending[key] = task
            record = await task.value
            pending[key] = nil
        }
        // All coalesced callers receive the same saved gallery when a refresh fails.
        if !record.complete, let old = previous, !old.images.isEmpty,
           Date().timeIntervalSince(old.fetchedAt) < 7 * 86400 {
            return AnimeVisualGallery(images: merged(merged(record.images, old.images), local),
                notice: "The full gallery could not refresh. Previously loaded artwork has been kept.", isStale: true)
        }
        if ownsRequest { cache[key] = record; saveCache() }
        return gallery(record, local: local)
    }
    private func gallery(_ record: Record, local: [AnimeVisual]) -> AnimeVisualGallery {
        AnimeVisualGallery(images: merged(record.images, local), notice: record.notice)
    }
    private func merged(_ remote: [AnimeVisual], _ local: [AnimeVisual]) -> [AnimeVisual] {
        var seen = Set<String>()
        return (remote + local).filter { seen.insert($0.id).inserted }
    }
    private func fetch(_ key: Key) async -> Record {
        var images: [AnimeVisual] = []
        var reason = "LiveChart could not load."
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
            } else { reason = "No matching LiveChart gallery is available for this title." }
        } catch { /* A denied/unavailable page falls back without a browser or automatic retry. */ }
        if let mal = key.mal {
            do {
                let url = URL(string: "https://api.jikan.moe/v4/anime/\(mal)/pictures")!
                let data = try await request(url, accept: "application/json", maximumBytes: 1_000_000)
                images = try AnimeVisualParser.myAnimeList(data)
                if !images.isEmpty { reason += " Showing MyAnimeList artwork where available." }
                else { reason += " MyAnimeList has no additional artwork listed." }
            } catch { reason += " Additional MyAnimeList artwork is also unavailable."; complete = false }
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
        request.setValue("AnimeCompanion/0.25 (Artwork gallery)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        if [401, 403, 429].contains(response.statusCode) {
            let retry = min(86400, max(60, Double(response.value(forHTTPHeaderField: "Retry-After") ?? "900") ?? 900))
            blockedUntil[host] = Date().addingTimeInterval(retry)
        }
        guard response.statusCode == 200 else { throw AnimeVisualsError.http(response.statusCode) }
        guard response.url == url else { throw AnimeVisualsError.invalidResponse }
        guard data.count <= maximumBytes else { throw AnimeVisualsError.oversized }
        return data
    }

    private func restoreCache() {
        guard !restored else { return }; restored = true
        guard let file = cacheFile, let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2_000_000,
              let data = try? Data(contentsOf: file), let records = try? JSONDecoder().decode([Record].self, from: data), records.count <= 40 else { return }
        for record in records where Date().timeIntervalSince(record.fetchedAt) >= 0 && Date().timeIntervalSince(record.fetchedAt) < 7 * 86400 {
            guard record.images.count <= 500, record.key.aniList > 0,
                  record.images.allSatisfy({ VisualURL.image($0.imageURL.absoluteString, source: $0.source) != nil && VisualURL.image($0.thumbnailURL.absoluteString, source: $0.source) != nil }) else { continue }
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
                    try? data.write(to: file, options: .atomic)
                }
                return
            }
            guard !records.isEmpty else { return }; records.removeLast()
        }
    }
}
