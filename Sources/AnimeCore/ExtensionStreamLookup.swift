import Foundation

/// Provider payloads stay intact from search through video resolution.
public protocol ExtensionStreamClient: Sendable {
    func search(source: UnifiedExtensionSource, query: String) async throws -> ExtensionMediaPage
    func detail(source: UnifiedExtensionSource, media: ExtensionMedia) async throws -> ExtensionMedia
    func videos(source: UnifiedExtensionSource, episode: ExtensionEpisode) async throws -> [ExtensionVideo]
}

public struct ExtensionStreamResult: Identifiable, Sendable {
    public let source: UnifiedExtensionSource
    public let videos: [ExtensionVideo]
    public let message: String?
    public var id: String { source.id }
    public init(source: UnifiedExtensionSource, videos: [ExtensionVideo] = [], message: String? = nil) {
        self.source = source; self.videos = videos; self.message = message
    }
}

public enum ExtensionStreamLookup {
    public static func titles(for anime: Anime) -> [String] {
        var seen = Set<String>()
        return ([anime.title?.english, anime.title?.romaji, anime.title?.userPreferred].compactMap { $0 } + (anime.synonyms ?? []))
            .filter { !$0.isEmpty && seen.insert(normalize($0)).inserted }
    }
    public static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }
    public static func matchingMedia(_ media: [ExtensionMedia], anime: Anime) -> ExtensionMedia? {
        let aliases = Set(titles(for: anime).map(normalize))
        var seen = Set<String>()
        let matches = media.filter { aliases.contains(normalize($0.title)) && seen.insert($0.id).inserted }
        return matches.count == 1 ? matches[0] : nil
    }
    /// Never infer episode numbers from array order or choose between seasons.
    public static func matchingEpisode(_ episodes: [ExtensionEpisode], number: Int, movie: Bool = false) -> ExtensionEpisode? {
        let seasons = Set(episodes.compactMap { $0.payload["sortMap"]["season"].string }.filter { !$0.isEmpty })
        guard seasons.count <= 1 else { return nil }
        let matches = episodes.filter { episodeNumber($0) == Double(number) }
        if matches.count == 1 { return matches[0] }
        if movie && number == 1 && episodes.count == 1 && episodeNumber(episodes[0]) == nil { return episodes[0] }
        return nil
    }
    private static func episodeNumber(_ episode: ExtensionEpisode) -> Double? {
        let raw = episode.payload["episodeNumber"]
        if case .number(let value) = raw { return value }
        if let text = raw.string, let value = Double(text) { return value }
        // Only explicit episode labels, never a date or a bare number in a title.
        guard let name = episode.payload["name"].string,
              let range = name.range(of: #"(?i)\b(?:episode|ep)\.?\s*(\d+(?:\.\d+)?)\b"#, options: .regularExpression) else { return nil }
        let label = String(name[range])
        return label.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression).flatMap { Double(label[$0]) }
    }
    public static func resolve(source: UnifiedExtensionSource, anime: Anime, episode: Int,
                               client: any ExtensionStreamClient) async throws -> ExtensionStreamResult {
        var candidates: [ExtensionMedia] = []
        // Alternate AniList titles help sources whose catalogs use romaji.
        for query in titles(for: anime).prefix(3) {
            try Task.checkCancellation()
            let page = try await client.search(source: source, query: query)
            try Task.checkCancellation()
            candidates += page.list
            if let media = matchingMedia(candidates, anime: anime) {
                let detail = try await client.detail(source: source, media: media)
                try Task.checkCancellation()
                guard let selected = matchingEpisode(detail.episodes, number: episode, movie: anime.format == "MOVIE") else {
                    return .init(source: source, message: "Choose the matching episode in this source.")
                }
                let videos = try await client.videos(source: source, episode: selected)
                try Task.checkCancellation()
                return .init(source: source, videos: videos, message: videos.isEmpty ? "No videos returned for episode \(episode)." : nil)
            }
        }
        return .init(source: source, message: "Choose the matching title in this source.")
    }
}

public extension ExtensionVideo {
    var isMagnet: Bool { url.lowercased().hasPrefix("magnet:") }
    var canPlay: Bool { isMagnet || StremioStream.networkURL(url) != nil }
    var audio: StreamAudioInfo { .init(texts: [title ?? "", quality]) }
    /// Headers remain on ExtensionVideo for the native extension player.
    func stream(sourceName: String) throws -> StremioStream {
        var object: [String: Any] = ["name": sourceName, "title": [title, quality].compactMap { $0 }.joined(separator: " · "), "url": url]
        object["subtitles"] = (subtitles ?? []).enumerated().compactMap { index, subtitle -> [String: String]? in
            guard let file = subtitle.file, StremioStream.networkURL(file) != nil else { return nil }
            return ["id": String(index), "url": file, "lang": subtitle.label ?? "Subtitles"]
        }
        return try JSONDecoder().decode(StremioStream.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
