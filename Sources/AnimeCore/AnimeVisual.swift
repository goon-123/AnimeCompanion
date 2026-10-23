import Foundation
import SwiftSoup

public enum AnimeVisualSource: String, Codable, CaseIterable, Sendable {
    case liveChart, myAnimeList, aniList
    public var label: String {
        switch self {
        case .liveChart: return "LiveChart"
        case .myAnimeList: return "MyAnimeList"
        case .aniList: return "AniList"
        }
    }
}

public struct AnimeVisual: Identifiable, Codable, Equatable, Sendable {
    public let imageURL: URL
    public let thumbnailURL: URL
    public let title: String
    public let copyright: String?
    public let source: AnimeVisualSource
    public var id: String { imageURL.absoluteString }
    public init(imageURL: URL, thumbnailURL: URL? = nil, title: String, copyright: String? = nil, source: AnimeVisualSource) {
        self.imageURL = imageURL; self.thumbnailURL = thumbnailURL ?? imageURL
        self.title = title; self.copyright = copyright; self.source = source
    }
}

public struct AnimeVisualGallery: Sendable {
    public let images: [AnimeVisual]
    public let notice: String?
    public let isStale: Bool
    public init(images: [AnimeVisual], notice: String? = nil, isStale: Bool = false) {
        self.images = images; self.notice = notice; self.isStale = isStale
    }
    public static func aniListImages(_ anime: Anime) -> [AnimeVisual] {
        var images: [AnimeVisual] = []
        if let url = anime.coverURL, VisualURL.accepts(url) {
            images.append(AnimeVisual(imageURL: url, title: "Poster", source: .aniList))
        }
        if let raw = anime.bannerImage, let url = URL(string: raw), VisualURL.accepts(url), !images.contains(where: { $0.id == url.absoluteString }) {
            images.append(AnimeVisual(imageURL: url, title: "Banner", source: .aniList))
        }
        return images
    }
}

enum VisualURL {
    static func accepts(_ url: URL, hosts: Set<String>? = nil) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil &&
        (url.port == nil || url.port == 443) && url.host != nil &&
        (hosts == nil || hosts!.contains(url.host!.lowercased()))
    }
    static func image(_ raw: String, source: AnimeVisualSource) -> URL? {
        let hosts: Set<String> = source == .liveChart ? ["u.livechart.me"] : ["cdn.myanimelist.net"]
        guard var parts = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        parts.fragment = nil
        guard let url = parts.url, accepts(url, hosts: hosts) else { return nil }
        return url
    }
    static func gallery(_ url: URL, liveChartID: Int) -> Bool {
        accepts(url, hosts: ["www.livechart.me", "livechart.me"]) && url.path == "/anime/\(liveChartID)/visuals"
    }
}

public enum AnimeVisualsError: Error, Equatable {
    case invalidResponse, oversized, http(Int), coolingDown
}

public struct LiveChartVisualPage: Sendable {
    public let images: [AnimeVisual]
    public let nextPage: URL?
}

/// Reads the public gallery contract used by AnymeX. No scripts are executed.
public enum AnimeVisualParser {
    public static func liveChart(_ data: Data, pageURL: URL, liveChartID: Int) throws -> LiveChartVisualPage {
        guard data.count <= 2_000_000 else { throw AnimeVisualsError.oversized }
        guard VisualURL.gallery(pageURL, liveChartID: liveChartID), let html = String(data: data, encoding: .utf8) else {
            throw AnimeVisualsError.invalidResponse
        }
        let document = try SwiftSoup.parse(html, pageURL.absoluteString)
        let cards = try document.select("[data-anime-visual-url-value]")
        var images: [AnimeVisual] = [], seen = Set<String>()
        for card in cards {
            guard let url = VisualURL.image(try card.attr("data-anime-visual-url-value"), source: .liveChart), seen.insert(url.absoluteString).inserted else { continue }
            let img = card.tagName() == "img" ? card : try card.select("img").first()
            let alt = try img?.attr("alt").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text = try card.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let copyrightStart = text.firstIndex(of: "©")
            let credit = copyrightStart.map { String(text[$0...].prefix(300)) }
            let caption = String((copyrightStart.map { String(text[..<$0]) } ?? text).trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
            let title = !alt.isEmpty ? String(alt.prefix(180)) : (!caption.isEmpty ? caption : "Visual \(images.count + 1)")
            let thumbnail = try img.flatMap { VisualURL.image(try $0.attr("src"), source: .liveChart) }
            images.append(AnimeVisual(imageURL: url, thumbnailURL: thumbnail, title: title, copyright: credit, source: .liveChart))
            guard images.count <= 500 else { throw AnimeVisualsError.oversized }
        }
        // A challenge/login/layout change must not be reported as an empty gallery.
        if images.isEmpty {
            let canonical = try document.select("link[rel=canonical]").first()?.attr("href") ?? ""
            guard let url = URL(string: canonical), VisualURL.gallery(url, liveChartID: liveChartID), cards.isEmpty() else {
                throw AnimeVisualsError.invalidResponse
            }
        }
        var nextPage: URL?
        if let link = try document.select("a[rel~=next], link[rel~=next]").first() {
            let raw = try link.attr("href")
            guard let url = URL(string: raw, relativeTo: pageURL)?.absoluteURL,
                  VisualURL.gallery(url, liveChartID: liveChartID),
                  let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let page = parts.queryItems?.first(where: { $0.name == "page" })?.value,
                  let number = Int(page), (2...20).contains(number) else { throw AnimeVisualsError.invalidResponse }
            nextPage = url
        }
        return LiveChartVisualPage(images: images, nextPage: nextPage)
    }

    public static func myAnimeList(_ data: Data) throws -> [AnimeVisual] {
        struct Response: Decodable { let data: [Picture] }
        struct Picture: Decodable { let jpg: Variant?; let webp: Variant? }
        struct Variant: Decodable { let image_url: String?; let large_image_url: String?; let small_image_url: String? }
        guard data.count <= 1_000_000 else { throw AnimeVisualsError.oversized }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.data.count <= 500 else { throw AnimeVisualsError.oversized }
        var result: [AnimeVisual] = [], seen = Set<String>()
        for item in response.data {
            let variants = [item.jpg, item.webp].compactMap { $0 }
            guard let url = variants.compactMap({ $0.large_image_url ?? $0.image_url }).compactMap({ VisualURL.image($0, source: .myAnimeList) }).first,
                  seen.insert(url.absoluteString).inserted else { continue }
            let thumbnail = variants.compactMap { $0.small_image_url ?? $0.image_url }.compactMap { VisualURL.image($0, source: .myAnimeList) }.first
            result.append(AnimeVisual(imageURL: url, thumbnailURL: thumbnail, title: "Artwork \(result.count + 1)", source: .myAnimeList))
        }
        if !response.data.isEmpty && result.isEmpty { throw AnimeVisualsError.invalidResponse }
        return result
    }
}
