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
    @AppStorage(AnimeEpisodeFilter.storageKey) private var defaultFilter = AnimeEpisodeFilter.unwatched.rawValue
    @State private var filter: AnimeEpisodeFilter?
    @State private var query = ""
    @State private var newest = false
    @State private var trackingError: String?
    @State private var upcomingExpanded = false
    @State private var upcomingLimit = 6
    private var activeFilter: AnimeEpisodeFilter { filter ?? AnimeEpisodeFilter.defaultValue(saved: defaultFilter) }
    private var currentFilterBinding: Binding<AnimeEpisodeFilter> {
        Binding(get: { activeFilter }, set: { filter = $0 })
    }
    private var defaultFilterBinding: Binding<AnimeEpisodeFilter> {
        Binding(get: { AnimeEpisodeFilter.defaultValue(saved: defaultFilter) }, set: {
            defaultFilter = $0.rawValue; filter = $0
        })
    }
    private var trackingBusy: Bool { store.savingMedia.contains(anime.id) || (store.isSignedIn && (store.loadingLibrary || store.savedAt == nil)) }
    private var watched: Int { store.entry(for: anime.id)?.progressValue ?? 0 }
    private var available: [AnimeEpisodeMetadata] {
        AnimeEpisodeReleaseGroups.listedEpisodes(anime: anime, metadata: rows, watched: watched)
    }
    private func filtered(_ episodes: [AnimeEpisodeMetadata]) -> [AnimeEpisodeMetadata] {
        let values = episodes.filter {
            activeFilter.includes(episode: $0.number, watchedThrough: watched) &&
            (query.isEmpty || ("\($0.number) " + ($0.title ?? "")).localizedCaseInsensitiveContains(query))
        }
        return newest ? Array(values.reversed()) : values
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            episodeContent(now: context.date)
        }.accessibilityIdentifier("anime-episodes")
            .task(id: "\(anime.id)-\(refreshID)") { await load(reset: true, refresh: refreshID != appliedRefreshID) }
            .onChange(of: activeFilter) { _, _ in resetLimits() }
            .onChange(of: query) { _, _ in resetLimits() }
            .onChange(of: upcomingExpanded) { _, expanded in if !expanded { upcomingLimit = 6 } }
    }
    private func episodeContent(now: Date) -> some View {
        let groups = AnimeEpisodeReleaseGroups(anime: anime, episodes: available, now: now)
        let aired = filtered(groups.aired)
        return VStack(alignment: .leading, spacing: 14) {
            episodeHeader(now: now)
            if groups.hasUpcoming && activeFilter != .watched { upcomingDisclosure(groups) }
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
                Picker("Show episodes", selection: currentFilterBinding) {
                    ForEach(AnimeEpisodeFilter.allCases) { Text($0.title).tag($0) }
                }
                Picker("Default on opening", selection: defaultFilterBinding) {
                    ForEach(AnimeEpisodeFilter.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Newest first", isOn: $newest)
            } label: { Image(systemName: "line.3.horizontal.decrease.circle").font(.title2).frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Episode filters and default").accessibilityIdentifier("episode-filter-options")
        }
    }
    private var feedback: some View {
        VStack(alignment: .leading, spacing: 8) {
            if loading && rows.isEmpty { ProgressView("Loading episode details…").font(.caption) }
            if let error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text(error).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Retry") { Task { await load(reset: true, refresh: true) } }.font(.caption.weight(.semibold)).disabled(loading)
                }.padding(.vertical, 6)
            }
            if let trackingError { Text(trackingError).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("episode-tracking-error") }
            TrackingFeedback(anime: anime)
        }
    }
    private func emptyEpisodes(_ groups: AnimeEpisodeReleaseGroups) -> some View {
        Text(emptyMessage(groups))
            .font(.subheadline).foregroundStyle(.secondary)
    }
    private func emptyMessage(_ groups: AnimeEpisodeReleaseGroups) -> String {
        if groups.aired.isEmpty {
            return groups.hasUpcoming ? "No released episodes are listed yet." : "Episode details have not been announced."
        }
        if activeFilter == .unwatched && query.isEmpty {
            if let released = anime.releasedEpisodeCount(), watched >= released {
                return "You're caught up. Use the filters to view watched episodes."
            }
            if more { return "No unwatched episodes are loaded yet. Load more episode details below." }
        }
        return "No released episodes match these filters."
    }
    private func episodeCard(_ episode: AnimeEpisodeMetadata, released: Bool) -> some View {
        AnimeEpisodeCard(episode: episode, watched: episode.number <= watched, canPlay: released,
            canTrack: released && !trackingBusy, signedIn: store.isSignedIn,
            play: { play(episode.number) }, setWatched: { track(episode, asWatched: $0) })
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
        }
        if more {
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
    private func track(_ episode: AnimeEpisodeMetadata, asWatched: Bool) {
        guard AnimeEpisodeReleaseGroups.isReleased(episode, anime: anime) else { return }
        guard store.isSignedIn else { edit(); return }
        trackingError = nil
        Task {
            do {
                if asWatched { try await store.markWatched(anime: anime, through: episode.number) }
                else { try await store.markUnwatched(anime: anime, from: episode.number) }
            }
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
    let setWatched: (Bool) -> Void
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay { RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(watched ? Theme.accent.opacity(0.55) : Theme.border, lineWidth: watched ? 1.5 : 1) }
            .animation(AppMotion.content(reduceMotion), value: watched)
            .accessibilityIdentifier("episode-row-\(episode.number)")
            .accessibilityValue(watched ? "Watched" : (canPlay ? "Unwatched" : "Not yet aired"))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
            .contextMenu { episodeMenu }
            .accessibilityHint("Touch and hold for episode actions")
            .accessibilityAction(named: Text(watched ? "Mark unwatched" : "Mark watched")) {
                if canTrack { setWatched(!watched) }
            }
    }
    private var thumbnail: some View {
        ArtworkImage(url: episode.imageURL, pointSize: width) { $0.resizable().scaledToFill() } placeholder: {
            EpisodeArtworkPlaceholder(number: episode.number)
        }.frame(width: width, height: width * 9 / 16).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }
    private var labels: some View {
        Button { withAnimation(AppMotion.content(reduceMotion)) { expanded.toggle() } } label: {
        VStack(alignment: .leading, spacing: 5) {
            if watched {
                Label("Watched", systemImage: "checkmark.circle.fill").font(.caption2.bold())
                    .foregroundStyle(Theme.accent).padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Theme.accent.opacity(0.16), in: Capsule())
                    .accessibilityIdentifier("episode-watched-\(episode.number)")
            }
            HStack(spacing: 5) {
                Text("Episode \(episode.number)").font(.headline).foregroundStyle(.primary)
                if episode.overview != nil { Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2).foregroundStyle(.secondary) }
            }
            if let title = episode.title { Text(title).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
            else if episode.overview == nil { Text("Episode details not supplied").font(.caption).foregroundStyle(.secondary) }
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
        Button(action: play) {
            Image(systemName: canPlay ? (watched ? "arrow.counterclockwise" : "play.fill") : "clock")
                .font(.headline).frame(width: 44, height: 44).background(Theme.accent.opacity(0.12), in: Circle())
        }.buttonStyle(.plain).disabled(!canPlay).accessibilityLabel((watched ? "Replay" : "Find streams for") + " episode \(episode.number)")
            .accessibilityIdentifier("episode-play-\(episode.number)").foregroundStyle(Theme.accent)
    }
    @ViewBuilder private var episodeMenu: some View {
        if canPlay {
            Button(watched ? "Replay episode" : "Find streams", systemImage: watched ? "arrow.counterclockwise" : "play.fill", action: play)
            if signedIn {
                Section {
                    Button(watched ? "Mark unwatched" : "Mark watched", systemImage: watched ? "circle" : "checkmark.circle") {
                        setWatched(!watched)
                    }.disabled(!canTrack)
                        .accessibilityIdentifier(watched ? "episode-unwatch-\(episode.number)" : "episode-mark-watched-\(episode.number)")
                } header: {
                    Text(watched ? "Progress becomes \(max(0, episode.number - 1)) watched" : "Watched through episode \(episode.number)")
                }
            } else {
                Button("Connect AniList", systemImage: "person.crop.circle") { setWatched(true) }.disabled(!canTrack)
            }
        } else { Label("Not yet aired", systemImage: "clock") }
    }
}

private struct EpisodeArtworkPlaceholder: View {
    let number: Int
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.accent.opacity(0.35), Color.indigo.opacity(0.2), Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().stroke(Theme.accent.opacity(0.14), lineWidth: 14).frame(width: 78, height: 78).offset(x: 38, y: -22)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("EP").font(.system(size: 9, weight: .bold)).tracking(2)
                    Text(String(format: "%02d", number)).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                }
                Spacer(minLength: 2)
                Image(systemName: "play.rectangle.fill").font(.system(size: 20, weight: .regular)).opacity(0.45)
            }.foregroundStyle(Theme.accent).padding(10)
        }
    }
}
