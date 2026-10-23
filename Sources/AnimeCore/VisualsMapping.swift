import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// AnimeAPI IDs are accepted only when the AniList/LiveChart relationship is unambiguous.
public struct VisualsMappingIndex: Sendable {
    private var forward: [Int: Set<Int>] = [:]
    private var reverse: [Int: Set<Int>] = [:]
    private var malIDs: [Int: Set<Int>] = [:]
    public init(tsv: Data) throws {
        guard tsv.count <= 16_000_000, let text = String(data: tsv, encoding: .utf8) else { throw AnimeVisualsError.invalidResponse }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard let first = lines.first else { throw AnimeVisualsError.invalidResponse }
        let columns = first.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t", omittingEmptySubsequences: false)
        guard let al = columns.firstIndex(of: "anilist"), let lc = columns.firstIndex(of: "livechart"), let mal = columns.firstIndex(of: "myanimelist") else {
            throw AnimeVisualsError.invalidResponse
        }
        for line in lines.dropFirst() {
            let cells = line.trimmingCharacters(in: .newlines).split(separator: "\t", omittingEmptySubsequences: false)
            guard cells.count == columns.count, let a = Int(cells[al]), a > 0, let l = Int(cells[lc]), l > 0 else { continue }
            forward[a, default: []].insert(l); reverse[l, default: []].insert(a)
            if let m = Int(cells[mal]), m > 0 { malIDs[a, default: []].insert(m) }
        }
        guard !forward.isEmpty else { throw AnimeVisualsError.invalidResponse }
    }
    public func liveChartID(aniListID: Int, malID: Int?) -> Int? {
        guard let ids = forward[aniListID], ids.count == 1, let id = ids.first, reverse[id] == Set([aniListID]) else { return nil }
        if let mapped = malIDs[aniListID], mapped.count > 1 { return nil }
        if let malID, let mapped = malIDs[aniListID], !mapped.contains(malID) { return nil }
        return id
    }
}

actor VisualsMappingClient {
    static let url = URL(string: "https://raw.githubusercontent.com/nattadasu/animeApi/v3/database/animeapi.tsv")!
    private let transport: any HTTPTransport
    private let file: URL?
    private var cached: (date: Date, index: VisualsMappingIndex)?
    private var pending: Task<VisualsMappingIndex, Error>?
    private var retryAfter = Date.distantPast
    init(transport: any HTTPTransport, directory: URL?) {
        self.transport = transport; file = directory?.appendingPathComponent("visual-ids.tsv")
    }
    func id(aniListID: Int, malID: Int?) async throws -> Int? {
        try await index().liveChartID(aniListID: aniListID, malID: malID)
    }
    private func index() async throws -> VisualsMappingIndex {
        let now = Date()
        if cached == nil, let file,
           let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
           let size = attrs.fileSize, size <= 16_000_000, let date = attrs.contentModificationDate,
           now.timeIntervalSince(date) < 7 * 86400, let data = try? Data(contentsOf: file), let index = try? VisualsMappingIndex(tsv: data) {
            cached = (date, index)
        }
        if let cached, now.timeIntervalSince(cached.date) < 86400 { return cached.index }
        if let pending { return try await pending.value }
        if now < retryAfter {
            if let cached, now.timeIntervalSince(cached.date) < 7 * 86400 { return cached.index }
            throw AnimeVisualsError.coolingDown
        }
        let transport = self.transport, file = self.file
        let task = Task<VisualsMappingIndex, Error> {
            var request = URLRequest(url: Self.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
            request.setValue("text/tab-separated-values", forHTTPHeaderField: "Accept")
            let (data, response) = try await transport.data(for: request)
            guard response.statusCode == 200, response.url == Self.url else { throw AnimeVisualsError.invalidResponse }
            let index = try VisualsMappingIndex(tsv: data)
            if let file {
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: file, options: .atomic)
            }
            return index
        }
        pending = task
        defer { pending = nil }
        do { let index = try await task.value; cached = (Date(), index); return index }
        catch {
            retryAfter = now.addingTimeInterval(300)
            if let cached, now.timeIntervalSince(cached.date) < 7 * 86400 { return cached.index }
            throw error
        }
    }
}
