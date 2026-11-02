import SwiftUI
import AnimeCore

private struct DetailPlaybackRequest: Identifiable {
    let id = UUID()
    let episode: Int?
}

struct AnimeDetailView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("series.layout.anime.v1") private var sectionOrder = ""
    let mediaID: Int
    @State private var anime: Anime?
    @State private var loading = false
    @State private var error: String?
    @State private var showSettings = false
    @State private var editing = false
    @State private var playbackRequest: DetailPlaybackRequest?
    @State private var imagePreview: AnimeImagePreview?
    @State private var requestID = UUID()
    @State private var episodeRefreshID = 0
    @State private var episodeAppliedRefreshID = 0
    @State private var selectedTab = SeriesTab.info
    @State private var synopsisExpanded = false
    private enum SeriesTab: String, CaseIterable { case info = "Info", episodes = "Episodes" }
    private var layout: SeriesDetailLayout { SeriesDetailLayout(page: .anime, saved: sectionOrder) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if loading && anime == nil { ProgressView("Loading anime…").frame(maxWidth: .infinity).padding(40) }
                    if let error { NoticeView(message: error) { Task { await load() } }.padding(.horizontal) }
                    if let anime, !store.isVisible(anime) {
                        ContentUnavailableView("Adult content is hidden", systemImage: "eye.slash", description: Text("Enable adult anime in Settings to view this title."))
                        Button("Open content settings") { showSettings = true }.buttonStyle(.bordered)
                    }
                    if let anime, store.isVisible(anime) {
                        AnimeDetailHero(anime: anime) { url in imagePreview = AnimeImagePreview(url: url, title: anime.displayTitle) }
                        tabPicker
                        tabContent(anime).padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 24).readableContent(width: 940)
                            .id("series-tab-content")
                    }
                }
            }.accessibilityIdentifier("anime-detail-scroll")
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: selectedTab) { _, _ in proxy.scrollTo("series-tab-header", anchor: .top) }
        }.seriesPosterSizing().background(Theme.background).navigationTitle("Anime").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { SeriesLayoutButton(page: .anime) }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let anime, store.isVisible(anime) {
                            Button("Edit Entry", systemImage: "square.and.pencil", action: editEntry)
                                .disabled(store.loadingLibrary || store.savingMedia.contains(anime.id)).accessibilityIdentifier("detail-edit-entry")
                            Button(resumeLabel(anime), systemImage: "play.fill") { playbackRequest = DetailPlaybackRequest(episode: nil) }
                                .disabled(anime.status == "NOT_YET_RELEASED").accessibilityIdentifier("watch-in-vidhub")
                            Button("Find manga / manhwa", systemImage: "book.closed") { navigation.openMangaSearch(for: anime) }.accessibilityIdentifier("detail-find-manga")
                        }
                        Button("Account and settings", systemImage: "person.crop.circle") { showSettings = true }
                    } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                        .accessibilityLabel("Series options").accessibilityIdentifier("detail-options")
                }
            }
            .task(id: "\(mediaID)-\(store.includeAdult)") { await load() }
            .refreshable { episodeRefreshID += 1; await load(refresh: true) }
            .appSettingsSheet(isPresented: $showSettings)
            .sheet(isPresented: $editing) {
                if let anime { TrackingEditorView(anime: anime, entry: store.entry(for: anime.id)) }
            }
            .sheet(item: $playbackRequest) { request in
                if let anime { WatchAnimeView(anime: anime, requestedEpisode: request.episode) }
            }
            .fullScreenCover(item: $imagePreview) { AnimeImageViewer(preview: $0) }
    }
    private func editEntry() { if store.isSignedIn { editing = true } else { showSettings = true } }
    private var tabPicker: some View {
        Picker("Series section", selection: $selectedTab) {
            ForEach(SeriesTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented).accessibilityIdentifier("anime-detail-tabs")
            .padding(.horizontal, 16).padding(.vertical, 12).readableContent(width: 940)
            .id("series-tab-header")
    }
    private func watchlist(_ anime: Anime) -> some View {
        AnimeWatchlistStrip(anime: anime, resumeLabel: resumeLabel(anime), edit: editEntry,
            play: { playbackRequest = DetailPlaybackRequest(episode: nil) })
    }
    @ViewBuilder private func tabContent(_ anime: Anime) -> some View {
        switch selectedTab {
        case .info:
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(visibleSections(for: anime)) { section in
                    infoSection(section, anime: anime).id(section.rawValue)
                }
            }.accessibilityIdentifier("series-info-tab")
        case .episodes:
            VStack(alignment: .leading, spacing: 18) {
                watchlist(anime)
                AnimeEpisodesSection(anime: anime, refreshID: episodeRefreshID, appliedRefreshID: $episodeAppliedRefreshID,
                    play: { playbackRequest = DetailPlaybackRequest(episode: $0) }, edit: editEntry)
            }
        }
    }
    private func visibleSections(for anime: Anime) -> [SeriesDetailSection] {
        layout.order.filter { section in
            switch section {
            case .related:
                return (anime.relations?.edges ?? []).contains { edge in
                    edge.node.map { store.includeAdult || $0.isAdult != true } == true
                }
            case .recommendations:
                return (anime.recommendations?.nodes ?? []).contains { entry in
                    entry.mediaRecommendation.map { store.includeAdult || $0.isAdult != true } == true
                }
            case .trailer: return anime.trailer?.url != nil
            default: return true
            }
        }
    }
    @ViewBuilder private func infoSection(_ section: SeriesDetailSection, anime: Anime) -> some View {
        switch section {
        case .watchlist: watchlist(anime)
        case .synopsis: synopsis(anime)
        case .information: metadata(anime)
        case .broadcast: AnimeOriginalBroadcast(anime: anime)
        case .related: VStack(alignment: .leading, spacing: 12) { related(anime) }
        case .recommendations: VStack(alignment: .leading, spacing: 12) { recommendations(anime) }
        case .artwork: AnimeArtworkShelf(anime: anime, refreshID: episodeRefreshID)
        case .trailer: VStack(alignment: .leading, spacing: 12) { trailer(anime) }
        case .dubSchedule:
            AnimeDubSchedule(anime: anime, progress: dubs.progress(for: anime), snapshot: dubs.snapshot,
                events: dubEvents(for: anime), loading: dubs.loading, error: dubs.notice)
        case .news: AnimeUpdatesLinks(anime: anime)
        case .discussions: AnimeDiscussionsSection(anime: anime)
        case .reviews: reviews(anime)
        case .links:
            VStack(alignment: .leading, spacing: 12) {
                externalLinks(anime)
                Link("View on AniList", destination: URL(string: "https://anilist.co/anime/\(anime.id)")!).font(.caption)
            }
        default: EmptyView()
        }
    }
    private func resumeLabel(_ anime: Anime) -> String {
        let entry = store.entry(for: anime.id)
        let episode = PlaybackEpisodeSelection.initial(anime: anime, entry: entry, resumeEpisode: playback.resumeEpisode(animeID: anime.id))
        let finished = anime.episodes.map { $0 > 0 && (entry?.progressValue ?? 0) >= $0 } ?? false
        return anime.format == "MOVIE" ? "Watch movie" : (finished ? "Replay episode \(episode)" : ((entry?.progressValue ?? 0) > 0 ? "Resume episode \(episode)" : "Watch episode \(episode)"))
    }
    private func synopsis(_ anime: Anime) -> some View {
        DetailCard(title: "Synopsis") {
            Text(anime.synopsis).font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(synopsisExpanded ? nil : 5).fixedSize(horizontal: false, vertical: true)
            if !anime.synopsis.isEmpty && anime.description != nil {
                Button(synopsisExpanded ? "Show less" : "Read more") { synopsisExpanded.toggle() }.font(.caption.weight(.semibold))
                    .accessibilityIdentifier("detail-synopsis-expand")
            }
        }
    }
    private func metadata(_ anime: Anime) -> some View {
        DetailCard(title: "Information") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: sizeClass == .regular ? 4 : 3), alignment: .leading, spacing: 16) {
                fact("Releasing", (anime.startDate?.label ?? "Not announced") + (anime.endDate?.year == nil ? "" : " – " + (anime.endDate?.label ?? "")))
                fact("Episodes", anime.episodes.map(String.init) ?? "Not announced")
                fact("Duration", anime.duration.map { "\($0) min" } ?? "Not announced")
                fact("Studio", anime.studios?.nodes?.map(\.name).joined(separator: ", ") ?? "Not listed")
                fact("Popularity", anime.popularity.map { $0.formatted() } ?? "Not listed")
                fact("Favourites", anime.favourites.map { $0.formatted() } ?? "Not listed")
            }
            AnimeEpisodeFacts(anime: anime, entry: store.entry(for: anime.id), dub: dubs.progress(for: anime))
            if let ranks = anime.rankings, !ranks.isEmpty {
                Divider()
                ForEach(Array(ranks.prefix(4))) { rank in Label(rank.label, systemImage: rank.type == "POPULAR" ? "heart.fill" : "star.fill").font(.caption).foregroundStyle(Theme.highlight) }
            }
        }
    }
    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(label).font(.caption2).foregroundStyle(.secondary); Text(value).font(.caption.weight(.medium)) }
    }
    @ViewBuilder private func related(_ anime: Anime) -> some View {
        if let edges = anime.relations?.edges, !edges.isEmpty {
            sectionTitle("Related")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(edges.enumerated()), id: \.offset) { _, edge in
                        if let media = edge.node, store.includeAdult || media.isAdult != true { RelatedAnimeCard(anime: media, caption: edge.relationType) }
                    }
                }
            }
        }
    }
    @ViewBuilder private func recommendations(_ anime: Anime) -> some View {
        let entries = (anime.recommendations?.nodes ?? []).filter { (store.includeAdult || $0.mediaRecommendation?.isAdult != true) && $0.mediaRecommendation != nil }
        if !entries.isEmpty {
            sectionTitle("You may also like")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(entries) { entry in if let media = entry.mediaRecommendation { RelatedAnimeCard(anime: media) } }
                }
            }
        }
    }
    @ViewBuilder private func trailer(_ anime: Anime) -> some View {
        if let trailer = anime.trailer, let url = trailer.url {
            sectionTitle("Trailer")
            Link(destination: url) {
                ZStack {
                    ArtworkImage(url: URL(string: trailer.thumbnail ?? "")) { image in image.resizable().scaledToFill() } placeholder: { Theme.surface }
                        .frame(height: sizeClass == .regular ? 280 : 190).clipped()
                    Image(systemName: "play.circle.fill").font(.system(size: 54)).foregroundStyle(.white).shadow(radius: 10)
                }.clipShape(RoundedRectangle(cornerRadius: 13))
            }.accessibilityLabel("Watch anime trailer")
        }
    }
    private func reviews(_ anime: Anime) -> some View {
        DetailCard(title: "Reviews") {
            let reviews = anime.reviews?.nodes ?? []
            if reviews.isEmpty { Text("No reviews listed on AniList.").font(.caption).foregroundStyle(.secondary) }
            ForEach(reviews) { review in
                if let raw = review.siteUrl, let url = URL(string: raw), url.scheme == "https" {
                    Link(destination: url) {
                        HStack {
                            Text(TextSanitizer.plain(review.summary ?? "Read review on AniList")).font(.subheadline).multilineTextAlignment(.leading).lineLimit(3)
                            Spacer()
                            if let score = review.score { Text("\(score)/100").font(.caption.bold()).foregroundStyle(Theme.highlight) }
                            Image(systemName: "arrow.up.right").font(.caption)
                        }.padding(.vertical, 5)
                    }
                }
            }
        }
    }
    @ViewBuilder private func externalLinks(_ anime: Anime) -> some View {
        let links = (anime.externalLinks ?? []).filter { $0.safeURL != nil }
        if !links.isEmpty {
            sectionTitle("External links")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), alignment: .leading)], alignment: .leading, spacing: 10) {
                ForEach(links) { link in
                    if let url = link.safeURL {
                        Link(destination: url) { Label(link.site, systemImage: "link").font(.caption).padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: .infinity).background(Theme.surface, in: Capsule()) }
                    }
                }
            }
        }
    }
    private func sectionTitle(_ title: String) -> some View { Text(title).font(.title3.bold()).padding(.top, 12) }
    private func dubEvents(for anime: Anime) -> [ReleaseEvent] {
        dubs.snapshot?.events(knownMedia: [anime.id: anime]).filter { $0.anime.id == anime.id } ?? []
    }
    private func load(refresh: Bool = false) async {
        let attempt = UUID(); requestID = attempt; let requestedAdult = store.includeAdult
        let targetID = mediaID
        if anime?.id != targetID { anime = nil }
        if let anime, !store.isVisible(anime) { error = nil; return }
        loading = true; error = nil
        defer { if requestID == attempt { loading = false } }
        do {
            var media = try await store.aniList.details(id: targetID, includeAdult: requestedAdult, refresh: refresh)
            #if DEBUG
            // Deterministic countdown for layout tests only, never a provider date or Release data.
            if ProcessInfo.processInfo.arguments.contains("--ui-detail-airing-preview"), media.id == 1 {
                var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(media)) as! [String: Any]
                object["status"] = "RELEASING"
                object["nextAiringEpisode"] = ["episode": 9, "airingAt": Int(Date().addingTimeInterval(86400).timeIntervalSince1970)]
                media = try JSONDecoder().decode(Anime.self, from: JSONSerialization.data(withJSONObject: object))
            }
            #endif
            try Task.checkCancellation(); guard requestID == attempt, store.includeAdult == requestedAdult else { return }
            anime = media
            await dubs.load(using: store.dubs, refresh: refresh)
        } catch is CancellationError {} catch { if requestID == attempt { self.error = error.localizedDescription } }
    }
}
