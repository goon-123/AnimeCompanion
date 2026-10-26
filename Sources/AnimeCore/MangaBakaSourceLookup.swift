import Foundation

/// The source endpoint wraps complete catalog records without a top-level
/// source ID. Each record's AniList source identity must be checked instead.
struct MBAniListSourceLookup: Decodable {
    let series: [Series]

    struct Series: Decodable {
        let record: MangaBakaSeries
        let state: String?
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: MBKey.self)
            record = try MangaBakaSeries(from: decoder)
            state = c.mbString(.state)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: MBKey.self)
        series = try c.decode([Series].self, forKey: .series)
    }
}
