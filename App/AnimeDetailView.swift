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
    @Environment(\.horizontalSizeClass) private var sizeClass
    let mediaID: Int
    @State private var anime: Anime?
    @State private var loading = false
    @State private var error: String?
    @State private var synopsisExpanded = false
    @State private var showSettings = false
    @State private var playbackRequest: DetailPlaybackRequest?
    @State private var episodesExpanded = false
    @State private var moreExpanded = false
    @State private var episodeLimit = 24
    @State private var imagePreview: AnimeImagePreview?
    @State private var requestID = UUID()
    @State private var liveChartMediaID: Int?

    var body: some View {
        Group {
          if store.metadataSource == .liveChart, let anime, store.isVisible(anime) {
            LiveChartAnimeView(anime: anime) { liveChartMediaID = $0.id }
          } else {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if loading && anime == nil { ProgressView("Loading anime…").frame(maxWidth: .infinity).padding(40) }
                if let error { NoticeView(message: error) { Task { await load() } }.padding(.horizontal) }
                if let anime, !store.isVisible(anime) {
                    ContentUnavailableView("Adult content is hidden", systemImage: "eye.slash", description: Text("Enable adult anime in Settings to view this title."))
                    Button("Open content settings") { showSettings = true }.buttonStyle(.bordered)
                }
                if let anime, store.isVisible(anime) {
                    AnimeDetailHero(anime: anime) { url in imagePreview = AnimeImagePreview(url: url, title: anime.displayTitle) }
                    VStack(alignment: .leading, spacing: 20) {
                        watchButton(anime)
                        FindMangaButton(anime: anime)
                        if anime.isCurrentlyAiring, let next = anime.nextAiringEpisode { BroadcastCountdown(episode: next) }
                        progress(anime)
                        AnimeDubSchedule(anime: anime, progress: dubs.progress(for: anime), snapshot: dubs.snapshot,
                                         events: dubEvents(for: anime), loading: dubs.loading, error: dubs.notice)
                        synopsis(anime)
                        episodes(anime)
                        related(anime)
                        recommendations(anime)
                        DetailDisclosure("More information", identifier: "detail-more-information", isExpanded: $moreExpanded) {
                            VStack(alignment: .leading, spacing: 20) {
                                metadata(anime)
                                characters(anime)
                                staff(anime)
                                trailer(anime)
                                reviews(anime)
                                externalLinks(anime)
                                Link("View on AniList", destination: URL(string: "https://anilist.co/anime/\(anime.id)")!).font(.caption)
                            }.padding(.top, 14)
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 24).readableContent(width: 940)
                }
            }
        }.accessibilityIdentifier("anime-detail-scroll").background(Theme.background).navigationTitle("Anime").navigationBarTitleDisplayMode(.inline)
          }
        }.navigationTitle("Anime").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) { MetadataSourcePicker().padding(.horizontal, 16).padding(.vertical, 10).background(.ultraThinMaterial) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel("Account and settings")
                }
            }
            .task(id: "\(mediaID)-\(store.includeAdult)-\(store.metadataSource.rawValue)") { await load() }.refreshable { await load(refresh: true) }
            .appSettingsSheet(isPresented: $showSettings)
            .sheet(item: $playbackRequest) { request in
                if let anime { WatchAnimeView(anime: anime, requestedEpisode: request.episode) }
            }
            .fullScreenCover(item: $imagePreview) { AnimeImageViewer(preview: $0) }
    }
    private func watchButton(_ anime: Anime) -> some View {
        let entry = store.entry(for: anime.id)
        let episode = PlaybackEpisodeSelection.initial(anime: anime, entry: entry, resumeEpisode: playback.resumeEpisode(animeID: anime.id))
        let finished = anime.episodes.map { $0 > 0 && (entry?.progressValue ?? 0) >= $0 } ?? false
        let label = anime.format == "MOVIE" ? "Watch movie" : (finished ? "Replay episode \(episode)" : ((entry?.progressValue ?? 0) > 0 ? "Resume episode \(episode)" : "Watch episode \(episode)"))
        return Button { playbackRequest = DetailPlaybackRequest(episode: nil) } label: {
            HStack(spacing: 14) {
                Image(systemName: "play.fill").font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.headline).accessibilityIdentifier("detail-resume-episode")
                    Text("Watch in VidHub").font(.caption).opacity(0.65)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.subheadline.bold())
            }.padding(16).foregroundStyle(.black).background(.white, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).disabled(anime.status == "NOT_YET_RELEASED" || (store.isSignedIn && store.loadingLibrary))
            .accessibilityIdentifier("watch-in-vidhub")
    }
    private func episodes(_ anime: Anime) -> some View {
        let entry = store.entry(for: anime.id)
        let next = PlaybackEpisodeSelection.initial(anime: anime, entry: entry, resumeEpisode: nil)
        let listed = AnimeEpisodeCatalog.episodes(anime: anime, visibleLimit: episodeLimit)
        let released = LibraryAiringProgress(anime: anime, watched: entry?.progressValue ?? 0)?.released
        return DetailCard(title: "Episodes") {
            Text(anime.format == "MOVIE" ? "Movie" : (anime.episodes.flatMap { $0 > 0 ? $0 : nil }.map { "\($0) episodes planned" } ?? "Episode total not announced"))
                .font(.caption).foregroundStyle(.secondary)
            DetailDisclosure("Choose an episode", identifier: "detail-episodes-disclosure", isExpanded: $episodesExpanded) {
                if listed.isEmpty {
                    Text("No episode list is supplied by the metadata source. Choose an episode number in Watch in VidHub.")
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(listed, id: \.self) { episode in
                            let watched = episode <= (entry?.progressValue ?? 0)
                            let upcoming = anime.status == "NOT_YET_RELEASED" || (released.map { episode > $0 } ?? false)
                            Button { playbackRequest = DetailPlaybackRequest(episode: episode) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: watched ? "checkmark.circle.fill" : (upcoming ? "clock" : "play.circle"))
                                        .foregroundStyle(watched ? Color.green : Color.secondary)
                                    Text(anime.format == "MOVIE" ? "Watch movie" : "Episode \(episode)").font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text(watched ? "Watched" : (upcoming ? "Upcoming" : (episode == next ? "Next unwatched" : "Find sources")))
                                        .font(.caption).foregroundStyle(.secondary)
                                }.frame(minHeight: 48).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(upcoming).accessibilityIdentifier("detail-episode-\(episode)")
                            Divider()
                        }
                    }
                    if let total = anime.episodes, listed.count < min(100_000, total) {
                        Button("Show next \(min(24, total - listed.count)) episodes") { episodeLimit = min(100_000, episodeLimit + 24) }
                            .font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("detail-more-episodes")
                    }
                }
                Text("Episode listings do not confirm stream or English audio availability. Choose an episode to check sources; tracking changes only with your watched-progress controls.")
                    .font(.caption2).foregroundStyle(.secondary).padding(.top, 8)
            }
        }
    }
    private func synopsis(_ anime: Anime) -> some View {
        DetailCard(title: "Synopsis") {
            Text(anime.synopsis).font(.subheadline).foregroundStyle(.secondary).lineLimit(synopsisExpanded ? nil : 4)
            Button(synopsisExpanded ? "Show less" : "Read more") { synopsisExpanded.toggle() }.font(.caption.bold())
                .accessibilityIdentifier("expand-synopsis")
        }
    }
    private func metadata(_ anime: Anime) -> some View {
        DetailCard(title: "Information") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: sizeClass == .regular ? 3 : 2), alignment: .leading, spacing: 16) {
                fact("Releasing", (anime.startDate?.label ?? "Not announced") + (anime.endDate?.year == nil ? "" : " – " + (anime.endDate?.label ?? "")))
                fact("Episodes", anime.episodes.map(String.init) ?? "Not announced")
                fact("Duration", anime.duration.map { "\($0) min" } ?? "Not announced")
                fact("Studio", anime.studios?.nodes?.map(\.name).joined(separator: ", ") ?? "Not listed")
                fact("Popularity", anime.popularity.map { $0.formatted() } ?? "Not listed")
                fact("Favourites", anime.favourites.map { $0.formatted() } ?? "Not listed")
            }
            if let ranks = anime.rankings, !ranks.isEmpty {
                Divider()
                ForEach(Array(ranks.prefix(4))) { rank in Label(rank.label, systemImage: rank.type == "POPULAR" ? "heart.fill" : "star.fill").font(.caption).foregroundStyle(Theme.highlight) }
            }
        }
    }
    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(label).font(.caption2).foregroundStyle(.secondary); Text(value).font(.caption.weight(.medium)) }
    }
    private func progress(_ anime: Anime) -> some View {
        DetailCard(title: "Your progress") {
            if store.isSignedIn {
                if let entry = store.entry(for: anime.id), let status = LibraryAiringProgress(anime: anime, watched: entry.progressValue,
                    source: store.airingProgressSource, dub: dubs.progress(for: anime), nextDub: dubs.nextDub(for: anime.id)) {
                    LibraryAiringStatus(status: status, animeID: anime.id)
                }
                ProgressControl(anime: anime)
            }
            else { Button("Connect AniList") { showSettings = true }.buttonStyle(.bordered) }
        }
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
    @ViewBuilder private func characters(_ anime: Anime) -> some View {
        if let people = anime.characters?.nodes, !people.isEmpty {
            sectionTitle("Characters")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(people) { person in
                        Link(destination: URL(string: "https://anilist.co/character/\(person.id)")!) {
                            DetailPersonCard(name: person.name?.full ?? "Character", imageURL: URL(string: person.image?.medium ?? ""))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
    @ViewBuilder private func staff(_ anime: Anime) -> some View {
        if let edges = anime.staff?.edges, !edges.isEmpty {
            sectionTitle("Staff")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(edges.enumerated()), id: \.offset) { _, edge in
                        if let person = edge.node {
                            Link(destination: URL(string: "https://anilist.co/staff/\(person.id)")!) {
                                DetailPersonCard(name: person.name?.full ?? "Staff", imageURL: URL(string: person.image?.large ?? person.image?.medium ?? ""), role: edge.role)
                            }.buttonStyle(.plain)
                        }
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
        let targetID = liveChartMediaID ?? mediaID
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

struct FindMangaButton: View {
    @EnvironmentObject private var navigation: AppNavigationStore
    let anime: Anime
    var body: some View {
        Button { navigation.openMangaSearch(for: anime) } label: {
            HStack(spacing: 14) {
                Image(systemName: "book.closed").font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Find manga or manhwa").font(.subheadline.weight(.semibold))
                    Text("Search your installed manga sources").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.subheadline)
            }.padding(16).foregroundStyle(MangaStyle.accent).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityIdentifier("detail-find-manga")
    }
}

