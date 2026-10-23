import SwiftUI
import AnimeCore

struct AnimeUpdatesLinks: View {
    let anime: Anime
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { links }
            VStack(alignment: .leading, spacing: 10) { links }
        }
    }
    @ViewBuilder private var links: some View {
        NavigationLink { AnimeReleaseInfoView(anime: anime) } label: { label("Schedule", symbol: "calendar") }
            .accessibilityIdentifier("detail-open-schedule")
        NavigationLink { AnimeVisualsView(anime: anime) } label: { label("Visuals", symbol: "photo.on.rectangle") }
            .accessibilityIdentifier("detail-open-visuals")
        NavigationLink { NewsView(anime: anime) } label: { label("Headlines", symbol: "newspaper") }
            .accessibilityIdentifier("detail-open-headlines")
    }
    private func label(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.caption.weight(.semibold))
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(Theme.surface, in: Capsule()).foregroundStyle(.primary)
    }
}

private struct AnimeReleaseInfoView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @EnvironmentObject private var navigation: AppNavigationStore
    let anime: Anime
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if store.isVisible(anime) {
                Text(anime.displayTitle).font(.title2.bold())
                DetailCard(title: "Original broadcast") {
                    if anime.isCurrentlyAiring, let next = anime.nextAiringEpisode { BroadcastCountdown(episode: next) }
                    else { Text(anime.status == "FINISHED" ? "Broadcast finished" : "Next episode time not announced").font(.subheadline) }
                    if let start = anime.startDate?.label { Text("First release · \(start)").font(.caption).foregroundStyle(.secondary) }
                    Text("AniList broadcast times use your device timezone and do not confirm regional streaming availability.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                AnimeDubSchedule(anime: anime, progress: dubs.progress(for: anime), snapshot: dubs.snapshot,
                    events: dubs.snapshot?.events(knownMedia: [anime.id: anime]).filter { $0.anime.id == anime.id } ?? [],
                    loading: dubs.loading, error: dubs.notice)
                Button { navigation.selectedTab = .schedule } label: { Label("Open the weekly schedule", systemImage: "calendar") }
                    .buttonStyle(.bordered).accessibilityIdentifier("detail-weekly-schedule")
                } else { ContentUnavailableView("Adult content is hidden", systemImage: "eye.slash") }
            }.padding(18).readableContent(width: 940)
        }.background(Theme.background).navigationTitle("Schedule").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("anime-release-info")
    }
}

