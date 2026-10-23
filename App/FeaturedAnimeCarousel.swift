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
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var textSize
    let anime: Anime
    let topInset: CGFloat
    let background: PosterAccent
    @State private var showTracking = false
    @State private var showSettings = false
    @State private var showPlayback = false

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
                    .padding(.horizontal, geometry.size.width >= 700 ? 32 : 20).padding(.bottom, 18)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.foregroundStyle(.white)
            .sheet(isPresented: $showTracking) { TrackingEditorView(anime: anime, entry: store.entry(for: anime.id)) }
            .appSettingsSheet(isPresented: $showSettings)
            .sheet(isPresented: $showPlayback) { WatchAnimeView(anime: anime) }
    }
    private func artwork(width: CGFloat, height: CGFloat, wide: Bool) -> some View {
        let banner = anime.bannerImage.flatMap(URL.init(string:))
        let url = wide ? (banner ?? anime.coverURL) : anime.coverURL
        return AnimeLink(id: anime.id) {
            ArtworkImage(url: url, pointSize: max(width, height)) { image in image.resizable().scaledToFill() }
                placeholder: { background.color }
                .frame(width: width, height: height, alignment: wide ? .center : .top).clipped().contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("View \(anime.displayTitle)")
            .accessibilityHint("Opens series details").accessibilityIdentifier("featured-poster-\(anime.id)")
    }
    private var information: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Text(anime.displayTitle).font(.system(.title, design: .rounded, weight: .bold))
                    .lineLimit(textSize.isAccessibilitySize ? 4 : 2).shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                    .accessibilityIdentifier("featured-title-\(anime.id)")
                DiscoveryAiringDot(anime: anime, identifierPrefix: "featured").padding(.top, 12)
            }
            HStack(spacing: 12) {
                if let score = anime.averageScore { Label("\(Double(score) / 10, specifier: "%.1f")", systemImage: "star.fill").foregroundStyle(.yellow) }
                if let year = anime.seasonYear { Text(String(year)) }
                Text((anime.format ?? "Anime").replacingOccurrences(of: "_", with: " "))
            }.font(.caption.weight(.semibold))
            AnimeGenres(anime: anime).accessibilityIdentifier("featured-genres-\(anime.id)")
            DiscoveryIndicators(anime: anime, identifierPrefix: "featured")
            Text(anime.synopsis).font(.subheadline).lineLimit(textSize.isAccessibilitySize ? 3 : 2)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { watchAction; detailsAction; libraryAction }
                VStack(alignment: .leading, spacing: 8) { watchAction; HStack { detailsAction; libraryAction } }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var watchAction: some View {
        Button { showPlayback = true } label: {
            Label("Watch", systemImage: "play.fill").font(.headline)
                .padding(.horizontal, 24).frame(minHeight: 48)
                .background(.white, in: Capsule()).foregroundStyle(.black)
        }.buttonStyle(.plain).accessibilityIdentifier("featured-watch-\(anime.id)")
    }
    private var detailsAction: some View {
            AnimeLink(id: anime.id) {
                Image(systemName: "info.circle").font(.headline).frame(width: 48, height: 48).silverGlass(in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("View details for \(anime.displayTitle)").accessibilityIdentifier("featured-details-\(anime.id)")
    }
    private var libraryAction: some View {
        Button {
            if store.isSignedIn { showTracking = true } else { showSettings = true }
        } label: {
            Image(systemName: store.entry(for: anime.id) == nil ? "plus" : "checkmark")
                .font(.headline).frame(width: 48, height: 48).silverGlass(in: Circle())
        }.buttonStyle(.plain).accessibilityLabel(store.entry(for: anime.id) == nil ? "Add \(anime.displayTitle) to Library" : "Edit Library tracking for \(anime.displayTitle)")
            .disabled(store.isSignedIn && store.loadingLibrary)
            .accessibilityIdentifier("featured-add-library-\(anime.id)")
    }
}

