import SwiftUI
import AnimeCore

private struct PreparedSpotlightArtwork: Sendable {
    let artwork: SeriesArtwork
    let logo: ArtworkBitmap?
}

struct FeaturedAnimeCarousel: View {
    let anime: [Anime]
    let height: CGFloat
    let topInset: CGFloat
    @Binding var background: PosterAccent
    @EnvironmentObject private var store: AppStore
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var paging = false
    @State private var selectedID: Int?
    @State private var visibleIDs = Set<Int>()
    @State private var titles = SpotlightTitlePresentation()
    @State private var prepared: [Int: PreparedSpotlightArtwork] = [:]
    @State private var presented: [Int: PreparedSpotlightArtwork] = [:]
    private var items: [Anime] { Array(anime.prefix(5)) }
    private var ids: Set<Int> { Set(items.map(\.id)) }
    private var active: Anime? { items.first { $0.id == selectedID } ?? items.first }
    private var protectedIDs: Set<Int> { paging ? ids : visibleIDs.union(active.map { [$0.id] } ?? []) }
    private var pixels: Int { ArtworkSizing.pixelLimit(points: 340, scale: Double(displayScale)) }

    var body: some View {
        GeometryReader { viewport in
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(items) { item in
                            FeaturedAnimePanel(anime: item, topInset: topInset,
                                background: PosterAccent(hex: item.coverImage?.color)?.backdrop ?? background,
                                artwork: presented[item.id]?.artwork ?? SeriesArtwork(),
                                logo: presented[item.id]?.logo, titlePresentation: titles.title(for: item.id))
                                .frame(width: viewport.size.width, height: height).id(item.id)
                                .onGeometryChange(for: Bool.self) { page in
                                    let overlap = page.frame(in: .global).intersection(viewport.frame(in: .global))
                                    return !overlap.isNull && overlap.width > 1 && overlap.height > 1
                                } action: { visible in
                                    if visible { visibleIDs.insert(item.id) } else { visibleIDs.remove(item.id) }
                                    revealOffscreen()
                                }
                        }
                    }.scrollTargetLayout()
                }.scrollTargetBehavior(.paging).scrollPosition(id: $selectedID)
                    .modifier(SpotlightScrollActivity(paging: $paging))
                HStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button { withAnimation(AppMotion.page(reduceMotion)) { selectedID = item.id } } label: {
                            Circle().fill(active?.id == item.id ? Color.white : .white.opacity(0.35))
                                .frame(width: 7, height: 7).frame(width: 35, height: 40)
                        }.buttonStyle(.plain).accessibilityLabel("Featured title \(index + 1) of \(items.count)")
                            .accessibilityValue(active?.id == item.id ? "Selected" : "")
                            .accessibilityIdentifier("featured-page-\(index)")
                    }
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("explore-featured-carousel")
        }.frame(height: height + 40)
            .onChange(of: items.map(\.id)) { _, values in
                visibleIDs.formIntersection(values)
                titles.retain(Set(values)); prepared = prepared.filter { values.contains($0.key) }
                presented = presented.filter { values.contains($0.key) }
                if !values.contains(selectedID ?? -1) { selectedID = values.first }
            }
            .onChange(of: selectedID) { _, _ in revealOffscreen() }
            .onChange(of: paging) { _, active in if !active { revealOffscreen() } }
            .onDisappear {
                paging = false
                visibleIDs = []
                titles.leaveViewport()
                for (id, value) in prepared { presented[id] = value }
            }
            .task(id: "\(items.map(\.id))-\(pixels)") { await prepareLogos() }
            .task(id: active) {
                guard let active else { return }
                let accent = await PosterColor.accent(for: active)
                guard !Task.isCancelled, self.active?.id == active.id else { return }
                withAnimation(AppMotion.content(reduceMotion)) { background = accent.backdrop }
            }
    }
    private func revealOffscreen() {
        titles.revealOffscreen(protected: protectedIDs)
        for (id, value) in prepared where !protectedIDs.contains(id) { presented[id] = value }
    }
    @MainActor private func prepareLogos() async {
        let lineup = items, api = store.seriesArtwork, pixelCount = pixels
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-") }) {
            for item in lineup { titles.checkedCache(for: item.id, hasLogo: false) }
            return
        }
        #endif
        // A cache-only probe reserves the logo slot; a cached logo never flashes text.
        for item in lineup {
            let artwork = await api.cachedArtwork(for: item) ?? SeriesArtwork()
            let bitmap: ArtworkBitmap?
            if let url = artwork.logo { bitmap = await ArtworkPipeline.shared.cachedImage(at: url, pixels: pixelCount) }
            else { bitmap = nil }
            guard !Task.isCancelled, ids.contains(item.id) else { return }
            if let bitmap {
                let value = PreparedSpotlightArtwork(artwork: artwork, logo: bitmap)
                prepared[item.id] = value; presented[item.id] = value
            }
            titles.checkedCache(for: item.id, hasLogo: bitmap != nil)
        }
        await withTaskGroup(of: (Int, PreparedSpotlightArtwork).self) { group in
            var remaining = lineup.makeIterator()
            for _ in 0..<2 {
                if let item = remaining.next() { group.addTask { await prepareSpotlightLogo(item, api: api, pixels: pixelCount) } }
            }
            for await (id, value) in group {
                guard !Task.isCancelled else { group.cancelAll(); return }
                if ids.contains(id) {
                    let previous = prepared[id]
                    let resolved = PreparedSpotlightArtwork(artwork: value.artwork.fillingMissing(with: previous?.artwork ?? SeriesArtwork()),
                        logo: value.logo ?? previous?.logo)
                    prepared[id] = resolved
                    if resolved.logo != nil { titles.preparedLogo(for: id, protected: protectedIDs) }
                    revealOffscreen()
                }
                if let item = remaining.next() { group.addTask { await prepareSpotlightLogo(item, api: api, pixels: pixelCount) } }
            }
        }
    }
}

