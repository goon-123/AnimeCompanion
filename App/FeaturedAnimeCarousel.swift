import SwiftUI
import AnimeCore

private struct PreparedSpotlightArtwork: Sendable {
    let artwork: SeriesArtwork
    let logo: ArtworkBitmap?
    let hero: ArtworkBitmap?
    let heroURL: URL?
    func retaining(_ old: Self?) -> Self {
        Self(artwork: artwork.fillingMissing(with: old?.artwork ?? SeriesArtwork()),
             logo: logo ?? old?.logo, hero: hero ?? old?.hero, heroURL: hero == nil ? old?.heroURL : heroURL)
    }
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
    @State private var selectedSlot: Int? = 0
    @State private var selectedAnimeID: Int?
    @State private var visibleSlots = Set<Int>()
    @State private var titles = SpotlightTitlePresentation()
    @State private var prepared: [Int: PreparedSpotlightArtwork] = [:]
    @State private var presented: [Int: PreparedSpotlightArtwork] = [:]
    @AppStorage(SeriesArtworkPreferences.bannerKey) private var bannerFallback = false
    @AppStorage(SeriesArtworkPreferences.posterKey) private var posterFallback = false
    private var items: [Anime] { Array(anime.prefix(5)) }
    private var ids: Set<Int> { Set(items.map(\.id)) }
    private var loop: SpotlightLoop { SpotlightLoop(count: items.count) }
    private var activeIndex: Int { loop.index(for: selectedSlot) ?? 0 }
    private var active: Anime? { items.indices.contains(activeIndex) ? items[activeIndex] : nil }
    private var preferences: SeriesArtworkPreferences { .init(banner: bannerFallback, poster: posterFallback) }

