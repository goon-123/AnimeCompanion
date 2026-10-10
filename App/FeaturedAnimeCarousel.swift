import SwiftUI
import AnimeCore

struct FeaturedAnimeCarousel: View {
    let anime: [Anime]
    let height: CGFloat
    let topInset: CGFloat
    @Binding var background: PosterAccent
    @State private var selected = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var active: Anime? { anime.indices.contains(selected) ? anime[selected] : anime.first }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selected) {
                ForEach(Array(anime.enumerated()), id: \.element.id) { index, item in
                    FeaturedAnimePanel(anime: item, topInset: topInset,
                        background: PosterAccent(hex: item.coverImage?.color)?.backdrop ?? background)
                        .tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: height)
                .accessibilityIdentifier("explore-featured-carousel")
            HStack(spacing: 0) {
                ForEach(anime.indices, id: \.self) { index in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { selected = index }
                    } label: {
                        Circle().fill(selected == index ? Color.white : Color.white.opacity(0.35))
                            .frame(width: 7, height: 7).frame(width: 35, height: 40)
                    }.buttonStyle(.plain).accessibilityLabel("Featured title \(index + 1) of \(anime.count)")
                        .accessibilityValue(selected == index ? "Selected" : "")
                        .accessibilityIdentifier("featured-page-\(index)")
                }
            }
        }.frame(maxWidth: .infinity)
            .onChange(of: anime.map(\.id)) { _, _ in selected = min(selected, max(0, anime.count - 1)) }
            .task(id: active) {
                guard let active else { return }
                let accent = await PosterColor.accent(for: active)
                guard !Task.isCancelled, self.active?.id == active.id else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { background = accent.backdrop }
            }
    }
}

private struct FeaturedAnimePanel: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let anime: Anime
    let topInset: CGFloat
    let background: PosterAccent
    @State private var preview: AnimeImagePreview?

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height * 1.2
            ZStack(alignment: .bottomLeading) {
                artwork(width: geometry.size.width, height: geometry.size.height, wide: wide)
                LinearGradient(stops: [.init(color: .black.opacity(0.34), location: 0), .init(color: .clear, location: 0.28),
                    .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
                LinearGradient(stops: [.init(color: .clear, location: 0.30), .init(color: background.color.opacity(0.15), location: 0.46),
                    .init(color: background.color.opacity(0.80), location: 0.73), .init(color: Theme.background, location: 1)],
                    startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
                information.frame(maxWidth: wide ? 740 : .infinity, alignment: .leading)
                    .padding(.horizontal, geometry.size.width >= 700 ? 32 : 20).padding(.bottom, 6)
                VStack {
                    HStack {
                        Spacer()
                        if let url = anime.coverURL {
                            Button { preview = AnimeImagePreview(url: url, title: anime.displayTitle) } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.subheadline.weight(.semibold))
                                    .frame(width: 44, height: 44).silverGlass(in: Circle())
                            }.buttonStyle(.plain).accessibilityLabel("Expand featured artwork")
                                .accessibilityIdentifier("featured-expand-\(anime.id)")
                        }
                    }
                    Spacer()
                }.padding(.horizontal, 20).padding(.top, max(90, topInset + 12))
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.foregroundStyle(.white)
            .fullScreenCover(item: $preview) { AnimeImageViewer(preview: $0) }
    }
    private func artwork(width: CGFloat, height: CGFloat, wide: Bool) -> some View {
        let banner = anime.bannerImage.flatMap(URL.init(string:))
        let url = wide ? (banner ?? anime.coverURL) : anime.coverURL
        return AsyncImage(url: url) { image in image.resizable().scaledToFill() }
            placeholder: { background.color }
            .frame(width: width, height: height, alignment: wide ? .center : .top).clipped().contentShape(Rectangle())
            .onTapGesture { if let url = anime.coverURL { preview = AnimeImagePreview(url: url, title: anime.displayTitle) } }
            .accessibilityHidden(true)
    }
    private var information: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Text(anime.displayTitle).font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .lineLimit(textSize.isAccessibilitySize ? 4 : 2).shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                    .accessibilityIdentifier("featured-title-\(anime.id)")
                DiscoveryAiringDot(anime: anime, identifierPrefix: "featured").padding(.top, 12)
            }
            HStack(spacing: 12) {
                if let score = anime.averageScore { Label("\(Double(score) / 10, specifier: "%.1f")", systemImage: "star.fill").foregroundStyle(.yellow) }
                if let year = anime.seasonYear { Text(String(year)) }
                Text((anime.format ?? "Anime").replacingOccurrences(of: "_", with: " "))
            }.font(.caption.weight(.semibold))
            Text((anime.genres ?? []).joined(separator: " · ")).font(.caption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("featured-genres-\(anime.id)")
            DiscoveryIndicators(anime: anime, identifierPrefix: "featured")
            Text(anime.synopsis).font(.subheadline).lineLimit(textSize.isAccessibilitySize ? 3 : 2)
            NavigationLink(value: AnimeRoute(id: anime.id)) {
                Label("View details", systemImage: "info.circle").font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20).frame(minHeight: 44).silverGlass(in: Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("featured-details-\(anime.id)")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

