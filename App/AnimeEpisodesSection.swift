import SwiftUI
import AnimeCore

struct AnimeEpisodesSection: View {
    @EnvironmentObject private var store: AppStore
    let anime: Anime
    var refreshID = 0
    @Binding var appliedRefreshID: Int
    let play: (Int) -> Void
    let edit: () -> Void
    @State private var rows: [AnimeEpisodeMetadata] = []
    @State private var page = 0
    @State private var more = false
    @State private var loading = false
    @State private var error: String?
    @State private var source: AnimeEpisodePage?
    @State private var requestID = UUID()
    @State private var displayLimit = 12
    @State private var filter = "All"
    @State private var query = ""
    @State private var newest = false
    @State private var trackingError: String?
    @State private var upcomingExpanded = false
    @State private var upcomingLimit = 6
    private var trackingBusy: Bool { store.savingMedia.contains(anime.id) || (store.isSignedIn && (store.loadingLibrary || store.savedAt == nil)) }
    private var watched: Int { store.entry(for: anime.id)?.progressValue ?? 0 }
    private var knownCount: Int { min(10_000, max(max(anime.episodes ?? 0, anime.releasedEpisodeCount() ?? 0), max(watched, anime.nextAiringEpisode?.episode ?? 0))) }
    private var available: [AnimeEpisodeMetadata] {
        var values = rows.isEmpty ? (knownCount > 0 ? (1...knownCount).map { AnimeEpisodeMetadata(number: $0) } : []) : rows
        if let next = anime.nextAiringEpisode, (1...10_000).contains(next.episode), next.date > Date(),
           !values.contains(where: { $0.number == next.episode }) {
            values.append(AnimeEpisodeMetadata(number: next.episode))
        }
        return values
    }
    private func filtered(_ episodes: [AnimeEpisodeMetadata]) -> [AnimeEpisodeMetadata] {
        let values = episodes.filter {
            (filter == "All" || (filter == "Watched" ? $0.number <= watched : $0.number > watched)) &&
            (query.isEmpty || ("\($0.number) " + ($0.title ?? "")).localizedCaseInsensitiveContains(query))
        }
        return newest ? Array(values.reversed()) : values
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            episodeContent(now: context.date)
        }.accessibilityIdentifier("anime-episodes")
            .task(id: "\(anime.id)-\(refreshID)") { await load(reset: true, refresh: refreshID != appliedRefreshID) }
            .onChange(of: filter) { _, _ in resetLimits() }
            .onChange(of: query) { _, _ in resetLimits() }
            .onChange(of: upcomingExpanded) { _, expanded in if !expanded { upcomingLimit = 6 } }
    }
    private func episodeContent(now: Date) -> some View {
        let groups = AnimeEpisodeReleaseGroups(anime: anime, episodes: available, now: now)
        let aired = filtered(groups.aired)
        return VStack(alignment: .leading, spacing: 14) {
            episodeHeader(now: now)
            if groups.hasUpcoming && filter != "Watched" { upcomingDisclosure(groups) }
            TextField("Search loaded episodes or titles", text: $query).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                .accessibilityIdentifier("anime-episode-search")
            feedback
            if aired.isEmpty && !loading { emptyEpisodes(groups) }
            LazyVStack(spacing: 12) {
                ForEach(Array(aired.prefix(displayLimit))) { episode in episodeCard(episode, released: true) }
            }
            pagination(visibleCount: aired.count)
            attribution
        }
    }
    private func episodeHeader(now: Date) -> some View {
        HStack {
            Text("Episodes").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            if let count = anime.releasedEpisodeCount(at: now) {
                Text("\(count) aired").font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Theme.accent.opacity(0.12), in: Capsule())
            }
            Spacer()
            Menu {
                Picker("Show episodes", selection: $filter) { ForEach(["All", "Unwatched", "Watched"], id: \.self) { Text($0).tag($0) } }
                Toggle("Newest first", isOn: $newest)
            } label: { Image(systemName: "line.3.horizontal.decrease.circle").font(.title2).frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Episode filters")
        }
    }
    private var feedback: some View {
        VStack(alignment: .leading, spacing: 8) {
            if loading && rows.isEmpty { ProgressView("Loading episode details…").font(.caption) }
            if let error { NoticeView(message: error) { Task { await load(reset: true, refresh: true) } } }
            if let trackingError { Text(trackingError).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("episode-tracking-error") }
            Text("Marking an episode watched also marks earlier episodes watched.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func emptyEpisodes(_ groups: AnimeEpisodeReleaseGroups) -> some View {
        Text(groups.aired.isEmpty
             ? (groups.hasUpcoming ? "No released episodes are listed yet." : "Episode details have not been announced.")
             : "No released episodes match these filters.")
            .font(.subheadline).foregroundStyle(.secondary)
    }
    private func episodeCard(_ episode: AnimeEpisodeMetadata, released: Bool) -> some View {
        AnimeEpisodeCard(episode: episode, watched: episode.number <= watched, canPlay: released,
            canTrack: released && !trackingBusy, signedIn: store.isSignedIn,
            play: { play(episode.number) }, track: { track(episode) })
    }
    private func upcomingDisclosure(_ groups: AnimeEpisodeReleaseGroups) -> some View {
        DisclosureGroup(isExpanded: $upcomingExpanded) {
            upcomingRows(groups)
        } label: {
            upcomingLabel(groups)
        }.companionPanel(padding: 12).accessibilityIdentifier("episodes-upcoming")
    }
    private func upcomingLabel(_ groups: AnimeEpisodeReleaseGroups) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let next = groups.next {
                Text("Next: Episode \(next.episode)").font(.subheadline.weight(.semibold))
                Text("Airs \(next.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let next = groups.upcoming.first {
                Text("Upcoming: Episode \(next.number)").font(.subheadline.weight(.semibold))
                Text(next.dateLabel.map { "Airs \($0)" } ?? "Air date not announced")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Upcoming episodes").font(.subheadline.weight(.semibold))
            }
            Text(groups.unairedCount.map { "\($0) unaired · Expand for details" } ?? "Expand upcoming episode details")
                .font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func upcomingRows(_ groups: AnimeEpisodeReleaseGroups) -> some View {
        let episodes = filtered(groups.upcoming)
        return LazyVStack(spacing: 12) {
            if episodes.isEmpty { Text("More episode details have not been announced.").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(episodes.prefix(upcomingLimit))) { episode in episodeCard(episode, released: false) }
            if episodes.count > upcomingLimit {
                Button("Show more upcoming episodes") { upcomingLimit += 24 }.frame(minHeight: 44)
            }
        }.padding(.top, 12)
    }
    @ViewBuilder private func pagination(visibleCount: Int) -> some View {
        if visibleCount > displayLimit {
            Button("Show more episodes") { displayLimit += 24 }.frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.bordered)
        } else if more {
            Button("Load more episode details") { Task { await load(reset: false) } }
                .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.bordered).disabled(loading)
        }
    }
    @ViewBuilder private var attribution: some View {
        if let source {
            Link("Episode metadata · " + source.source, destination: source.sourceURL).font(.caption2).foregroundStyle(.secondary)
            if let notice = source.notice { Text(notice).font(.caption2).foregroundStyle(.secondary) }
        }
    }
    private func resetLimits() { displayLimit = 12; upcomingLimit = 6 }
    private func track(_ episode: AnimeEpisodeMetadata) {
        guard AnimeEpisodeReleaseGroups.isReleased(episode, anime: anime) else { return }
        guard store.isSignedIn && episode.number > watched else { edit(); return }
        trackingError = nil
        Task {
            do { try await store.markWatched(anime: anime, through: episode.number) }
            catch { trackingError = error.localizedDescription }
        }
    }
    @MainActor private func load(reset: Bool, refresh: Bool = false) async {
        guard !loading || reset else { return }
        let attempt = UUID(); requestID = attempt; loading = true; error = nil
        let next = reset ? 1 : page + 1
        defer { if requestID == attempt { loading = false } }
        if reset, let saved = await store.episodeMetadata.cached(for: anime), requestID == attempt, !Task.isCancelled {
            rows = saved.episodes; source = saved; more = saved.hasMore; page = 1
        }
        do {
            let result = try await store.episodeMetadata.page(for: anime, page: next, refresh: refresh)
            try Task.checkCancellation(); guard requestID == attempt else { return }
            var ids = Set(reset ? [] : rows.map(\.number))
            let incoming = result.episodes.filter { ids.insert($0.number).inserted }
            rows = reset ? incoming : rows + incoming; rows.sort { $0.number < $1.number }
            source = result; page = next; more = result.hasMore
            if reset { appliedRefreshID = refreshID }
            if !reset { displayLimit += 24 }
        } catch is CancellationError {} catch { if requestID == attempt { self.error = error.localizedDescription } }
    }
}