    var body: some View {
        GeometryReader { viewport in
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    // At most seven lightweight panels share five decoded asset
                    // snapshots. Both boundary copies have their bitmap on the
                    // very first frame; recycling must not flash a placeholder.
                    HStack(spacing: 0) {
                        ForEach(loop.slots, id: \.self) { slot in
                            if let index = loop.index(for: slot) {
                                let item = items[index]
                                let snapshot = presented[item.id]
                                FeaturedAnimePanel(anime: item, topInset: topInset,
                                    background: PosterAccent(hex: item.coverImage?.color)?.backdrop ?? background,
                                    hero: snapshot?.hero, heroURL: snapshot?.heroURL,
                                    logo: snapshot?.logo, titlePresentation: titles.title(for: item.id))
                                    .frame(width: viewport.size.width, height: height).id(slot)
                                    .accessibilityHidden(slot != (selectedSlot ?? 0))
                                    .onGeometryChange(for: Bool.self) { page in
                                        let overlap = page.frame(in: .global).intersection(viewport.frame(in: .global))
                                        return !overlap.isNull && overlap.width > 1 && overlap.height > 1
                                    } action: { visible in
                                        if visible { visibleSlots.insert(slot) } else { visibleSlots.remove(slot) }
                                    }
                                    .onGeometryChange(for: Bool.self) { page in
                                        abs(page.frame(in: .global).minX - viewport.frame(in: .global).minX) < 0.5
                                    } action: { aligned in
                                        // iOS 18+ uses the native idle callback.
                                        // The iOS 17 fallback waits for the exact
                                        // paging alignment, not a guessed delay.
                                        if #unavailable(iOS 18.0), aligned, loop.rebase(slot) != nil {
                                            Task { @MainActor in
                                                await Task.yield()
                                                if selectedSlot == slot { settlePage() }
                                            }
                                        }
                                    }
                            }
                        }
                    }.scrollTargetLayout()
                }.scrollTargetBehavior(.paging).scrollPosition(id: $selectedSlot, anchor: .center)
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    .modifier(SpotlightScrollActivity(paging: $paging))
                HStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button { withAnimation(AppMotion.page(reduceMotion)) { selectedSlot = index } } label: {
                            Circle().fill(active?.id == item.id ? Color.white : .white.opacity(0.35))
                                .frame(width: 7, height: 7).frame(width: 35, height: 40)
                        }.buttonStyle(.plain).accessibilityLabel("Featured title \(index + 1) of \(items.count)")
                            .accessibilityValue(active?.id == item.id ? "Selected" : "")
                            .accessibilityIdentifier("featured-page-\(index)")
                    }
                }
            }.background(Theme.background)
                .accessibilityElement(children: .contain).accessibilityIdentifier("explore-featured-carousel")
                .task(id: preparationKey(width: viewport.size.width)) { await prepareArtwork(width: viewport.size.width) }
        }.frame(height: height + 40)
            .onChange(of: items.map(\.id)) { previous, values in
                let previousID = selectedAnimeID ?? previous.first
                visibleSlots = []
                titles.retain(Set(values)); prepared = prepared.filter { values.contains($0.key) }
                presented = presented.filter { values.contains($0.key) }
                var instant = Transaction(); instant.disablesAnimations = true
                withTransaction(instant) { selectedSlot = previousID.flatMap { values.firstIndex(of: $0) } ?? 0 }
            }
            .onChange(of: paging) { _, moving in if !moving { settlePage() } }
            .onChange(of: selectedSlot) { _, _ in
                selectedAnimeID = active?.id
                if #unavailable(iOS 18.0) { commitOffscreen() }
            }
            .onAppear { selectedAnimeID = active?.id }
            .onDisappear {
                paging = false; visibleSlots = []
                titles.leaveViewport(); presented = prepared
            }
    }
    @MainActor private func settlePage() {
        if let real = loop.rebase(selectedSlot) {
            var instant = Transaction(); instant.disablesAnimations = true
            withTransaction(instant) { selectedSlot = real }
            Task { @MainActor in
                await Task.yield()
                commitReady()
            }
            return
        }
        commitReady()
    }
    private func commitOffscreen() {
        let protected = Set(visibleSlots.compactMap { loop.index(for: $0).map { items[$0].id } }).union(active.map { [$0.id] } ?? [])
        titles.revealOffscreen(protected: protected)
        for (id, value) in prepared where !protected.contains(id) { presented[id] = value }
    }
    private func commitReady() {
        guard !paging else { return }
        // A cold result appears as one decoded background/logo snapshot, in a
        // short fade with a fixed title slot. Never mutate it during a swipe.
        withAnimation(.easeOut(duration: reduceMotion ? 0.10 : 0.18)) {
            presented = prepared; titles.presentPrepared()
        }
    }
    private func preparationKey(width: CGFloat) -> String {
        "\(items.map(\.id))-\(width)-\(height)-\(displayScale)-\(bannerFallback)-\(posterFallback)"
    }
    @MainActor private func prepareArtwork(width: CGFloat) async {
        let lineup = items, api = store.seriesArtwork
        let prefs = preferences, wide = width > height * 1.2
        let heroPixels = min(2400, ArtworkSizing.pixelLimit(points: Double(max(width, height)), scale: Double(displayScale)))
        let logoPixels = ArtworkSizing.pixelLimit(points: Double(min(max(0, width - 40), 560)), scale: Double(displayScale))
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--ui-") }) && !SpotlightPolishPreview.active {
            for item in lineup { titles.checkedCache(for: item.id, hasLogo: false) }
            return
        }
        #endif
        // Probe decoded cache first, without a network request. Previously
        // displayed snapshots survive rotation and a cancelled preparation task.
        for item in lineup {
            let art = await api.cachedArtwork(for: item) ?? SeriesArtwork()
            let url = prefs.spotlightURL(artwork: art, anime: item, landscape: wide)
            let cachedHero: ArtworkBitmap?
            if let url { cachedHero = await ArtworkPipeline.shared.cachedImage(at: url, pixels: heroPixels) } else { cachedHero = nil }
            let cachedLogo: ArtworkBitmap?
            if let url = art.logo, let bitmap = await ArtworkPipeline.shared.cachedImage(at: url, pixels: logoPixels) {
                cachedLogo = await SpotlightLogoBitmap.shared.trim(bitmap)
            } else { cachedLogo = nil }
            guard !Task.isCancelled, ids.contains(item.id) else { return }
            let value = PreparedSpotlightArtwork(artwork: art, logo: cachedLogo, hero: cachedHero, heroURL: cachedHero == nil ? nil : url).retaining(prepared[item.id])
            prepared[item.id] = value
            if !paging { presented[item.id] = value }
            titles.checkedCache(for: item.id, hasLogo: value.logo != nil)
        }
        // Warm the current title and both neighbors, including the wrap in
        // either direction, before the remaining offscreen entries.
        let priority = loop.neighbors(of: activeIndex)
        let ordered = (priority + lineup.indices.filter { !priority.contains($0) }).map { lineup[$0] }
        await withTaskGroup(of: (Int, PreparedSpotlightArtwork).self) { group in
            var remaining = ordered.makeIterator()
            for _ in 0..<2 {
                if let item = remaining.next() { group.addTask { await prepareSpotlight(item, api: api, preferences: prefs, wide: wide, heroPixels: heroPixels, logoPixels: logoPixels) } }
            }
            for await (id, value) in group {
                guard !Task.isCancelled else { group.cancelAll(); return }
                if ids.contains(id) {
                    prepared[id] = value.retaining(prepared[id])
                    if prepared[id]?.logo != nil { titles.preparedLogo(for: id, protected: ids) }
                    commitReady()
                }
                if let item = remaining.next() { group.addTask { await prepareSpotlight(item, api: api, preferences: prefs, wide: wide, heroPixels: heroPixels, logoPixels: logoPixels) } }
            }
        }
    }
}

