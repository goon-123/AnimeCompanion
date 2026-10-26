#if DEBUG
import Foundation
import AnimeCore

/// Owned profiles for offline native UI journeys. These are not real sessions.
enum AccountSwitcherPreview {
    static var active: Bool { ProcessInfo.processInfo.arguments.contains("--ui-account-switcher-preview") }
    static var aniListConnected: Bool { !ProcessInfo.processInfo.arguments.contains("--ui-account-anilist-disconnected") }
    static var mangaBakaConnected: Bool { !ProcessInfo.processInfo.arguments.contains("--ui-account-mangabaka-disconnected") }
    static func viewer() throws -> Viewer {
        try JSONDecoder().decode(Viewer.self, from: Data(#"{"id":12345,"name":"HarborWatcher"}"#.utf8))
    }
    static func profile() throws -> MangaBakaProfile {
        try JSONDecoder().decode(MangaBakaProfile.self, from: Data(#"{"id":"owned-reader","nickname":"LanternReader","rating_steps":1}"#.utf8))
    }
}
#endif
