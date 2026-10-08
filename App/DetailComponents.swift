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
    @Environment(\.horizontalSizeClass) private var sizeClass
    let anime: Anime
    let expand: (URL) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 14) {
                Button { if let url = anime.coverURL { expand(url) } } label: {
                    AnimeCover(anime: anime, width: sizeClass == .regular ? 160 : 98, cornerRadius: 7)
                        .overlay(alignment: .bottomTrailing) { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption2).padding(6).background(.black.opacity(0.65), in: Circle()).padding(5) }
                }.buttonStyle(.plain).disabled(anime.coverURL == nil).accessibilityLabel("Expand anime cover").accessibilityIdentifier("expand-anime-cover")
                VStack(alignment: .leading, spacing: 8) {
                    Text(anime.displayTitle).font(sizeClass == .regular ? .title.bold() : .title3.bold())
                    Text(metadata).font(sizeClass == .regular ? .subheadline : .caption).foregroundStyle(.secondary)
                    if let score = anime.averageScore { Text("AniList · \(Double(score) / 10, specifier: "%.1f") ★").font(.caption.bold()).foregroundStyle(Theme.highlight) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let genres = anime.genres, !genres.isEmpty { Text(genres.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
        }.padding(.horizontal, 16).padding(.top, sizeClass == .regular ? 130 : 100).padding(.bottom, 18)
            .background(alignment: .top) {
              GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    if let value = anime.bannerImage, let url = URL(string: value) {
                        Button { expand(url) } label: {
                            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Theme.surface }
                                .frame(width: geometry.size.width, height: sizeClass == .regular ? 340 : 220).clipped()
                        }.buttonStyle(.plain).accessibilityLabel("Expand anime banner")
                    } else { Theme.surface.frame(height: sizeClass == .regular ? 340 : 220) }
                    LinearGradient(colors: [.clear, Theme.background.opacity(0.65), Theme.background], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
                }.frame(height: sizeClass == .regular ? 340 : 220).clipped()
              }
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
    @Environment(\.horizontalSizeClass) private var sizeClass
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
                .frame(width: sizeClass == .regular ? 145 : 100, height: sizeClass == .regular ? 210 : 145).clipShape(RoundedRectangle(cornerRadius: 7))
            if let caption { Text(caption.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption2).foregroundStyle(Theme.highlight).lineLimit(1) }
            Text(anime.displayTitle).font(.caption.weight(.semibold)).lineLimit(2, reservesSpace: true).foregroundStyle(.primary)
        }.frame(width: sizeClass == .regular ? 145 : 100, alignment: .leading)
    }
}

struct DetailPersonCard: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let name: String
    let imageURL: URL?
    var role: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            AsyncImage(url: imageURL) { image in image.resizable().scaledToFill() } placeholder: { Theme.surface }
                .frame(width: sizeClass == .regular ? 120 : 90, height: sizeClass == .regular ? 142 : 106).clipShape(RoundedRectangle(cornerRadius: 7))
            Text(name).font(.caption.weight(.semibold)).lineLimit(2, reservesSpace: true).foregroundStyle(.primary)
            if let role { Text(role).font(.caption2).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true) }
        }.frame(width: sizeClass == .regular ? 120 : 90, alignment: .leading)
    }
}

struct AnimeDubSchedule: View {
    let anime: Anime
    let progress: LibraryDubProgress?
    let snapshot: DubSnapshot?
    let events: [ReleaseEvent]
    let loading: Bool
    let error: String?
    @State private var expandedHistory = false
    private var upcoming: [ReleaseEvent] { events.filter { $0.date == nil || ($0.date ?? .distantPast) >= Date() } }
    private var recorded: [ReleaseEvent] { events.filter { $0.certainty == .recorded }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) } }

    var body: some View {
        DetailCard(title: "English dub schedule") {
            DubStatusBadge(anime: anime, progress: progress).accessibilityIdentifier("detail-dub-count")
            if let progress {
                if let total = anime.episodes, total > 0 { Text("\(total) episodes planned for this title").font(.caption).foregroundStyle(.secondary) }
                Text(progress.explanation).font(.caption).foregroundStyle(.secondary)
                if let date = progress.lastReleaseAt {
                    Text("Latest reported dub release: \(date.formatted(.dateTime.month(.abbreviated).day().year()))").font(.caption).foregroundStyle(.secondary)
                }
                if let sources = progress.agreeingSources {
                    Text("Dub availability supported by \(sources) \(sources == 1 ? "source" : "sources") via MyDubList.")
                        .font(.caption).foregroundStyle(progress.tone.color).accessibilityIdentifier("detail-dub-source-count")
                }
            }
            if loading { ProgressView("Checking this anime’s dub releases…") }
            Text("Upcoming releases").font(.subheadline.bold()).padding(.top, 3)
            if !loading && upcoming.isEmpty {
                Text(progress?.completeListing == true ? "No further dub episodes are expected from the completed listing." : "No next dub date is supplied by the release sources yet. Pull to refresh to check again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(upcoming) { event in release(event) }
            if !recorded.isEmpty {
                Divider()
                Text("Recorded releases").font(.subheadline.bold())
                ForEach(expandedHistory ? recorded : Array(recorded.prefix(6))) { event in release(event) }
                if recorded.count > 6 { Button(expandedHistory ? "Show recent episodes" : "Show all \(recorded.count) recorded episodes") { expandedHistory.toggle() }.font(.caption.bold()) }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            Text("Green shows reported releases or availability. Amber marks estimates; yellow marks announcements. Release reports can differ from availability in your streaming service or region.").font(.caption2).foregroundStyle(.secondary)
            if let snapshot {
                Text("Checked \(snapshot.fetchedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))").font(.caption2).foregroundStyle(.secondary)
                if let updated = snapshot.historyUpdatedAt { Text("Episode feed updated \(updated.formatted(.dateTime.month(.abbreviated).day().hour().minute()))").font(.caption2).foregroundStyle(.secondary) }
                ForEach(Array(Set([snapshot.historyProvider, snapshot.scheduleProvider].compactMap { $0 })).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { provider in
                    Link("Dub episodes and dates · \(provider.label)", destination: provider.repositoryURL).font(.caption2)
                }
            }
            Link("Check AnimeSchedule", destination: snapshot?.schedulePage(for: anime) ?? URL(string: "https://animeschedule.net")!).font(.caption2)
            Link("Dub availability © MyDubList", destination: URL(string: "https://mydublist.com")!).font(.caption2)
        }.accessibilityIdentifier("anime-dub-schedule")
    }
    private func release(_ event: ReleaseEvent) -> some View {
        HStack(alignment: .top) {
            Text("Episode \(event.episode)").font(.caption.bold())
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let date = event.date { Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()).font(.caption) }
                else { Text(event.note ?? "Date not confirmed").font(.caption) }
                if event.certainty == .unverified { Text("Estimated date").font(.caption2).foregroundStyle(.orange) }
                if event.certainty == .delayed { Text(event.note ?? "Delayed").font(.caption2).foregroundStyle(.orange) }
                if event.certainty == .recorded { Text("Reported released").font(.caption2).foregroundStyle(.mint) }
            }
        }.padding(.vertical, 3)
    }
}

