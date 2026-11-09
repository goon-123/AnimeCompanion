import Foundation

public enum ScreenPresentation: String, CaseIterable, Identifiable, Sendable {
    case cinematic, original
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public init(preference: String?) { self = preference.flatMap(Self.init(rawValue:)) ?? .cinematic }
}

public enum ScreenPresentationScope: String, CaseIterable, Identifiable, Sendable {
    case home, classicExplore, mixedExplore, discoveryExplore
    public var id: String { rawValue }
    public var storageKey: String { "screen.presentation.\(rawValue).v1" }
    public var title: String {
        switch self {
        case .home: return "Home"
        case .classicExplore: return "Classic sections"
        case .mixedExplore: return "Mixed poster grid"
        case .discoveryExplore: return "Discovery shelves"
        }
    }
}

extension ExploreDesign {
    public var presentationScope: ScreenPresentationScope {
        switch self {
        case .classic: return .classicExplore
        case .posterGrid: return .mixedExplore
        case .discover: return .discoveryExplore
        }
    }
}
