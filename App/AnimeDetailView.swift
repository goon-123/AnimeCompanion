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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AnimeSeriesStyle.storageKey) private var savedStyle = AnimeSeriesStyle.cinematic.rawValue
    @AppStorage(SeriesMoreInfoPreferences.storageKey) private var moreInfoSaved = ""
    @AppStorage("series.layout.anime.v1") private var sectionOrder = ""
    @Namespace private var tabIndicator
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
    @State private var selectedTab = SeriesTab.episodes
    @State private var artwork = SeriesArtwork()
    @State private var artworkResolved = false
    @State private var showingTrailer = false
    @State private var arranging = false
    @State private var appearance = false
    @State private var synopsisExpanded = false
    private enum SeriesTab: String, CaseIterable { case episodes = "Episodes", info = "More Info", recommendations = "Similar" }
    private var layout: SeriesDetailLayout { SeriesDetailLayout(page: .anime, saved: sectionOrder) }
    private var style: AnimeSeriesStyle { AnimeSeriesStyle(preference: savedStyle) }
    private var moreInfo: SeriesMoreInfoPreferences { .init(saved: moreInfoSaved) }
    private var tabs: [SeriesTab] { style == .classic ? [.info, .episodes] : SeriesTab.allCases }
    init(mediaID: Int) {
        self.mediaID = mediaID
        let style = AnimeSeriesStyle(preference: UserDefaults.standard.string(forKey: AnimeSeriesStyle.storageKey) ?? "")
        _selectedTab = State(initialValue: style == .classic ? .info : .episodes)
    }

    var body: some View {
        seriesScroll.seriesPosterSizing()
            .ignoresSafeArea(.container, edges: style == .cinematic ? .top : [])
            .background(Theme.background).navigationTitle(anime?.displayTitle ?? "Anime").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .companionDockHidden()
            .overlay(alignment: .bottomLeading) { commentsButton }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { optionsMenu } }
            .task(id: "\(mediaID)-\(store.includeAdult)") { await load() }
            .refreshable { episodeRefreshID += 1; await load(refresh: true) }
            .appSettingsSheet(isPresented: $showSettings)
            .sheet(isPresented: $arranging) { AppNavigationStack { SeriesLayoutEditor(page: .anime) } }
            .sheet(isPresented: $appearance) {
                AppNavigationStack {
                    SeriesAppearanceSettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { appearance = false } } }
                }
            }
            .sheet(isPresented: $editing) { if let anime { TrackingEditorView(anime: anime, entry: store.entry(for: anime.id)) } }
            .sheet(item: $playbackRequest) { request in if let anime { WatchAnimeView(anime: anime, requestedEpisode: request.episode) } }
            .fullScreenCover(item: $imagePreview) { AnimeImageViewer(preview: $0) }
            .sheet(isPresented: $showingTrailer) { if let trailer = anime?.trailer, let url = trailer.url { SeriesTrailerSheet(trailer: trailer, url: url) } }
            .onChange(of: savedStyle) { _, _ in selectedTab = style == .classic ? .info : .episodes }
            .task(id: "\(anime?.id ?? 0)-\(episodeRefreshID)-\(store.includeAdult)-\(savedStyle)") { await loadArtwork() }
    }
    private var seriesScroll: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if loading && anime == nil { ProgressView("Loading anime…").frame(maxWidth: .infinity).padding(40) }
                    if let error { NoticeView(message: error) { Task { await load() } }.padding(.horizontal) }
                    if let anime, !store.isVisible(anime) {
                        ContentUnavailableView("Adult content is hidden", systemImage: "eye.slash", description: Text("Enable adult anime in Settings to view this title."))
                        Button("Open content settings") { showSettings = true }.buttonStyle(.bordered)
                    }
                    if let anime, store.isVisible(anime) {
                        seriesHeader(anime)
                        tabPicker
                        VStack(alignment: .leading, spacing: 0) { tabContent(anime) }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .id(selectedTab).transition(AppMotion.replacement(reduceMotion))
                            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 90).readableContent(width: 1060)
                            .id("series-tab-content")
                    }
                }
            }.accessibilityIdentifier("anime-detail-scroll")
                .contentMargins(.top, 0, for: .scrollContent)
                .ignoresSafeArea(.container, edges: style == .cinematic ? .top : [])
                .scrollDismissesKeyboard(.interactively)
    }
    @ViewBuilder private func seriesHeader(_ anime: Anime) -> some View {
        if style == .classic {
            ClassicAnimeDetailHero(anime: anime) { imagePreview = AnimeImagePreview(url: $0, title: anime.displayTitle) }
        } else {
            CinematicAnimeHero(anime: anime, artwork: artwork, artworkResolved: artworkResolved, trailer: { showingTrailer = true }) { imagePreview = AnimeImagePreview(url: $0, title: anime.displayTitle) }
            seriesIntroduction(anime).padding(.horizontal, 20).padding(.bottom, 18).readableContent(width: 1060)
        }
    }
    @ViewBuilder private var commentsButton: some View {
                if let anime, store.isVisible(anime) {
                    NavigationLink { SeriesCommunityView(anime: anime) } label: {
                        Image(systemName: "text.bubble").font(.title2).frame(width: 56, height: 56).silverGlass(in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain).padding(.leading, 20).padding(.bottom, 16)
                        .accessibilityLabel("Series reviews and episode comments").accessibilityIdentifier("detail-floating-comments")
                }
    }
    private var optionsMenu: some View {
                    Menu {
                        Section("Appearance") {
                            Button("Customize sections", systemImage: "slider.horizontal.3") { arranging = true }.accessibilityIdentifier("series-arrange-anime")
                            Button("Series appearance", systemImage: "rectangle.on.rectangle") { appearance = true }.accessibilityIdentifier("detail-series-appearance")
                        }
                        if let anime, store.isVisible(anime) {
                            Button("Edit Entry", systemImage: "square.and.pencil", action: editEntry)
                                .disabled(store.loadingLibrary || store.savingMedia.contains(anime.id)).accessibilityIdentifier("detail-edit-entry")
                            Button(resumeLabel(anime), systemImage: "play.fill") { playbackRequest = DetailPlaybackRequest(episode: nil) }
                                .disabled(AnimePremiere.defersEpisodes(for: anime)).accessibilityIdentifier("watch-in-vidhub")
                            Button("Find manga / manhwa", systemImage: "book.closed") { navigation.openMangaSearch(for: anime) }.accessibilityIdentifier("detail-find-manga")
                        }
                        Button("Account and settings", systemImage: "person.crop.circle") { showSettings = true }
                    } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }
                        .accessibilityLabel("Series options").accessibilityIdentifier("detail-options")
    }
    private func loadArtwork() async {
                guard style == .cinematic, let anime, store.isVisible(anime) else { artwork = SeriesArtwork(); artworkResolved = false; return }
                #if DEBUG
                // Keep existing offline device fixtures independent of public artwork services.
                if ProcessInfo.processInfo.arguments.contains("--ui-phase2-preview") { artworkResolved = true; return }
                #endif
                if let cached = await store.seriesArtwork.cachedArtwork(for: anime), !Task.isCancelled {
                    artwork = cached; artworkResolved = true
                }
                let result = await store.seriesArtwork.artwork(for: anime, refresh: episodeRefreshID > 0)
                guard !Task.isCancelled else { return }
                artwork = result; artworkResolved = true
    }
    private func editEntry() { if store.isSignedIn { editing = true } else { showSettings = true } }
    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button { withAnimation(AppMotion.page(reduceMotion)) { selectedTab = tab } } label: {
                    VStack(spacing: 12) {
                        Text(style == .classic && tab == .info ? "Info" : tab.rawValue).font(.subheadline.weight(selectedTab == tab ? .bold : .medium))
                            .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
                        ZStack {
                            Rectangle().fill(Theme.border)
                            if selectedTab == tab { Rectangle().fill(Theme.accent).matchedGeometryEffect(id: "selected-series-tab", in: tabIndicator) }
                        }.frame(height: 2)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("anime-detail-tabs").readableContent(width: 1060)
            .id("series-tab-header")
    }
    private func seriesIntroduction(_ anime: Anime) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if layout.visible.contains(.broadcast) { SeriesAiringCountdown(anime: anime) }
            if layout.visible.contains(.watchlist) {
                SeriesWatchActions(anime: anime, resumeLabel: resumeLabel(anime),
                    play: { playbackRequest = DetailPlaybackRequest(episode: nil) }, edit: editEntry)
            }
            if layout.visible.contains(.synopsis) { synopsis(anime) }
            if layout.visible.contains(.characters) { SeriesCharacters(anime: anime) }
            AnimeGenres(anime: anime).accessibilityIdentifier("detail-genres-\(anime.id)")
        }
    }
    private func watchlist(_ anime: Anime) -> some View {
        AnimeWatchlistStrip(anime: anime, resumeLabel: resumeLabel(anime), edit: editEntry,
            play: { playbackRequest = DetailPlaybackRequest(episode: nil) })
    }
    @ViewBuilder private func tabContent(_ anime: Anime) -> some View {
        switch selectedTab {
        case .info:
            LazyVStack(alignment: .leading, spacing: 18) {
                if visibleSections(for: anime).isEmpty { hiddenSectionsNotice }
                ForEach(visibleSections(for: anime)) { section in
                    infoSection(section, anime: anime).id(section.rawValue)
                }
            }.accessibilityIdentifier("series-info-tab")
        case .episodes:
            AnimeEpisodesSection(anime: anime, refreshID: episodeRefreshID, appliedRefreshID: $episodeAppliedRefreshID,
                play: { playbackRequest = DetailPlaybackRequest(episode: $0) }, edit: editEntry)
        case .recommendations:
            if layout.visible.contains(.recommendations) {
                if (anime.recommendations?.nodes ?? []).isEmpty {
                    ContentUnavailableView("No recommendations yet", systemImage: "sparkles", description: Text("Recommendations will appear as this series gains activity."))
                } else { recommendations(anime) }
            } else { Text("Recommendations are hidden. Use Arrange sections to show them.").foregroundStyle(.secondary) }
        }
    }
    private func visibleSections(for anime: Anime) -> [SeriesDetailSection] {
        (style == .classic ? layout.visible : moreInfo.visible).filter { section in
            switch section {
            case .broadcast: return AnimeSeriesContent.showsOriginalBroadcast(for: anime)
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
    private var hiddenSectionsNotice: some View {
        Text("Info sections are hidden or unavailable. Use Arrange sections in the toolbar to show more.")
            .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 20)
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
        case .news: AnimeSeriesNewsWidget(anime: anime, refreshID: episodeRefreshID)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(anime.synopsis).font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(synopsisExpanded ? nil : 5).fixedSize(horizontal: false, vertical: true)
            if !anime.synopsis.isEmpty && anime.description != nil {
                Button(synopsisExpanded ? "Show less" : "Read more") { synopsisExpanded.toggle() }.font(.caption.weight(.semibold))
                    .accessibilityIdentifier("detail-synopsis-expand")
            }
        }
    }
    private func metadata(_ anime: Anime) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Information").font(.headline)
                Spacer()
                Text([anime.format?.replacingOccurrences(of: "_", with: " "), anime.seasonYear.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(anime.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
            HStack(spacing: 16) {
                Label(anime.episodes.map { "\($0) episodes" } ?? "Episodes TBA", systemImage: "rectangle.stack")
                if let duration = anime.duration { Label("\(duration) min", systemImage: "clock") }
            }.font(.caption).foregroundStyle(.secondary)
            studioLinks(anime)
            AnimeEpisodeFacts(anime: anime, entry: store.entry(for: anime.id), dub: dubs.progress(for: anime))
            DisclosureGroup("Dates & rankings") {
                VStack(alignment: .leading, spacing: 10) {
                    fact("Broadcast", (anime.startDate?.label ?? "Not announced") + (anime.endDate?.year == nil ? "" : " – " + (anime.endDate?.label ?? "")))
                    HStack { fact("Popularity", anime.popularity.map { $0.formatted() } ?? "Not listed"); Spacer(); fact("Favourites", anime.favourites.map { $0.formatted() } ?? "Not listed") }
                    ForEach(Array((anime.rankings ?? []).prefix(4))) { rank in
                        Label(rank.label, systemImage: rank.type == "POPULAR" ? "heart.fill" : "star.fill").font(.caption).foregroundStyle(Theme.highlight)
                    }
                }.padding(.top, 8)
            }
            .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).companionPanel(padding: 12).accessibilityIdentifier("detail-information")
    }
    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(label).font(.caption2).foregroundStyle(.secondary); Text(value).font(.caption.weight(.medium)) }
    }
    private func studioLinks(_ anime: Anime) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Studio").font(.caption2).foregroundStyle(.secondary)
            let studios = anime.studios?.nodes?.filter { $0.id > 0 } ?? []
            if studios.isEmpty { Text("Not listed").font(.caption) }
            ForEach(studios) { studio in
                NavigationLink { StudioAnimeView(studio: studio) } label: {
                    HStack(spacing: 4) { Text(studio.name).multilineTextAlignment(.leading); Image(systemName: "chevron.right").font(.caption2) }
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent).frame(minHeight: 32, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("detail-studio-\(studio.id)").accessibilityHint("Browse anime by \(studio.name)")
            }
        }
    }
    @ViewBuilder private func related(_ anime: Anime) -> some View {
        let rows = (anime.relations?.edges ?? []).compactMap { edge -> RelatedSeriesShelf.Item? in
            guard let media = edge.node, store.includeAdult || media.isAdult != true else { return nil }
            return .init(anime: media, caption: edge.relationType)
        }
        if !rows.isEmpty { RelatedSeriesShelf(title: "Related", items: rows) }
    }
    @ViewBuilder private func recommendations(_ anime: Anime) -> some View {
        let entries = (anime.recommendations?.nodes ?? []).filter { (store.includeAdult || $0.mediaRecommendation?.isAdult != true) && $0.mediaRecommendation != nil }
        if !entries.isEmpty {
            RelatedSeriesShelf(title: style == .classic ? "Similar" : nil,
                items: entries.compactMap { $0.mediaRecommendation.map { RelatedSeriesShelf.Item(anime: $0, caption: nil) } })
        } else { ContentUnavailableView("No similar titles yet", systemImage: "sparkles") }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Reviews").font(.headline)
                Spacer(minLength: 8)
                AnimeDiscussionsSection(anime: anime)
            }
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
        }.frame(maxWidth: .infinity, alignment: .leading).companionPanel().accessibilityIdentifier("anime-reviews-discussions")
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
    private func load(refresh: Bool = false) async {
        let attempt = UUID(); requestID = attempt; let requestedAdult = store.includeAdult
        let targetID = mediaID
        if anime?.id != targetID { anime = nil; artwork = SeriesArtwork(); selectedTab = style == .classic ? .info : .episodes }
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
