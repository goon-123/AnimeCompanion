import SwiftUI
import AnimeCore

struct DetailCard<Content: View>: View {
    let title: String
    let content: Content
    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) { Text(title).font(.headline); content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(15).background(Theme.surface, in: RoundedRectangle(cornerRadius: 13))
    }
}

struct AnimeDetailHero: View {
    let anime: Anime
    let expand: (URL) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 14) {
                Button { if let url = anime.coverURL { expand(url) } } label: {
                    AnimeCover(anime: anime, width: 98, cornerRadius: 7)
                        .overlay(alignment: .bottomTrailing) { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption2).padding(6).background(.black.opacity(0.65), in: Circle()).padding(5) }
                }.buttonStyle(.plain).disabled(anime.coverURL == nil).accessibilityLabel("Expand anime cover").accessibilityIdentifier("expand-anime-cover")
                VStack(alignment: .leading, spacing: 8) {
                    Text(anime.displayTitle).font(.title3.bold())
                    Text(metadata).font(.caption).foregroundStyle(.secondary)
                    if let score = anime.averageScore { Text("AniList · \(Double(score) / 10, specifier: "%.1f") ★").font(.caption.bold()).foregroundStyle(Theme.highlight) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let genres = anime.genres, !genres.isEmpty { Text(genres.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
        }.padding(.horizontal, 16).padding(.top, 100).padding(.bottom, 18)
            .background(alignment: .top) {
                ZStack(alignment: .bottom) {
                    if let value = anime.bannerImage, let url = URL(string: value) {
                        Button { expand(url) } label: {
                            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Theme.surface }
                                .frame(height: 220).clipped()
                        }.buttonStyle(.plain).accessibilityLabel("Expand anime banner")
                    } else { Theme.surface.frame(height: 220) }
                    LinearGradient(colors: [.clear, Theme.background.opacity(0.65), Theme.background], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
                }.frame(height: 220).clipped()
            }
    }
    private var metadata: String {
        [anime.season.map { $0.label + (anime.seasonYear.map { " \($0)" } ?? "") },
         anime.format?.replacingOccurrences(of: "_", with: " "),
         anime.status?.replacingOccurrences(of: "_", with: " ").capitalized].compactMap { $0 }.joined(separator: " · ")
    }
}

struct BroadcastCountdown: View {
    let episode: AiringEpisode
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(episode.date.timeIntervalSince(context.date)))
            HStack {
                Label("Episode #\(episode.episode)", systemImage: "tv").font(.subheadline.bold())
                Spacer()
                Text(String(format: "%02d  %02d:%02d:%02d", seconds / 86400, seconds % 86400 / 3600, seconds % 3600 / 60, seconds % 60))
                    .font(.subheadline.monospacedDigit().bold())
            }
        }
        Text(episode.date, format: .dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(.secondary)
        Text("Original Japanese broadcast · Device local time").font(.caption2).foregroundStyle(.secondary)
    }
}

struct RelatedAnimeCard: View {
    let anime: RelatedAnime
    var caption: String? = nil
    var body: some View {
        Group {
            if anime.type == "MANGA" { Link(destination: URL(string: "https://anilist.co/manga/\(anime.id)")!) { card } }
            else { NavigationLink(value: AnimeRoute(id: anime.id)) { card } }
        }.buttonStyle(.plain)
    }
    private var card: some View {
        VStack(alignment: .leading, spacing: 7) {
            AsyncImage(url: anime.coverURL) { image in image.resizable().scaledToFill() } placeholder: { Theme.surface }
                .frame(width: 100, height: 145).clipShape(RoundedRectangle(cornerRadius: 7))
            if let caption { Text(caption.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption2).foregroundStyle(Theme.highlight).lineLimit(1) }
            Text(anime.displayTitle).font(.caption.weight(.semibold)).lineLimit(2, reservesSpace: true).foregroundStyle(.primary)
        }.frame(width: 100, alignment: .leading)
    }
}

struct DetailPersonCard: View {
    let name: String
    let imageURL: URL?
    var role: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            AsyncImage(url: imageURL) { image in image.resizable().scaledToFill() } placeholder: { Theme.surface }
                .frame(width: 90, height: 106).clipShape(RoundedRectangle(cornerRadius: 7))
            Text(name).font(.caption.weight(.semibold)).lineLimit(2, reservesSpace: true).foregroundStyle(.primary)
            if let role { Text(role).font(.caption2).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true) }
        }.frame(width: 90, alignment: .leading)
    }
}

struct AnimeDubSchedule: View {
    let status: DubAvailability
    let events: [ReleaseEvent]
    let loading: Bool
    let error: String?
    @State private var expandedHistory = false
    private var upcoming: [ReleaseEvent] { events.filter { $0.date == nil || ($0.date ?? .distantPast) >= Date() } }
    private var recorded: [ReleaseEvent] { events.filter { $0.certainty == .recorded }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) } }

    var body: some View {
        DetailCard(title: "English dub schedule") {
            Label(status.label, systemImage: "mic.fill").font(.subheadline.bold())
            if loading { ProgressView("Checking this anime’s dub releases…") }
            Text("Upcoming releases").font(.subheadline.bold()).padding(.top, 3)
            if !loading && upcoming.isEmpty { Text("No upcoming English dub date is listed for this anime.").font(.caption).foregroundStyle(.secondary) }
            ForEach(upcoming) { event in release(event) }
            if !recorded.isEmpty {
                Divider()
                Text("Recorded releases").font(.subheadline.bold())
                ForEach(expandedHistory ? recorded : Array(recorded.prefix(6))) { event in release(event) }
                if recorded.count > 6 { Button(expandedHistory ? "Show recent episodes" : "Show all \(recorded.count) recorded episodes") { expandedHistory.toggle() }.font(.caption.bold()) }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            Text("Dub dates reported by AniSchedule. Unverified dates are estimates; delays may change.").font(.caption2).foregroundStyle(.secondary)
            Link("Dub availability © MyDubList", destination: URL(string: "https://mydublist.com")!).font(.caption2)
        }.accessibilityIdentifier("anime-dub-schedule")
    }
    private func release(_ event: ReleaseEvent) -> some View {
        HStack(alignment: .top) {
            Text("Episode \(event.episode)").font(.caption.bold())
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let date = event.date { Text(date, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption) }
                else { Text(event.note ?? "Date not confirmed").font(.caption) }
                if event.certainty == .unverified { Text("Unverified").font(.caption2).foregroundStyle(.orange) }
                if event.certainty == .delayed { Text(event.note ?? "Delayed").font(.caption2).foregroundStyle(.orange) }
                if event.certainty == .recorded { Text("Reported released").font(.caption2).foregroundStyle(.mint) }
            }
        }.padding(.vertical, 3)
    }
}
