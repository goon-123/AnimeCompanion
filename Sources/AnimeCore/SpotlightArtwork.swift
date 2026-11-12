import Foundation
import SwiftSoup

/// Exactly mapped public image collections. No title search, API key or server.
public struct SpotlightArtworkTarget: Equatable, Sendable {
    public enum Kind: String, Sendable { case posters, backdrops }
    public let id: Int
    public let movie: Bool
    public let season: Int?
    public init(id: Int, movie: Bool = false, season: Int? = nil) {
        self.id = id; self.movie = movie; self.season = movie ? nil : season
    }
    private func path(_ kind: Kind) -> String {
        "/\(movie ? "movie" : "tv")/\(id)" + (season.map { "/season/\($0)" } ?? "") + "/images/\(kind.rawValue)"
    }
    public func pageURL(kind: Kind) -> URL? {
        guard id > 0, season.map({ (0...1000).contains($0) }) ?? true else { return nil }
        return URL(string: "https://www.themoviedb.org" + path(kind) + "?image_language=xx")
    }
    public func accepts(_ url: URL, kind: Kind) -> Bool {
        url.scheme == "https" && url.host == "www.themoviedb.org" && url.user == nil && url.password == nil &&
        (url.port == nil || url.port == 443) && url.path == path(kind) &&
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "image_language", value: "xx")]
    }
    func canonical(_ url: URL, kind: Kind) -> Bool {
        url.scheme == "https" && url.host == "www.themoviedb.org" && url.user == nil && url.password == nil &&
        url.port == nil && url.path == path(kind)
    }
}

public enum SpotlightArtworkParser {
    public static func images(_ data: Data, target: SpotlightArtworkTarget, kind: SpotlightArtworkTarget.Kind) throws -> [URL] {
        guard data.count <= 2_000_000, let html = String(data: data, encoding: .utf8) else { throw ServiceError.invalidResponse }
        let doc = try SwiftSoup.parse(html)
        guard let canonical = try doc.select("link[rel=canonical]").first()?.attr("href"),
              let url = URL(string: canonical), target.canonical(url, kind: kind),
              try doc.select("#image_language_xx.active").first() != nil else { throw ServiceError.invalidResponse }
        let expectedKind = kind == .posters ? "poster" : "backdrop"
        let cards = try doc.select("li[data-image-id]")
        guard cards.array().count <= 500 else { throw ServiceError.invalidResponse }
        var fullSize: [URL] = [], smaller: [URL] = [], seen = Set<URL>()
        for card in cards {
            // Verify every card as well as the selected collection. Never turn
            // the ordinary English/Japanese poster into a supposedly clean one.
            guard try card.select("input[data-language=xx][data-kind=\(expectedKind)]").first() != nil,
                  let raw = try card.select(".image_content a[title='View Original']").first()?.attr("href"),
                  let image = URL(string: raw), validImage(image), seen.insert(image).inserted else { continue }
            let size = try card.select(".info a[title='View Original']").first()?.text() ?? ""
            let dimensions = size.lowercased().split(separator: "x").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let enoughPixels = dimensions.count == 2 && (kind == .posters
                ? dimensions[0] >= 780 && dimensions[1] >= 1100
                : dimensions[0] >= 1280 && dimensions[1] >= 720)
            if enoughPixels { fullSize.append(image) } else { smaller.append(image) }
        }
        // Keep provider ordering within each group. A small old upload should
        // not win over an available sharp textless image of the same title.
        var urls = fullSize + smaller
        // This verified clean counterpart preserves the reported Mage scene.
        // It is used only while TMDB still lists it in this textless collection.
        if !target.movie, target.id == 313346, kind == .posters,
           let index = urls.firstIndex(where: { $0.lastPathComponent == "iRkFny4BWIw5nNkAbfph5UMxw18.jpg" }) {
            urls.insert(urls.remove(at: index), at: 0)
        }
        return urls
    }
    private static func validImage(_ url: URL) -> Bool {
        let path = url.path.split(separator: "/")
        return url.scheme == "https" && url.host == "image.tmdb.org" && url.user == nil && url.password == nil &&
            url.port == nil && url.query == nil && url.fragment == nil && path.count == 4 &&
            path[0] == "t" && path[1] == "p" && path[2] == "original" &&
            (8...100).contains(path[3].count) && ["jpg", "png", "webp"].contains(url.pathExtension.lowercased())
    }
}
