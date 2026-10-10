import SwiftUI
import AnimeCore

struct DetailCard<Content: View>: View {
    let title: String
    let content: Content
    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) { Text(title).font(.headline); content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Theme.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.04), lineWidth: 1) }
    }
}

struct AnimeDetailHero: View {
    @EnvironmentObject private var dubs: ExploreDubStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    let anime: Anime
    let expand: (URL) -> Void
    private var bannerHeight: CGFloat { sizeClass == .regular ? 400 : 300 }
    private var posterWidth: CGFloat { sizeClass == .regular ? 150 : 108 }
    private var artworkURL: URL? { anime.bannerImage.flatMap(URL.init(string:)) ?? anime.coverURL }
    private var accent: Color { (PosterAccent(hex: anime.coverImage?.color)?.backdrop ?? PosterAccent.fallback.backdrop).color }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 18) { poster; information }
                VStack(alignment: .leading, spacing: 16) { poster; information }
            }
            AnimeGenres(anime: anime).accessibilityIdentifier("detail-genres-\(anime.id)")
        }.padding(.horizontal, 18).padding(.top, bannerHeight - 90).padding(.bottom, 10)
            .readableContent(width: 940).frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .top) {
                GeometryReader { geometry in
                    ZStack(alignment: .top) {
                        Theme.background
                        Button { if let artworkURL { expand(artworkURL) } } label: {
                            AsyncImage(url: artworkURL) { image in image.resizable().scaledToFill() } placeholder: { accent }
                                .frame(width: geometry.size.width, height: bannerHeight).clipped()
                        }.buttonStyle(.plain).disabled(artworkURL == nil)
                            .accessibilityLabel("Expand anime banner").accessibilityIdentifier("expand-anime-banner")
                        LinearGradient(stops: [.init(color: .black.opacity(0.08), location: 0),
                            .init(color: Theme.background.opacity(0.12), location: 0.30),
                            .init(color: Theme.background.opacity(0.88), location: 0.73),
                            .init(color: Theme.background, location: 1)], startPoint: .top, endPoint: .bottom)
                            .frame(height: bannerHeight + 80).allowsHitTesting(false)
                    }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
            }
    }
    private var poster: some View {
        Button { if let url = anime.coverURL { expand(url) } } label: {
            AnimeCover(anime: anime, width: posterWidth, cornerRadius: 12)
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.16), lineWidth: 1) }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.caption2)
                        .padding(7).background(.black.opacity(0.70), in: Circle()).padding(6)
                }.shadow(color: .black.opacity(0.45), radius: 15, y: 6)
        }.buttonStyle(.plain).disabled(anime.coverURL == nil)
            .accessibilityLabel("Expand anime cover").accessibilityIdentifier("expand-anime-cover")
    }
    private var information: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if anime.isCurrentlyAiring { Circle().fill(.green).frame(width: 6, height: 6).accessibilityHidden(true) }
                Text(statusLabel).font(.caption.weight(.semibold)).foregroundStyle(anime.isCurrentlyAiring ? Color.green : Color.secondary)
                    .accessibilityIdentifier("detail-release-status")
            }
            Text(anime.displayTitle).font(sizeClass == .regular ? .largeTitle.bold() : .title2.bold())
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("detail-title")
            Text([anime.season.map { $0.label + (anime.seasonYear.map { " \($0)" } ?? "") },
                  anime.format?.replacingOccurrences(of: "_", with: " ")].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            if let score = anime.averageScore {
                Label("AniList · \(Double(score) / 10, specifier: "%.1f")", systemImage: "star.fill")
                    .font(.caption.bold()).foregroundStyle(Theme.highlight)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(Theme.highlight.opacity(0.10), in: Capsule())
            }
            DubStatusBadge(anime: anime, progress: dubs.progress(for: anime))
                .accessibilityIdentifier("detail-dub-summary")
        }.frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
    }
    private var statusLabel: String {
        switch anime.status {
        case "RELEASING": return "Airing now"
        case "FINISHED": return "Finished"
        case "NOT_YET_RELEASED": return "Upcoming"
        case "HIATUS": return "On hiatus"
        case "CANCELLED": return "Cancelled"
        default: return "Anime"
        }
    }
}

struct BroadcastCountdown: View {
    let episode: AiringEpisode
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Episode \(episode.episode)", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline).foregroundStyle(.green)
                Spacer()
                Text("ORIGINAL BROADCAST").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(0, Int(episode.date.timeIntervalSince(context.date)))
                if seconds > 0 {
                    HStack(spacing: 8) {
                        timePart(seconds / 86400, label: "Days")
                        timePart(seconds % 86400 / 3600, label: "Hours")
                        timePart(seconds % 3600 / 60, label: "Minutes")
                        timePart(seconds % 60, label: "Seconds")
                    }.accessibilityElement(children: .combine)
                        .accessibilityIdentifier("detail-countdown")
                } else {
                    Text("Scheduled broadcast time reached. Refresh to check the next episode.").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text(episode.date, format: .dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
                .font(.caption).foregroundStyle(.secondary)
            Text("Original Japanese broadcast · Device local time").font(.caption2).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(Color.green.opacity(0.18), lineWidth: 1) }
    }
    private func timePart(_ number: Int, label: String) -> some View {
        VStack(spacing: 5) {
            Text(String(format: "%02d", number)).font(.title2.bold().monospacedDigit()).contentTransition(.numericText())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
    }
}

struct RelatedAnimeCard: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let anime: RelatedAnime
    var caption: String? = nil
    var body: some View {
      VStack(alignment: .leading, spacing: 3) {
        Group {
            if anime.type == "MANGA" { Link(destination: URL(string: "https://anilist.co/manga/\(anime.id)")!) { card } }
            else { NavigationLink(value: AnimeRoute(id: anime.id)) { card } }
        }.buttonStyle(.plain)
        GenreTags(genres: anime.genres ?? [], animeID: anime.id)
      }.frame(width: sizeClass == .regular ? 145 : 100, alignment: .leading)
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
        }
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

