import Foundation

/// The source endpoint returns MangaBaka identities; hydrate them through the
/// normal detail client so content settings and the complete metadata apply.
struct MBAniListSourceLookup: Decodable {
    let id: Int
    let series: [Series]

    struct Series: Decodable {
        let id: Int
        let state: String?
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: MBKey.self)
            guard let id = c.mbInt(.id), id > 0 else { throw MangaBakaError.invalidResponse }
            self.id = id
            state = c.mbString(.state)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: MBKey.self)
        guard let id = c.mbInt(.id), id > 0 else { throw MangaBakaError.invalidResponse }
        self.id = id
        series = try c.decode([Series].self, forKey: .series)
    }
}
