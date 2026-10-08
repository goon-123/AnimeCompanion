import SwiftUI
import AnimeCore

struct AnimeDetailView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    let mediaID: Int
    @State private var anime: Anime?
    @State private var loading = false
    @State private var error: String?
    @State private var synopsisExpanded = false
    @State private var showSettings = false
    @State private var showPlayback = false
    @State private var imagePreview: AnimeImagePreview?
    @State private var requestID = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if loading && anime == nil { ProgressView("Loading anime…").frame(maxWidth: .infinity).padding(40) }
                if let error { NoticeView(message: error) { Task { await load() } }.padding(.horizontal) }
                if let anime {
                    AnimeDetailHero(anime: anime) { url in imagePreview = AnimeImagePreview(url: url, title: anime.displayTitle) }
                    VStack(alignment: .leading, spacing: 20) {
                        if let next = anime.nextAiringEpisode { DetailCard(title: "Next original broadcast") { BroadcastCountdown(episode: next) } }
                        synopsis(anime)
                        metadata(anime)
                        progress(anime)
                        Button { showPlayback = true } label: {
                            Label("Watch in VidHub", systemImage: "play.rectangle.fill").frame(maxWidth: .infinity).padding(.vertical, 5)
                        }.buttonStyle(.bordered).controlSize(.large).disabled(anime.status == "NOT_YET_RELEASED")
                            .accessibilityIdentifier("watch-in-vidhub")
                        AnimeDubSchedule(anime: anime, progress: dubs.progress(for: anime), snapshot: dubs.snapshot,
                                         events: dubEvents(for: anime), loading: dubs.loading, error: dubs.notice)
                        related(anime)
                        characters(anime)
                        staff(anime)
                        recommendations(anime)
                        trailer(anime)
                        reviews(anime)
                        externalLinks(anime)
                        Link("View on AniList", destination: URL(string: "https://anilist.co/anime/\(anime.id)")!).font(.caption).padding(.bottom)
                    }.padding(.horizontal, 14)
                }
            }.readableContent(width: 940)
        }.background(Theme.background).navigationTitle("Anime").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel("Account and settings")
                }
            }
            .task(id: mediaID) { await load() }.refreshable { await load(refresh: true) }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showPlayback) { if let anime { WatchAnimeView(anime: anime) } }
            .fullScreenCover(item: $imagePreview) { AnimeImageViewer(preview: $0) }
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
            if store.isSignedIn { ProgressControl(anime: anime) }
            else { Button("Connect AniList") { showSettings = true }.buttonStyle(.bordered) }
        }
    }
    @ViewBuilder private func related(_ anime: Anime) -> some View {
        if let edges = anime.relations?.edges, !edges.isEmpty {
            sectionTitle("Related")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(edges.enumerated()), id: \.offset) { _, edge in
                        if let media = edge.node, media.isAdult != true { RelatedAnimeCard(anime: media, caption: edge.relationType) }
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
        let entries = (anime.recommendations?.nodes ?? []).filter { $0.mediaRecommendation?.isAdult != true && $0.mediaRecommendation != nil }
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
                    AsyncImage(url: URL(string: trailer.thumbnail ?? "")) { image in image.resizable().scaledToFill() } placeholder: { Theme.surface }
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
    private func sectionTitle(_ title: String) -> some View { Text(title).font(.headline).padding(.top, 3) }
    private func dubEvents(for anime: Anime) -> [ReleaseEvent] {
        dubs.snapshot?.events(knownMedia: [anime.id: anime]).filter { $0.anime.id == anime.id } ?? []
    }
    private func load(refresh: Bool = false) async {
        let attempt = UUID(); requestID = attempt
        if anime?.id != mediaID { anime = nil }
        loading = true; error = nil
        defer { if requestID == attempt { loading = false } }
        do {
            let media = try await store.aniList.details(id: mediaID)
            try Task.checkCancellation(); guard requestID == attempt else { return }
            anime = media
            await dubs.load(using: store.dubs, refresh: refresh)
        } catch is CancellationError {} catch { if requestID == attempt { self.error = error.localizedDescription } }
    }
}

