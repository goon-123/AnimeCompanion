import SwiftUI
import AnimeCore

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
                                NavigationLink(value: AnimeVisualsRoute(anime: item)) {
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
        (gallery?.images ?? []).map {
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
            let images = gallery?.images ?? []
            HStack {
                Text("\(images.count) images").font(.headline).accessibilityIdentifier("visuals-image-count")
                Spacer()
                if !loadingGallery {
                    Button { Task { await loadGallery(anime, refresh: true) } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                        .accessibilityLabel("Refresh artwork").accessibilityIdentifier("visuals-refresh")
                }
            }
            if images.isEmpty && !loadingGallery && gallery?.notice == nil { ContentUnavailableView("No artwork available", systemImage: "photo") }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 300), spacing: 16)], alignment: .leading, spacing: 18) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                    artwork(image, index: index)
                }
            }
        }
    }
    private func artwork(_ image: AnimeVisual, index: Int) -> some View {
        AnimeVisualCard(image: image) { preview = image.preview }
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
        if gallery == nil { gallery = await store.visuals.cachedGallery(for: anime) }
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
