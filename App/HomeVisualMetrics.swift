import SwiftUI
import AnimeCore

enum HomeArtworkSize: String, CaseIterable, Identifiable {
    case standard, large, extraLarge
    static let storageKey = "home.ipadArtworkSize.v1"
    var id: String { rawValue }
    var title: String {
        switch self { case .standard: return "Standard"; case .large: return "Large"; case .extraLarge: return "Extra large" }
    }
    var factor: CGFloat {
        switch self { case .standard: return 0; case .large: return 1; case .extraLarge: return 1.3 }
    }
}

/// The Home column supplies its actual width, including Split View and Stage Manager.
/// Narrow panes retain compact cards; tablet artwork grows without scaling the whole UI.
struct HomeVisualMetrics {
    private let strength: CGFloat
    init(isPad: Bool = false, availableWidth: CGFloat = 0, artworkSize: HomeArtworkSize = .large) {
        strength = isPad ? min(1, max(0, (availableWidth - 380) / 300)) * artworkSize.factor : 0
    }
    func value(_ compact: CGFloat, _ enlarged: CGFloat) -> CGFloat { compact + (enlarged - compact) * strength }
    var enlarged: Bool { strength >= 0.5 }
    var iconFont: Font { enlarged ? .largeTitle : .title3 }
    var actionIconFont: Font { enlarged ? .title2.weight(.semibold) : .subheadline.weight(.semibold) }
    var circleIconFont: Font { enlarged ? .largeTitle : .title2 }
    var actionTextFont: Font { enlarged ? .subheadline.weight(.semibold) : .caption.weight(.semibold) }
    var toolbarIconFont: Font { enlarged ? .title2 : .body }
    var weeklyPosterLimit: CGFloat { value(72, 160) }
    var watchingCover: CGFloat { value(80, 112) }
    var readingCover: CGFloat { value(44, 80) }
    var upcomingCover: CGFloat { value(40, 76) }
    var rowCover: CGFloat { value(44, 80) }
    var communityCover: CGFloat { value(56, 84) }
    var bannerCover: CGFloat { value(56, 84) }
    var bannerHeight: CGFloat { value(210, 280) }
    var newsBannerHeight: CGFloat { value(160, 240) }
    var animeBannerLimit: CGFloat { value(620, 760) }
    var newsBannerLimit: CGFloat { value(550, 680) }
    var watchingCardLimit: CGFloat { value(400, 540) }
    var gridMinimum: CGFloat { value(270, 340) }
    var shortcutMinimum: CGFloat { value(145, 210) }
}

private struct HomeVisualMetricsKey: EnvironmentKey {
    static let defaultValue = HomeVisualMetrics()
}

extension EnvironmentValues {
    var homeVisuals: HomeVisualMetrics {
        get { self[HomeVisualMetricsKey.self] }
        set { self[HomeVisualMetricsKey.self] = newValue }
    }
}

private struct HomeWidgetLayoutKey: EnvironmentKey { static let defaultValue = HomeWidgetLayout.banner }
extension EnvironmentValues {
    var homeWidgetLayout: HomeWidgetLayout {
        get { self[HomeWidgetLayoutKey.self] }
        set { self[HomeWidgetLayoutKey.self] = newValue }
    }
}
