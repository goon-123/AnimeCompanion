import Foundation

public enum TorrentSort: String, CaseIterable, Identifiable, Sendable {
    case seeders, name, provider
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .seeders: return "Highest seeders"
        case .name: return "Release name"
        case .provider: return "Provider order"
        }
    }

    /// Sort presentation values without changing their provider/file identities.
    /// Use cached audio evidence; subtitles alone never establish English audio.
    /// English audio stays first for every order. Ties retain incoming order.
    public func sorted<Value>(_ values: [Value], torrent: (Value) -> SeanimeTorrent,
                              audio: (Value) -> StreamAudioInfo) -> [Value] {
        let ranked = values.enumerated().map {
            (offset: $0.offset, value: $0.element, torrent: torrent($0.element), english: audio($0.element).english)
        }
        return ranked.sorted { lhs, rhs in
            if lhs.english != rhs.english { return lhs.english }
            switch self {
            case .seeders:
                // Missing/invalid counts follow even a known zero-seeder result.
                let left = max(lhs.torrent.seeders ?? -1, -1)
                let right = max(rhs.torrent.seeders ?? -1, -1)
                if left != right { return left > right }
            case .name:
                let order = lhs.torrent.name.localizedStandardCompare(rhs.torrent.name)
                if order != .orderedSame { return order == .orderedAscending }
            case .provider: break
            }
            return lhs.offset < rhs.offset
        }.map(\.value)
    }
}