private struct SpotlightScrollActivity: ViewModifier {
    @Binding var paging: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) { content.onScrollPhaseChange { _, phase in paging = phase != .idle } }
        else { content }
    }
}

private func prepareSpotlight(_ anime: Anime, api: SeriesArtworkClient, preferences: SeriesArtworkPreferences,
                              wide: Bool, heroPixels: Int, logoPixels: Int) async -> (Int, PreparedSpotlightArtwork) {
    let art = await api.spotlightArtwork(for: anime)
    let url = preferences.spotlightURL(artwork: art, anime: anime, landscape: wide)
    async let hero = spotlightBitmap(url, pixels: heroPixels)
    async let logo = spotlightBitmap(art.logo, pixels: logoPixels)
    let (background, title) = await (hero, logo)
    let trimmed: ArtworkBitmap?
    if let title { trimmed = await SpotlightLogoBitmap.shared.trim(title) } else { trimmed = nil }
    return (anime.id, PreparedSpotlightArtwork(artwork: art, logo: trimmed,
        hero: background, heroURL: background == nil ? nil : url))
}
private func spotlightBitmap(_ url: URL?, pixels: Int) async -> ArtworkBitmap? {
    guard let url else { return nil }
    return try? await ArtworkPipeline.shared.image(at: url, pixels: pixels)
}

private struct FeaturedAnimePanel: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.displayScale) private var displayScale
    @AppStorage(SeriesArtworkPreferences.bannerKey) private var bannerFallback = false
    @AppStorage(SeriesArtworkPreferences.posterKey) private var posterFallback = false
    let anime: Anime
    let topInset: CGFloat
    let background: PosterAccent
    let hero: ArtworkBitmap?
    let heroURL: URL?
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
                    .init(color: Theme.background.opacity(0.80), location: 0.73), .init(color: Theme.background, location: 0.98)],
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
        return AnimeLink(id: anime.id) {
            ZStack {
                background.color
                if let hero {
                    Image(decorative: hero.image, scale: displayScale).resizable().scaledToFill()
                        .frame(width: width, height: height, alignment: wide ? .center : .top)
                        .clipped().id(heroURL).transition(.opacity)
                }
            }.frame(width: width, height: height, alignment: wide ? .center : .top).clipped().contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("View \(anime.displayTitle)")
            .accessibilityHint("Opens series details").accessibilityIdentifier("featured-poster-\(anime.id)")
    }
    private func information(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Color.clear.frame(height: textSize.isAccessibilitySize ? 150 : 92)
                .overlay(alignment: .bottom) {
                    GeometryReader { slot in
                        Group {
                            if titlePresentation == .logo, let logo {
                                Image(decorative: logo.image, scale: displayScale).resizable().scaledToFit()
                                    .frame(width: min(slot.size.width, 560), height: textSize.isAccessibilitySize ? 210 : 148, alignment: .bottom)
                                    .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                                    .transition(.opacity)
                            } else if titlePresentation == .text { title.frame(width: slot.size.width, height: slot.size.height) }
                        }.frame(width: slot.size.width, height: slot.size.height, alignment: .bottom)
                    }
                }
                .accessibilityElement(children: .ignore).accessibilityLabel(anime.displayTitle)
                .accessibilityValue(titlePresentation == .logo ? "Logo" : "Text")
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
            }.foregroundStyle(Color.primary).frame(maxWidth: wide ? 740 : .infinity, alignment: .leading)
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
        }.buttonStyle(.plain).disabled(AnimePremiere.defersEpisodes(for: anime)).accessibilityIdentifier("featured-watch-\(anime.id)")
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

