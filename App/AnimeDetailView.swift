import SwiftUI
import AnimeCore

struct AnimeDetailView: View {
    @EnvironmentObject private var store: AppStore
    let mediaID: Int
    @State private var anime: Anime?
    @State private var loading = false
    @State private var error: String?
    @State private var dubStatus = DubAvailability.unknown
    @State private var dubEvents: [ReleaseEvent] = []
    @State private var dubError: String?
    @State private var loadingDub = false
    @State private var showSettings = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if loading && anime == nil { ProgressView("Loading anime…").frame(maxWidth: .infinity).padding(40) }
                if let error { NoticeView(message: error) { Task { await load() } } }
                if let anime {
                    if let banner = anime.bannerImage, let url = URL(string: banner) {
                        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Theme.surface }
                            .frame(height: 150).clipped().clipShape(RoundedRectangle(cornerRadius: 18)).accessibilityHidden(true)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        AnimeCover(anime: anime, width: 95)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(anime.displayTitle).font(.title2.bold())
                            if let score = anime.averageScore { Label("\(score)% AniList", systemImage: "star.fill").font(.subheadline) }
                            Text([anime.format?.replacingOccurrences(of: "_", with: " "), anime.seasonYear.map(String.init), anime.episodes.map { "\($0) episodes" }].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            if let status = anime.status { Text(status.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if let next = anime.nextAiringEpisode {
                        infoCard("Next original broadcast") {
                            Text("Episode \(next.episode)").font(.headline)
                            Text(next.date, format: .dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
                            Text("Japanese broadcast · Local subtitle release may differ").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    infoCard("English dub") {
                        if loadingDub { ProgressView("Checking dub information…") }
                        Label(dubStatus.label, systemImage: "mic").font(.headline)
                        if let latest = dubEvents.last(where: { $0.certainty == .recorded }) { Text("Episode \(latest.episode) reported released").font(.subheadline) }
                        ForEach(Array(dubEvents.filter { $0.date == nil || ($0.date ?? .distantPast) >= Date() }.prefix(5))) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Episode \(event.episode)").font(.subheadline.weight(.semibold))
                                if let date = event.date { Text(date, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.subheadline) }
                                else { Text(event.note ?? "Date not confirmed").font(.subheadline) }
                                if event.certainty == .unverified { Text("Unverified date from source").font(.caption).foregroundStyle(.orange) }
                                if event.certainty == .delayed { Text(event.note ?? "Delayed").font(.caption).foregroundStyle(.orange) }
                            }
                        }
                        if !loadingDub && !dubEvents.contains(where: { $0.date == nil || ($0.date ?? .distantPast) >= Date() }) {
                            Text("No upcoming dub date listed.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let dubError { Text(dubError).font(.caption).foregroundStyle(.secondary) }
                        Link("Powered by MyDubList", destination: URL(string: "https://mydublist.com")!).font(.caption)
                        Text("Dates reported by AniSchedule. They may change.").font(.caption).foregroundStyle(.secondary)
                    }
                    infoCard("Your progress") {
                        if store.isSignedIn { ProgressControl(anime: anime) }
                        else { Button("Connect AniList") { showSettings = true }.buttonStyle(.borderedProminent) }
                    }
                    infoCard("Overview") {
                        Text(anime.synopsis).font(.body)
                        if let genres = anime.genres, !genres.isEmpty { Text(genres.joined(separator: " · ")).font(.subheadline).foregroundStyle(Theme.accent) }
                        if let studios = anime.studios?.nodes, !studios.isEmpty { Text("Studio: " + studios.map(\.name).joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    if let characters = anime.characters?.nodes, !characters.isEmpty {
                        Text("Characters").font(.title3.bold())
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(characters) { character in
                                    VStack(spacing: 8) {
                                        AsyncImage(url: URL(string: character.image?.medium ?? "")) { image in image.resizable().scaledToFill() }
                                        placeholder: { Theme.surface }
                                            .frame(width: 64, height: 64).clipShape(Circle()).accessibilityHidden(true)
                                        Text(character.name?.full ?? "Character").font(.caption).lineLimit(2).multilineTextAlignment(.center)
                                    }.frame(width: 76)
                                }
                            }
                        }
                    }
                    if let relations = anime.relations?.edges, !relations.isEmpty {
                        infoCard("Related anime") {
                            ForEach(Array(relations.enumerated()), id: \.offset) { _, edge in
                                if let related = edge.node, related.type == "ANIME" {
                                    NavigationLink(value: AnimeRoute(id: related.id)) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(related.title?.english ?? related.title?.romaji ?? "Anime #\(related.id)")
                                            Text((edge.relationType ?? "Related").replacingOccurrences(of: "_", with: " ").capitalized).font(.caption).foregroundStyle(.secondary)
                                        }.padding(.vertical, 6)
                                    }
                                }
                            }
                        }
                    }
                    if let trailer = anime.trailer?.url { Link(destination: trailer) { Label("Watch trailer", systemImage: "play.rectangle").frame(maxWidth: .infinity) }.buttonStyle(.bordered) }
                    Link("View on AniList", destination: URL(string: "https://anilist.co/anime/\(anime.id)")!).font(.subheadline)
                }
            }.padding()
        }.background(Theme.background).navigationTitle("Anime").navigationBarTitleDisplayMode(.inline)
            .task(id: mediaID) { await load() }.refreshable { await load() }.sheet(isPresented: $showSettings) { SettingsView() }
    }
    private func infoCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { Text(title).font(.title3.bold()); content() }
            .frame(maxWidth: .infinity, alignment: .leading).padding().background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let media = try await store.aniList.details(id: mediaID)
            try Task.checkCancellation(); anime = media
            await loadDub(media)
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func loadDub(_ anime: Anime) async {
        loadingDub = true; dubError = nil; dubStatus = .unknown; dubEvents = []
        defer { loadingDub = false }
        // Keep availability and dates independent when one source is temporarily unavailable.
        async let status: Void = loadDubStatus(anime)
        async let schedule: Void = loadDubDates(anime)
        _ = await (status, schedule)
    }
    private func loadDubStatus(_ anime: Anime) async {
        do { dubStatus = try await store.dubs.availability(malId: anime.idMal) }
        catch { dubError = "Dub availability could not be checked." }
    }
    private func loadDubDates(_ anime: Anime) async {
        do { dubEvents = try await store.dubs.snapshot().events(knownMedia: [anime.id: anime]).filter { $0.anime.id == anime.id } }
        catch { dubError = "Dub dates could not be loaded." }
    }
}