private struct AnimeEpisodeCard: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var textSize
    let episode: AnimeEpisodeMetadata
    let watched: Bool
    let canPlay: Bool
    let canTrack: Bool
    let signedIn: Bool
    let play: () -> Void
    let track: () -> Void
    @State private var expanded = false
    private var width: CGFloat { sizeClass == .regular ? 180 : 108 }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { thumbnail; HStack { labels; actions } }
            } else {
                HStack(alignment: .center, spacing: 12) { thumbnail; labels; actions }
            }
            if let overview = episode.overview {
                Text(overview).font(.subheadline).foregroundStyle(.secondary).lineLimit(expanded ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(watched ? Theme.secondarySurface.opacity(0.6) : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay { RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border, lineWidth: 1) }
            .accessibilityIdentifier("episode-row-\(episode.number)")
            .accessibilityValue(watched ? "Watched" : (canPlay ? "Unwatched" : "Not yet aired"))
    }
    private var thumbnail: some View {
        ArtworkImage(url: episode.imageURL, pointSize: width) { $0.resizable().scaledToFill() } placeholder: {
            ZStack { Theme.accent.opacity(0.12); Image(systemName: "film").font(.title2).foregroundStyle(Theme.accent.opacity(0.5)) }
        }.frame(width: width, height: width * 9 / 16).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
            .saturation(watched ? 0 : 1).opacity(watched ? 0.55 : 1)
            .overlay(alignment: .topTrailing) {
                if watched { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, Theme.accent).padding(5).accessibilityLabel("Watched") }
            }.accessibilityHidden(true)
    }
    private var labels: some View {
        Button { expanded.toggle() } label: {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text("Episode \(episode.number)").font(.headline).foregroundStyle(watched ? Color.secondary : Color.primary)
                if episode.overview != nil { Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2).foregroundStyle(.secondary) }
            }
            if let title = episode.title { Text(title).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
            let facts = [episode.dateLabel, episode.runtime.map { "\($0) min" }].compactMap { $0 }
            if !facts.isEmpty { Text(facts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
            if let rating = episode.rating {
                Label(rating.formatted(.number.precision(.fractionLength(1))) + "/10", systemImage: "star.fill")
                    .font(.caption2).foregroundStyle(Theme.highlight)
            }
            if episode.filler || episode.recap { Text(episode.filler ? "Filler" : "Recap").font(.caption2.weight(.semibold)).foregroundStyle(Theme.highlight) }
        }.frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain).disabled(episode.overview == nil)
            .accessibilityHint(episode.overview == nil ? "Episode metadata" : "Tap to expand or shorten the synopsis")
    }
    private var actions: some View {
        VStack(spacing: 4) {
            Button(action: play) {
                Image(systemName: canPlay ? (watched ? "arrow.counterclockwise" : "play.fill") : "clock")
                    .font(.headline).frame(width: 44, height: 44).background(Theme.accent.opacity(0.12), in: Circle())
            }.buttonStyle(.plain).disabled(!canPlay).accessibilityLabel((watched ? "Replay" : "Find streams for") + " episode \(episode.number)")
                .accessibilityIdentifier("episode-play-\(episode.number)")
            Button(action: track) {
                Image(systemName: watched ? "checkmark.circle.fill" : "circle")
                    .font(.title3).frame(width: 44, height: 44)
            }.buttonStyle(.plain).disabled(!canTrack)
                .accessibilityLabel(!signedIn ? "Connect AniList to mark watched" : (watched ? "Episode \(episode.number) watched. Edit progress" : "Mark watched through episode \(episode.number)"))
                .accessibilityIdentifier("episode-watched-\(episode.number)")
        }.foregroundStyle(Theme.accent)
    }
}
