import Foundation

public enum SetupStage: Int, CaseIterable, Sendable {
    case welcome, libraries, preferences, ready
    public static let storageKey = "setup.simple.step.v1"
    public var title: String {
        switch self {
        case .welcome: return "Your stories. Your space."
        case .libraries: return "Bring your libraries."
        case .preferences: return "Make yourself at home."
        case .ready: return "Ready when you are."
        }
    }
    public var subtitle: String {
        switch self {
        case .welcome: return "Discover anime, manga and novels, and pick up where you left off."
        case .libraries: return "Connect what you use. Both accounts are optional."
        case .preferences: return "A couple of choices to get you started. Change them anytime in Settings."
        case .ready: return "Explore now. Add reading sources and playback when you need them."
        }
    }
    public static func restoring(savedStep: Int?, legacyStep: Int) -> Self {
        if let savedStep { return Self(rawValue: savedStep) ?? .welcome }
        switch legacyStep {
        case 1...2: return .libraries
        case 3...6: return .preferences
        case 7: return .ready
        default: return .welcome
        }
    }
}
