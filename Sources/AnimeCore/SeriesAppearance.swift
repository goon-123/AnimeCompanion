import Foundation

public enum AnimeSeriesStyle: String, CaseIterable, Identifiable, Sendable {
    case cinematic, classic
    public static let storageKey = "series.appearance.style.v1"
    public var id: String { rawValue }
    public var title: String { self == .cinematic ? "Cinematic" : "Classic AniList" }
    public init(preference: String) { self = Self(rawValue: preference) ?? .cinematic }
}

/// Artwork choices never change the series layout or account metadata.
public struct SeriesArtworkPreferences: Equatable, Sendable {
    public static let logoKey = "series.artwork.anilist-logo-fallback.v1"
    public static let bannerKey = "series.artwork.anilist-banner-fallback.v1"
    public static let posterKey = "series.artwork.anilist-poster-fallback.v1"
    public var logo: Bool
    public var banner: Bool
    public var poster: Bool
    public init(logo: Bool = false, banner: Bool = false, poster: Bool = false) {
        self.logo = logo; self.banner = banner; self.poster = poster
    }
    public func bannerURL(artwork: SeriesArtwork, anime: Anime) -> URL? {
        artwork.backdrop ?? (banner ? anime.bannerImage.flatMap(URL.init(string:)) ?? anime.coverURL : nil)
    }
    public func posterURL(artwork: SeriesArtwork, anime: Anime) -> URL? {
        artwork.poster ?? (poster ? anime.coverURL : nil)
    }
    public func spotlightURL(artwork: SeriesArtwork, anime: Anime, landscape: Bool) -> URL? {
        let resolved = landscape ? artwork.backdrop ?? artwork.poster : artwork.poster ?? artwork.backdrop
        let cover = poster ? anime.coverURL : nil
        let backdrop = banner ? anime.bannerImage.flatMap(URL.init(string:)) : nil
        return SeriesArtworkQuality.spotlight(resolved ?? (landscape ? backdrop ?? cover : cover ?? backdrop))
    }
}

public struct SeriesMoreInfoPreferences: Equatable, Sendable {
    public static let storageKey = "series.more-info.layout.v1"
    public static let defaults: [SeriesDetailSection] = [.information, .related, .news, .artwork, .links]
    public static let sections = defaults + [.reviews, .trailer]
    private struct Saved: Codable { let order: [String]; let hidden: [String] }
    public private(set) var order: [SeriesDetailSection]
    public private(set) var hidden: Set<SeriesDetailSection>
    public var visible: [SeriesDetailSection] { order.filter { !hidden.contains($0) } }
    public init(saved: String = "") {
        let data = Data(saved.utf8.prefix(16_385))
        let value = data.count <= 16_384 ? (try? JSONDecoder().decode(Saved.self, from: data)) : nil
        var seen = Set<SeriesDetailSection>()
        order = (value?.order ?? []).compactMap(SeriesDetailSection.init(rawValue:)).filter {
            Self.sections.contains($0) && seen.insert($0).inserted
        }
        order += Self.sections.filter { seen.insert($0).inserted }
        hidden = value.map { Set($0.hidden.compactMap(SeriesDetailSection.init(rawValue:))).intersection(Self.sections) } ?? [.reviews, .trailer]
    }
    public var saved: String {
        let value = Saved(order: order.map(\.rawValue), hidden: hidden.map(\.rawValue).sorted())
        return (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    public mutating func setVisible(_ section: SeriesDetailSection, _ visible: Bool) {
        guard order.contains(section) else { return }
        if visible { hidden.remove(section) } else { hidden.insert(section) }
    }
    public mutating func move(fromOffsets offsets: IndexSet, toOffset target: Int) {
        guard !offsets.isEmpty, offsets.allSatisfy({ order.indices.contains($0) }), (0...order.count).contains(target) else { return }
        let moving = offsets.map { order[$0] }
        var rest = order.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        rest.insert(contentsOf: moving, at: target - offsets.filter { $0 < target }.count)
        order = rest
    }
}

public enum LibraryArtworkSizing {
    public static func gridMinimum(preferred: Double = 140, accessible: Bool) -> Double {
        let value = preferred.isFinite ? min(260, max(100, preferred)) : 140
        return accessible ? max(190, value) : value
    }
    public static func listWidth(preferred: Double, availableWidth: Double, accessible: Bool) -> Double {
        PosterLayout.listWidth(preferred: accessible ? min(100, preferred) : preferred, availableWidth: availableWidth)
    }
}
