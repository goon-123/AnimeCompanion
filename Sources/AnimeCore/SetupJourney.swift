import Foundation

public enum SetupStage: Int, CaseIterable, Sendable {
    case welcome, libraries, preferences, watch, reading, ready
    public static let storageKey = "setup.guided.step.v2"
    public static let previousStorageKey = "setup.simple.step.v1"
    public var title: String {
        switch self {
        case .welcome: return "Your stories. Your space."
        case .libraries: return "Bring your libraries."
        case .preferences: return "Make yourself at home."
        case .watch: return "Set up video playback."
        case .reading: return "Add your manga sources."
        case .ready: return "Your setup at a glance."
        }
    }
    public var subtitle: String {
        switch self {
        case .welcome: return "Discover anime, manga and novels, and pick up where you left off."
        case .libraries: return "Connect what you use. These accounts sync lists; they do not provide videos or manga chapters."
        case .preferences: return "Choose your theme and colors. Change them anytime in Settings."
        case .watch: return "Highly recommended before watching: set up one source route, then choose and install a video player."
        case .reading: return "Reading manga requires an installed, enabled manga source. Your MangaBaka or AniList account alone does not supply chapters."
        case .ready: return "Check what is configured before you start. You can browse now and finish missing steps in Settings → Setup Guide."
        }
    }
    public static func restoring(savedStep: Int?, legacyStep: Int, previousStep: Int? = nil) -> Self {
        if let savedStep { return Self(rawValue: savedStep) ?? .welcome }
        // The old final page did not explain source requirements; resume there
        // at playback so an interrupted first launch sees the new guidance.
        if let previousStep {
            switch previousStep { case 0: return .welcome; case 1: return .libraries; case 2: return .preferences; case 3: return .watch; default: return .welcome }
        }
        switch legacyStep {
        case 1...2: return .libraries
        case 3...6: return .preferences
        case 7: return .watch
        default: return .welcome
        }
    }
}

public enum SetupPlaybackRoute: String, CaseIterable, Identifiable, Sendable {
    case stremio, seanime
    public static let storageKey = "setup.playback.route.v1"
    public var id: String { rawValue }
    public var label: String { self == .stremio ? "AIOStreams" : "Seanime + TorBox" }
}

/// Configuration checks, not a promise that a provider can serve every title.
public struct SourceSetupStatus: Equatable, Sendable {
    public let streamAddons: Int
    public let torrentProviders: Int
    public let torBoxConnected: Bool
    public let playerConfirmed: Bool
    public let mangaSources: Int
    public init(streamAddons: Int, torrentProviders: Int, torBoxConnected: Bool, playerConfirmed: Bool, mangaSources: Int) {
        self.streamAddons = streamAddons; self.torrentProviders = torrentProviders
        self.torBoxConnected = torBoxConnected; self.playerConfirmed = playerConfirmed; self.mangaSources = mangaSources
    }
    public var stremioConfigured: Bool { streamAddons > 0 }
    public var seanimeConfigured: Bool { torrentProviders > 0 && torBoxConnected }
    public var videoConfigured: Bool { (stremioConfigured || seanimeConfigured) && playerConfirmed }
    public var readingConfigured: Bool { mangaSources > 0 }
    public func configured(_ route: SetupPlaybackRoute) -> Bool { route == .stremio ? stremioConfigured : seanimeConfigured }
}