/// Observe the native pager without installing a drag recognizer over its image.
/// Vertical drags remain available to Explore's enclosing scroll view.
private struct SpotlightScrollActivity: ViewModifier {
    @Binding var paging: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in paging = phase != .idle }
        } else {
            // On iOS 17, page geometry and selection still protect visible titles.
            content
        }
    }
}

private func prepareSpotlightLogo(_ anime: Anime, api: SeriesArtworkClient, pixels: Int) async -> (Int, PreparedSpotlightArtwork) {
    let artwork = await api.logoArtwork(for: anime)
    let bitmap: ArtworkBitmap?
    if let url = artwork.logo { bitmap = try? await ArtworkPipeline.shared.image(at: url, pixels: pixels) }
    else { bitmap = nil }
    return (anime.id, PreparedSpotlightArtwork(artwork: artwork, logo: bitmap))
}

private struct FeaturedAnimePanel: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.displayScale) private var displayScale
    let anime: Anime
    let topInset: CGFloat
    let background: PosterAccent
    let artwork: SeriesArtwork
    let logo: ArtworkBitmap?
    let titlePresentation: SpotlightTitlePresentation.Title
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
                    .init(color: background.color.opacity(0.80), location: 0.73), .init(color: .black, location: 1)],
                    startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
                AnimePosterBadges(anime: anime, identifierPrefix: "featured")
                    .padding(.top, topInset).padding(.bottom, 10)
                information(wide: wide).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, geometry.size.width >= 700 ? 32 : 20).padding(.bottom, 18)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.foregroundStyle(.white)
            .sheet(isPresented: $showTracking) { TrackingEditorView(anime: anime, entry: store.entry(for: anime.id)) }
            .appSettingsSheet(isPresented: $showSettings)
            .sheet(isPresented: $showPlayback) { WatchAnimeView(anime: anime) }
    }
    private func artwork(width: CGFloat, height: CGFloat, wide: Bool) -> some View {
        let banner = anime.bannerImage.flatMap(URL.init(string:))
        let url = wide ? (artwork.backdrop ?? banner ?? anime.coverURL) : anime.coverURL
        return AnimeLink(id: anime.id) {
            ArtworkImage(url: url, pointSize: max(width, height)) { image in image.resizable().scaledToFill() }
                placeholder: { background.color }
                .frame(width: width, height: height, alignment: wide ? .center : .top).clipped().contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("View \(anime.displayTitle)")
            .accessibilityHint("Opens series details").accessibilityIdentifier("featured-poster-\(anime.id)")
    }
    private func information(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if titlePresentation == .logo, let logo {
                    Image(decorative: logo.image, scale: displayScale).resizable().scaledToFit()
                        .frame(maxWidth: 340).shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                } else if titlePresentation == .text { title }
                else { Color.clear }
            }.frame(maxWidth: .infinity).frame(height: textSize.isAccessibilitySize ? 150 : 92)
                .accessibilityElement(children: .ignore).accessibilityLabel(anime.displayTitle)
                .accessibilityIdentifier("featured-title-\(anime.id)")
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 12) {
                    if let year = anime.seasonYear { Text(String(year)) }
                    Text((anime.format ?? "Anime").replacingOccurrences(of: "_", with: " "))
                }.font(.caption.weight(.semibold))
                AnimeGenres(anime: anime).accessibilityIdentifier("featured-genres-\(anime.id)")
                DiscoveryLibraryBadge(anime: anime, identifierPrefix: "featured")
                Text(anime.synopsis).font(.subheadline).lineLimit(textSize.isAccessibilitySize ? 3 : 2)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { watchAction; detailsAction; libraryAction }
                    VStack(alignment: .leading, spacing: 8) { watchAction; HStack { detailsAction; libraryAction } }
                }
            }.frame(maxWidth: wide ? 740 : .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var title: some View {
        Text(anime.displayTitle).font(.system(.title, design: .rounded, weight: .bold))
            .multilineTextAlignment(.center).lineLimit(textSize.isAccessibilitySize ? 4 : 2).shadow(color: .black.opacity(0.3), radius: 5, y: 2)
            .accessibilityIdentifier("featured-title-\(anime.id)")
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

