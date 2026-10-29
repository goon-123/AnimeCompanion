import SwiftUI
import AnimeCore

/// All listing artwork shares the Library badge layout. The parent owns sizing,
/// navigation and context menus; this view never starts its own metadata request.
struct AnimePoster: View {
    let anime: Anime
    var dub: LibraryDubProgress? = nil
    var identifierPrefix = "explore"
    var cornerRadius: CGFloat = 14
    var artworkIdentifierPrefix: String? = nil

    var body: some View {
        AnimeRowArtwork(anime: anime, identifierPrefix: artworkIdentifierPrefix ?? identifierPrefix)
            .overlay {
                AnimePosterBadges(anime: anime, dub: dub, identifierPrefix: identifierPrefix)
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

    private var hasDub: Bool { (dubs.progress(for: anime) ?? dub)?.hasAvailableDub == true }

    var body: some View {
        GeometryReader { geometry in
            let metrics = AnimePosterMetrics(width: geometry.size.width)
            Color.clear
                .overlay(alignment: .topLeading) {
                    DiscoveryAiringDot(anime: anime, overArtwork: true, identifierPrefix: identifierPrefix,
                        symbolSize: metrics.dotSize, artworkPadding: metrics.dotPadding)
                        .padding(metrics.inset)
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

/// Keep both badges legible and within even the 40-point agenda thumbnails.
/// Standard posters retain the Library reference's original sizes and spacing.
private struct AnimePosterMetrics {
    let width: CGFloat
    private var miniature: Bool { width < 60 }
    private var compact: Bool { width < 115 }
    var inset: CGFloat { miniature ? 3 : compact ? 6 : 8 }
    var spacing: CGFloat { miniature ? 2 : compact ? 4 : 6 }
    var horizontalPadding: CGFloat { miniature ? 3 : compact ? 5 : 7 }
    var verticalPadding: CGFloat { miniature ? 3 : 5 }
    var radius: CGFloat { miniature ? 4 : 6 }
    var dubSize: CGFloat { miniature ? 7 : compact ? 9 : 10 }
    var ratingSize: CGFloat { miniature ? 8 : compact ? 10 : 12 }
    var letterSpacing: CGFloat { miniature ? 0.4 : 0.8 }
    var dotSize: CGFloat { miniature ? 6 : 9 }
    var dotPadding: CGFloat { miniature ? 3 : 5 }
}
