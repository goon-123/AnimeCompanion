import SwiftUI
import AnimeCore

struct DetailCard<Content: View>: View {
    let title: String
    let content: Content
    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) { Text(title).font(.headline); content }
            .frame(maxWidth: .infinity, alignment: .leading).companionPanel()
    }
}

/// The accessibility identifier belongs only to the toggle button. Assigning
/// it to a containing group can overwrite identifiers of episode actions.
struct DetailDisclosure<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let identifier: String
    @Binding var isExpanded: Bool
    let content: Content
    init(_ title: String, identifier: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title; self.identifier = identifier; _isExpanded = isExpanded; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { isExpanded.toggle() } label: {
                HStack(spacing: 12) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down").font(.caption.bold())
                        .accessibilityHidden(true)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier(identifier)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            if isExpanded { content.transition(.opacity) }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isExpanded)
    }
}

/// A compact broadcast summary, distinct from the larger Home countdown widgets.
struct AnimeOriginalBroadcast: View {
    let anime: Anime
    var body: some View {
        Group {
            if AnimeSeriesContent.showsOriginalBroadcast(for: anime), let next = anime.nextAiringEpisode {
                BroadcastCountdown(episode: next)
            } else if AnimeSeriesContent.showsOriginalBroadcast(for: anime) {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right").font(.title3).foregroundStyle(Theme.accent)
                        .frame(width: 38, height: 38).background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Original broadcast").font(.subheadline.weight(.semibold))
                        Text("Next episode time not announced")
                            .font(.caption).foregroundStyle(.secondary)
                        if let start = anime.startDate?.label { Text("First release · " + start).font(.caption2).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.companionPanel(padding: 14)
            }
        }.accessibilityIdentifier("detail-original-broadcast")
    }
}

struct BroadcastCountdown: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let episode: AiringEpisode
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let seconds = max(0, Int(episode.date.timeIntervalSince(context.date)))
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.title3).foregroundStyle(Theme.accent)
                    .frame(width: 38, height: 38).background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Original broadcast").font(.subheadline.weight(.semibold))
                    Text("Episode \(episode.episode) · " + episode.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if textSize.isAccessibilitySize { countdown(seconds) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !textSize.isAccessibilitySize { countdown(seconds) }
            }.companionPanel(padding: 14)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Original Japanese broadcast in device local time")
        }
    }
    private func countdown(_ seconds: Int) -> some View {
        let days = seconds / 86400, hours = seconds % 86400 / 3600, minutes = seconds % 3600 / 60
        let label = seconds == 0 ? "Time reached" : (days > 0 ? "In \(days)d \(hours)h" : (hours > 0 ? "In \(hours)h \(minutes)m" : (minutes > 0 ? "In \(minutes)m" : "Under 1m")))
        return Text(label).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.accent)
            .padding(.horizontal, 10).padding(.vertical, 7).background(Theme.accent.opacity(0.1), in: Capsule())
            .fixedSize().accessibilityIdentifier("detail-countdown")
    }
}

struct RelatedAnimeCard: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.seriesPosterWidth) private var posterWidth
    let anime: RelatedAnime
    var caption: String? = nil
    var body: some View {
      VStack(alignment: .leading, spacing: 3) {
        Group {
            if anime.type == "MANGA" {
                NavigationLink(value: RelatedMangaBakaRoute(media: anime)) { card }
                    .accessibilityIdentifier("related-mangabaka-\(anime.id)")
            } else {
                AnimeLink(id: anime.id) { card }.accessibilityIdentifier("related-anime-\(anime.id)")
            }
        }.buttonStyle(.plain)
        GenreTags(genres: anime.genres ?? [], animeID: anime.id)
      }.frame(width: posterWidth, alignment: .leading)
    }
    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            if anime.type == "MANGA" {
                ArtworkImage(url: anime.coverURL, pointSize: posterWidth * 1.45) { image in image.resizable().scaledToFill() } placeholder: { Theme.surface }
                    .frame(width: posterWidth, height: posterWidth * 1.45).clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                AnimeCover(anime: Anime(related: anime), width: posterWidth,
                    cornerRadius: 14, identifierPrefix: "related")
            }
            if let caption { Text(caption.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption2).foregroundStyle(Theme.highlight).lineLimit(1) }
            Text(anime.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2, reservesSpace: true).foregroundStyle(.primary)
        }.frame(width: posterWidth, alignment: .leading)
    }
}

struct DetailPersonCard: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let name: String
    let imageURL: URL?
    var role: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ArtworkImage(url: imageURL, pointSize: sizeClass == .regular ? 142 : 106) { image in image.resizable().scaledToFill() } placeholder: { Theme.surface }
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
    var showExpandedDetails = false
    @State private var expandedHistory = false
    @State private var expandedSchedule = false
    private var upcoming: [ReleaseEvent] { events.filter { $0.date == nil || ($0.date ?? .distantPast) >= Date() } }
    private var recorded: [ReleaseEvent] { events.filter { $0.certainty == .recorded }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) } }

    var body: some View {
        DetailCard(title: "English dub schedule") {
            DubStatusBadge(anime: anime, progress: progress).accessibilityIdentifier("detail-dub-count")
            if let sources = progress?.agreeingSources {
                Text("Dub availability supported by \(sources) \(sources == 1 ? "source" : "sources") via MyDubList.")
                    .font(.caption).foregroundStyle(progress?.tone.color ?? .secondary).accessibilityIdentifier("detail-dub-source-count")
            }
            if loading { ProgressView("Checking this anime’s dub releases…") }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            if showExpandedDetails { scheduleDetails }
            else {
                DetailDisclosure("Release dates, history and sources", identifier: "detail-dub-disclosure", isExpanded: $expandedSchedule) {
                    scheduleDetails
                }
            }
        }
    }
    private var scheduleDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let progress {
                if let total = anime.episodes, total > 0 { Text("\(total) episodes planned for this title").font(.caption).foregroundStyle(.secondary) }
                Text(progress.explanation).font(.caption).foregroundStyle(.secondary)
                if let date = progress.lastReleaseAt {
                    Text("Latest reported dub release: \(date.formatted(.dateTime.month(.abbreviated).day().year()))").font(.caption).foregroundStyle(.secondary)
                }
            }
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