struct AnimeVisualsView: View {
    @EnvironmentObject private var store: AppStore
    var anime: Anime? = nil
    @StateObject private var catalog = ExploreCatalogModel()
    @State private var preview: AnimeImagePreview?
    @State private var details: Anime?
    @State private var detailError: String?
    @State private var gallery: AnimeVisualGallery?
    @State private var loadingGallery = false
    private let season = SeasonSelection.current()
    private var media: [Anime] { AnimeUpdates.visuals(in: catalog.state.response, includeAdult: store.includeAdult) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let anime {
                    if store.isVisible(details ?? anime) {
                        titleVisuals(details ?? anime)
                        if let detailError { NoticeView(message: detailError) { Task { await loadDetails(anime, refresh: true) } } }
                    }
                    else { ContentUnavailableView("Adult content is hidden", systemImage: "eye.slash") }
                } else {
                    Text("Seasonal & upcoming artwork").font(.title2.bold())
                    Text("Posters from the AniList catalog—not a chronological feed of newly announced visuals. Open a title for more artwork and its available trailer.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let error = catalog.state.error { NoticeView(message: error) { Task { await load(refresh: true) } } }
                    if catalog.state.loading && media.isEmpty { ProgressView("Loading visuals…").frame(maxWidth: .infinity) }
                    if !media.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 240), spacing: 16)], alignment: .leading, spacing: 22) {
                            ForEach(media) { item in
                                NavigationLink { AnimeVisualsView(anime: item) } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        GeometryReader { geometry in AnimeCover(anime: item, width: geometry.size.width) }
                                            .aspectRatio(1 / 1.45, contentMode: .fit)
                                        Text(item.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    }.foregroundStyle(.primary)
                                }.buttonStyle(.plain).accessibilityIdentifier("anime-visual-\(item.id)")
                            }
                        }.modifier(CatalogEntrance())
                    } else if !catalog.state.loading && catalog.state.error == nil {
                        ContentUnavailableView("No artwork listed yet", systemImage: "photo")
                    }
                }
            }.padding(18).readableContent(width: 1100)
        }.background(Theme.background).navigationTitle("Visuals").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("anime-visuals")
            .task(id: "\(anime?.id ?? 0)-\(store.includeAdult)") {
                if let anime { await loadTitle(anime) } else { await load() }
            }
            .refreshable { if let anime { await loadTitle(anime, refresh: true) } else { await load(refresh: true) } }
            .fullScreenCover(item: $preview) { AnimeImageViewer(preview: $0, gallery: previews) }
            .onChange(of: store.includeAdult) { _, _ in
                if let anime, !store.isVisible(details ?? anime) { preview = nil; gallery = nil }
            }
    }
    private var previews: [AnimeImagePreview] {
        (gallery?.images ?? anime.map(AnimeVisualGallery.aniListImages) ?? []).map {
            AnimeImagePreview(url: $0.imageURL, title: $0.title, credit: $0.copyright, source: $0.source.label)
        }
    }
    private func titleVisuals(_ anime: Anime) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(anime.displayTitle).font(.title2.bold())
            Text("Tap artwork to expand it, swipe between images, or pinch to zoom.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                AnimeLink(id: anime.id) { Label("Anime details", systemImage: "info.circle").frame(minHeight: 44) }
                    .accessibilityIdentifier("visuals-anime-details")
                if let trailer = anime.trailer, let url = trailer.url {
                    Link(destination: url) { Label("Watch trailer", systemImage: "play.rectangle.fill").frame(minHeight: 44) }
                        .buttonStyle(.bordered).accessibilityIdentifier("visuals-watch-trailer")
                }
            }.font(.subheadline)
            if loadingGallery {
                ProgressView(gallery == nil ? "Loading more artwork…" : "Refreshing artwork…")
                    .accessibilityIdentifier("visuals-loading")
            }
            if let notice = gallery?.notice {
                Label(notice, systemImage: gallery?.isStale == true ? "clock.arrow.circlepath" : "info.circle")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("visuals-notice")
            }
            let images = gallery?.images ?? AnimeVisualGallery.aniListImages(anime)
            HStack {
                Text("\(images.count) images").font(.headline).accessibilityIdentifier("visuals-image-count")
                Spacer()
                if !loadingGallery {
                    Button { Task { await loadGallery(anime, refresh: true) } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                        .accessibilityLabel("Refresh artwork").accessibilityIdentifier("visuals-refresh")
                }
            }
            if images.isEmpty && !loadingGallery { ContentUnavailableView("No artwork available", systemImage: "photo") }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 300), spacing: 16)], alignment: .leading, spacing: 18) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                    artwork(image, index: index)
                }
            }
        }.modifier(CatalogEntrance())
    }
    private func artwork(_ image: AnimeVisual, index: Int) -> some View {
        Button {
            preview = AnimeImagePreview(url: image.imageURL, title: image.title, credit: image.copyright, source: image.source.label)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { geometry in
                    ArtworkImage(url: image.thumbnailURL, pointSize: 600) { $0.resizable().scaledToFit() } placeholder: { Theme.surface }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }.aspectRatio(2.0 / 3, contentMode: .fit)
                VStack(alignment: .leading, spacing: 5) {
                    Text(image.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(image.source.label).font(.caption).foregroundStyle(.secondary)
                    if let copyright = image.copyright { Text(copyright).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }.background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 14)).foregroundStyle(.primary)
        }.buttonStyle(.plain).accessibilityLabel("Expand \(image.title), \(image.source.label)")
            .accessibilityIdentifier("visual-card-\(image.source.rawValue)-\(index)")
    }
    @MainActor private func loadTitle(_ anime: Anime, refresh: Bool = false) async {
        async let metadata: Void = loadDetails(anime, refresh: refresh)
        async let artwork: Void = loadGallery(anime, refresh: refresh)
        _ = await (metadata, artwork)
    }
    @MainActor private func loadGallery(_ anime: Anime, refresh: Bool = false) async {
        guard store.isVisible(anime) else { gallery = nil; return }
        let includeAdult = store.includeAdult
        loadingGallery = true
        defer { loadingGallery = false }
        let value = await store.visuals.gallery(for: anime, refresh: refresh)
        guard !Task.isCancelled, store.includeAdult == includeAdult, store.isVisible(details ?? anime) else { return }
        gallery = value
    }
    private func load(refresh: Bool = false) async {
        await catalog.load(selection: season, includeAdult: store.includeAdult, api: store.aniList, cache: store.exploreCache, refresh: refresh)
    }
    @MainActor private func loadDetails(_ anime: Anime, refresh: Bool = false) async {
        guard store.isVisible(anime) else { details = nil; return }
        detailError = nil
        let includeAdult = store.includeAdult
        do {
            let value = try await store.aniList.details(id: anime.id, includeAdult: includeAdult, refresh: refresh)
            try Task.checkCancellation()
            guard store.includeAdult == includeAdult else { return }
            details = value
        } catch is CancellationError {} catch {
            detailError = "Additional artwork and trailer information could not load. Your existing artwork is still available."
        }
    }
}
