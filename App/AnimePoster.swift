import SwiftUI
import AnimeCore

enum AnimePosterBadgeStyle: Equatable {
    case standard, compact, none
}

/// All listing artwork shares the Library badge layout. The parent owns sizing,
/// navigation and context menus; this view never starts its own metadata request.
struct AnimePoster: View {
    let anime: Anime
    var dub: LibraryDubProgress? = nil
    var identifierPrefix = "explore"
    var cornerRadius: CGFloat = 14
    var artworkIdentifierPrefix: String? = nil
    var badgeStyle: AnimePosterBadgeStyle = .compact

    var body: some View {
        AnimeRowArtwork(anime: anime, identifierPrefix: artworkIdentifierPrefix ?? identifierPrefix)
            .overlay {
                if badgeStyle != .none {
                    AnimePosterBadges(anime: anime, dub: dub, identifierPrefix: identifierPrefix, style: badgeStyle)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .contentShape(Rectangle())
    }
}

/// Also used on the featured artwork, which can be a landscape banner. All
/// overlays ignore touches so poster taps and long presses reach their owner.
struct AnimePosterBadges: View {
    @EnvironmentObject private var dubs: ExploreDubStore
    let anime: Anime
    var dub: LibraryDubProgress? = nil
    var identifierPrefix = "explore"
    var style: AnimePosterBadgeStyle = .compact

    private var hasDub: Bool { (dubs.progress(for: anime) ?? dub)?.hasAvailableDub == true }

    var body: some View {
        GeometryReader { geometry in
            let metrics = AnimePosterMetrics(width: geometry.size.width, style: style)
            Color.clear
                .overlay(alignment: .topLeading) {
                    DiscoveryAiringDot(anime: anime, overArtwork: true, identifierPrefix: identifierPrefix,
                        symbolSize: metrics.dotSize, artworkPadding: metrics.dotPadding)
                        .padding(metrics.airingInset)
                }
                .overlay(alignment: .bottomTrailing) {
                    VStack(alignment: .trailing, spacing: metrics.spacing) {
                        if hasDub {
                            Text("DUB").font(.system(size: metrics.dubSize, weight: .heavy))
                                .tracking(metrics.letterSpacing).foregroundStyle(Color.mint)
                                .padding(.horizontal, metrics.horizontalPadding).padding(.vertical, metrics.verticalPadding)
                                .background(.black.opacity(0.80), in: RoundedRectangle(cornerRadius: metrics.radius))
                                .accessibilityLabel("English dub available")
                                .accessibilityHint("Open series details for dubbed episode counts and schedules")
                                .accessibilityIdentifier("\(identifierPrefix)-dub-\(anime.id)")
                        }
                        if let score = anime.averageScore {
                            HStack(spacing: metrics.spacing) {
                                Image(systemName: "star.fill").foregroundStyle(Color.yellow)
                                Text("\(Double(score) / 10, specifier: "%.1f")").foregroundStyle(Color.white)
                            }.font(.system(size: metrics.ratingSize, weight: .semibold)).monospacedDigit()
                                .padding(.horizontal, metrics.horizontalPadding).padding(.vertical, metrics.verticalPadding)
                                .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: metrics.radius))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text("AniList rating \(Double(score) / 10, specifier: "%.1f") out of 10"))
                                .accessibilityIdentifier("\(identifierPrefix)-rating-\(anime.id)")
                        }
                    }.fixedSize().padding(metrics.inset)
                }
        }.allowsHitTesting(false)
    }
}

/// Library grids retain their reference sizes. Other listings use less artwork
/// for rating/dub metadata; schedule artwork omits the overlay altogether.
private struct AnimePosterMetrics {
    let width: CGFloat
    let style: AnimePosterBadgeStyle
    private var miniature: Bool { width < 60 }
    private var narrow: Bool { width < 115 }
    private var compact: Bool { style == .compact }
    var airingInset: CGFloat { miniature ? 3 : narrow ? 6 : 8 }
    var inset: CGFloat { miniature ? 3 : compact ? 5 : airingInset }
    var spacing: CGFloat { miniature ? 2 : compact ? 3 : narrow ? 4 : 6 }
    var horizontalPadding: CGFloat { miniature ? 3 : compact ? 4 : narrow ? 5 : 7 }
    var verticalPadding: CGFloat { miniature ? 3 : compact ? 2.5 : 5 }
    var radius: CGFloat { miniature ? 4 : compact ? 5 : 6 }
    var dubSize: CGFloat { miniature ? 7 : compact ? 8 : narrow ? 9 : 10 }
    var ratingSize: CGFloat { miniature ? 8 : compact ? 9 : narrow ? 10 : 12 }
    var letterSpacing: CGFloat { miniature ? 0.4 : compact ? 0.5 : 0.8 }
    var dotSize: CGFloat { miniature ? 6 : 9 }
    var dotPadding: CGFloat { miniature ? 3 : 5 }
}
