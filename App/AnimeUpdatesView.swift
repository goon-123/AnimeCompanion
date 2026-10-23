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
                if let anime { await loadDetails(anime) } else { await load() }
            }
            .refreshable { if let anime { await loadDetails(anime, refresh: true) } else { await load(refresh: true) } }
            .fullScreenCover(item: $preview) { AnimeImageViewer(preview: $0) }
    }
    private func titleVisuals(_ anime: Anime) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(anime.displayTitle).font(.title2.bold())
            Text("Artwork supplied by AniList. Tap an image to expand it.").font(.caption).foregroundStyle(.secondary)
            if let url = anime.coverURL {
                artwork(url, title: anime.displayTitle + " · Poster", height: 420)
            }
            if let raw = anime.bannerImage, let url = URL(string: raw) {
                artwork(url, title: anime.displayTitle + " · Banner", height: 220)
            }
            if let trailer = anime.trailer, let url = trailer.url {
                Link(destination: url) { Label("Watch trailer", systemImage: "play.rectangle.fill").frame(minHeight: 44) }
                    .buttonStyle(.bordered).accessibilityIdentifier("visuals-watch-trailer")
            }
            NavigationLink { AnimeDetailView(mediaID: anime.id) } label: { Label("Anime details", systemImage: "info.circle").frame(minHeight: 44) }
                .accessibilityIdentifier("visuals-anime-details")
        }.modifier(CatalogEntrance())
    }
    private func artwork(_ url: URL, title: String, height: CGFloat) -> some View {
        Button { preview = AnimeImagePreview(url: url, title: title) } label: {
            ArtworkImage(url: url, pointSize: 700) { $0.resizable().scaledToFit() } placeholder: { Theme.surface }
                .frame(maxWidth: .infinity).frame(height: height).clipShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityLabel("Expand \(title)")
    }
    private func load(refresh: Bool = false) async {
        await catalog.load(selection: season, includeAdult: store.includeAdult, api: store.aniList, cache: store.exploreCache, refresh: refresh)
    }
    private func loadDetails(_ anime: Anime, refresh: Bool = false) async {
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
