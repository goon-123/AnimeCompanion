import Foundation

extension Anime {
    /// A scheduled premiere is not evidence that the original broadcast is airing.
    public var isCurrentlyAiring: Bool { status == "RELEASING" }
}

/// Short discovery labels describe availability, not an inferred episode count.
public enum DiscoveryDubStatus: Sendable, Equatable {
    case available, partial, estimated, announced, unconfirmed, notReported, unknown

    public var label: String {
        switch self {
        case .available: return "Dub available"
        case .partial: return "Partial dub"
        case .estimated: return "Dub estimated"
        case .announced: return "Dub announced"
        case .unconfirmed: return "Dub unconfirmed"
        case .notReported: return "No dub reported"
        case .unknown: return "Dub unknown"
        }
    }
    public var tone: DubStatusTone {
        switch self {
        case .available, .partial: return .available
        case .estimated, .unconfirmed: return .estimated
        case .announced: return .announced
        case .notReported, .unknown: return .neutral
        }
    }
}

extension LibraryDubProgress {
    public var discoveryStatus: DiscoveryDubStatus {
        if availability == .partial { return .partial }
        if confidence == .reported && (released ?? 0) > 0 { return .available }
        if announced && released == nil { return .announced }
        if availability == .dubbed { return .available }
        if confidence == .estimated && (released ?? 0) > 0 { return .estimated }
        if announced { return .announced }
        if (agreeingSources ?? 0) > 0 { return .unconfirmed }
        return availability == .notReported ? .notReported : .unknown
    }
}
