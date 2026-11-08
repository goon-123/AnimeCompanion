import Foundation

public struct AnimeStudioCollection: Codable, Identifiable, Sendable {
    public let studio: Studio
    public let anime: [Anime]
    public var id: Int { studio.id }
    public init(studio: Studio, anime: [Anime]) { self.studio = studio; self.anime = anime }
    public static let featured: [Studio] = [
        Studio(id: 569, name: "MAPPA"), Studio(id: 43, name: "ufotable"),
        Studio(id: 34, name: "WIT STUDIO"), Studio(id: 2, name: "Kyoto Animation"),
        Studio(id: 4, name: "Bones"), Studio(id: 11, name: "Madhouse"),
        Studio(id: 6222, name: "CloverWorks"), Studio(id: 803, name: "TRIGGER")
    ]
}
