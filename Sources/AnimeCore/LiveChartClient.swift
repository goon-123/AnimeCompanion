import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MetadataSource: String, CaseIterable, Identifiable, Sendable {
    case aniList = "anilist", liveChart = "livechart"
    public var id: String { rawValue }
    public var label: String { self == .aniList ? "AniList" : "LiveChart.me" }
}

public enum LiveChartURL {
    public static func accepts(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil &&
        ["livechart.me", "www.livechart.me"].contains(url.host?.lowercased() ?? "")
    }
    public static func animeID(_ url: URL) -> Int? {
        guard accepts(url) else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count == 2, parts[0] == "anime", let id = Int(parts[1]), id > 0 else { return nil }
        return id
    }
    public static func anime(_ id: Int) -> URL { URL(string: "https://www.livechart.me/anime/\(id)")! }
    public static func season(_ selection: SeasonSelection) -> URL {
        URL(string: "https://www.livechart.me/\(selection.season.rawValue.lowercased())-\(selection.year)/tv")!
    }
    public static func search(_ title: String) -> URL {
        var parts = URLComponents(string: "https://www.livechart.me/search")!
        parts.queryItems = [URLQueryItem(name: "q", value: title)]
        return parts.url!
    }
}

public struct LiveChartMappingIndex: Sendable {
    private let forward: [Int: Set<Int>]
    private let reverse: [Int: Set<Int>]
    public init(tsv: Data) throws {
        guard tsv.count <= 16_000_000, let text = String(data: tsv, encoding: .utf8) else { throw ServiceError.invalidResponse }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard let header = lines.first else { throw ServiceError.invalidResponse }
        let columns = header.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t", omittingEmptySubsequences: false)
        guard let al = columns.firstIndex(of: "anilist"), let lc = columns.firstIndex(of: "livechart") else { throw ServiceError.invalidResponse }
        var forward: [Int: Set<Int>] = [:], reverse: [Int: Set<Int>] = [:]
        for line in lines.dropFirst() {
            let cells = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cells.count == columns.count, let a = Int(cells[al]), a > 0,
                  let l = Int(cells[lc].trimmingCharacters(in: .whitespacesAndNewlines)), l > 0 else { continue }
            forward[a, default: []].insert(l); reverse[l, default: []].insert(a)
        }
        guard !forward.isEmpty else { throw ServiceError.invalidResponse }
        self.forward = forward; self.reverse = reverse
    }
    /// A match must be one-to-one in both directions. Split cours and conflicts stay unlinked.
    public func liveChartID(aniListID: Int) -> Int? {
        guard let ids = forward[aniListID], ids.count == 1, let id = ids.first,
              reverse[id] == Set([aniListID]) else { return nil }
        return id
    }
    public func aniListID(liveChartID: Int) -> Int? {
        guard let ids = reverse[liveChartID], ids.count == 1, let id = ids.first,
              forward[id] == Set([liveChartID]) else { return nil }
        return id
    }
}

/// Downloads only the public ID index, never scrapes LiveChart metadata or sends account data.
public actor LiveChartClient {
    public static let mappingURL = URL(string: "https://raw.githubusercontent.com/nattadasu/animeApi/v3/database/animeapi.tsv")!
    private let transport: any HTTPTransport
    private let file: URL?
    private var cached: (Date, LiveChartMappingIndex)?
    private var pending: Task<LiveChartMappingIndex, Error>?
    public init(transport: any HTTPTransport = URLSessionTransport(), cacheFile: URL? = nil) {
        self.transport = transport
        file = cacheFile ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AnimeCompanion-livechart-ids.tsv")
    }
    public func liveChartID(aniListID: Int) async throws -> Int? { try await index().liveChartID(aniListID: aniListID) }
    public func aniListID(liveChartID: Int) async throws -> Int? { try await index().aniListID(liveChartID: liveChartID) }
    private func index() async throws -> LiveChartMappingIndex {
        if let cached, Date().timeIntervalSince(cached.0) < 86400 { return cached.1 }
        if let pending { return try await pending.value }
        if cached == nil, let file, let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
           let size = attrs.fileSize, size <= 16_000_000, let date = attrs.contentModificationDate,
           Date().timeIntervalSince(date) < 7 * 86400, let data = try? Data(contentsOf: file),
           let index = try? LiveChartMappingIndex(tsv: data) {
            cached = (date, index)
            if Date().timeIntervalSince(date) < 86400 { return index }
        }
        let transport = self.transport; let file = self.file
        let task = Task<LiveChartMappingIndex, Error> {
            var request = URLRequest(url: Self.mappingURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
            request.setValue("text/tab-separated-values", forHTTPHeaderField: "Accept")
            let (data, response) = try await transport.data(for: request)
            try HTTPValidation.check(response)
            let index = try LiveChartMappingIndex(tsv: data)
            if let file {
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: file, options: .atomic)
            }
            return index
        }
        pending = task
        defer { pending = nil }
        do { let index = try await task.value; cached = (Date(), index); return index }
        catch { if let cached, Date().timeIntervalSince(cached.0) < 7 * 86400 { return cached.1 }; throw error }
    }
}
