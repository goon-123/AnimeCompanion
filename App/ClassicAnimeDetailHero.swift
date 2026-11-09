import SwiftUI
import AnimeCore

struct ClassicAnimeDetailHero: View {
    @EnvironmentObject private var dubs: ExploreDubStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var textSize
    let anime: Anime
    let expand: (URL) -> Void
    private var bannerHeight: CGFloat { sizeClass == .regular ? 240 : 180 }
    private var posterWidth: CGFloat { sizeClass == .regular ? 152 : 112 }
    private var artworkURL: URL? { anime.bannerImage.flatMap(URL.init(string:)) ?? anime.coverURL }
    private var accent: Color { (PosterAccent(hex: anime.coverImage?.color)?.backdrop ?? PosterAccent.fallback.backdrop).color }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) { poster; information }
            } else {
                HStack(alignment: .bottom, spacing: 18) { poster.fixedSize(); information }
            }
            AnimeGenres(anime: anime).accessibilityIdentifier("detail-genres-\(anime.id)")
        }.padding(.horizontal, 18).padding(.top, bannerHeight - posterWidth * 0.72).padding(.bottom, 16)
            .readableContent(width: 940).frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .top) {
                GeometryReader { geometry in
                    ZStack(alignment: .top) {
                        Theme.background
                        Button { if let artworkURL { expand(artworkURL) } } label: {
                            ArtworkImage(url: artworkURL, pointSize: max(geometry.size.width, bannerHeight)) { image in image.resizable().scaledToFill() } placeholder: { accent }
                                .frame(width: geometry.size.width, height: bannerHeight).clipped()
                        }.buttonStyle(.plain).disabled(artworkURL == nil)
                            .accessibilityLabel("Expand anime banner").accessibilityIdentifier("expand-anime-banner")
                        LinearGradient(stops: [.init(color: .black.opacity(0.08), location: 0),
                            .init(color: Theme.background.opacity(0.12), location: 0.30),
                            .init(color: Theme.background.opacity(0.88), location: 0.73),
                            .init(color: Theme.background, location: 1)], startPoint: .top, endPoint: .bottom)
                            .frame(height: bannerHeight + 80).allowsHitTesting(false)
                    }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
            }
    }
    private var poster: some View {
        Button { if let url = anime.coverURL { expand(url) } } label: {
            AnimeCover(anime: anime, width: posterWidth, cornerRadius: 12)
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.16), lineWidth: 1) }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption2)
                        .foregroundStyle(.white)
                        .padding(7).background(.black.opacity(0.70), in: Circle()).padding(6)
                }.shadow(color: .black.opacity(0.45), radius: 15, y: 6)
        }.buttonStyle(.plain).disabled(anime.coverURL == nil)
            .accessibilityLabel("Expand anime cover").accessibilityIdentifier("expand-anime-cover")
    }
    private var information: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if anime.isCurrentlyAiring { Circle().fill(.green).frame(width: 6, height: 6).accessibilityHidden(true) }
                Text(statusLabel).font(.caption.weight(.semibold)).foregroundStyle(anime.isCurrentlyAiring ? Color.green : Color.secondary)
                    .accessibilityIdentifier("detail-release-status")
            }
            Text(anime.displayTitle).font(sizeClass == .regular ? .title.bold() : .title2.bold())
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("detail-title")
            Text([anime.season.map { $0.label + (anime.seasonYear.map { " \($0)" } ?? "") },
                  anime.format?.replacingOccurrences(of: "_", with: " ")].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            if let score = anime.averageScore {
                Label("AniList · \(Double(score) / 10, specifier: "%.1f")", systemImage: "star.fill")
                    .font(.caption.bold()).foregroundStyle(Theme.highlight)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(Theme.highlight.opacity(0.10), in: Capsule())
            }
            DubStatusBadge(anime: anime, progress: dubs.progress(for: anime))
                .accessibilityIdentifier("detail-dub-summary")
        }.frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
    }
    private var statusLabel: String {
        switch anime.status {
        case "RELEASING": return "Airing now"
        case "FINISHED": return "Finished"
        case "NOT_YET_RELEASED": return "Upcoming"
        case "HIATUS": return "On hiatus"
        case "CANCELLED": return "Cancelled"
        default: return "Anime"
        }
    }
}

