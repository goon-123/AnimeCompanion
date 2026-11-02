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
    private var trackingBusy: Bool { store.savingMedia.contains(anime.id) || (store.isSignedIn && (store.loadingLibrary || store.savedAt == nil)) }
    private var watched: Int { store.entry(for: anime.id)?.progressValue ?? 0 }
    private var knownCount: Int { min(10_000, max(max(anime.episodes ?? 0, anime.releasedEpisodeCount() ?? 0), watched)) }
    private var available: [AnimeEpisodeMetadata] {
        rows.isEmpty ? (knownCount > 0 ? (1...knownCount).map { AnimeEpisodeMetadata(number: $0) } : []) : rows
    }
    private var filtered: [AnimeEpisodeMetadata] {
        let values = available.filter {
            (filter == "All" || (filter == "Watched" ? $0.number <= watched : $0.number > watched)) &&
            (query.isEmpty || ("\($0.number) " + ($0.title ?? "")).localizedCaseInsensitiveContains(query))
        }
        return newest ? Array(values.reversed()) : values
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Episodes").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text("\(max(anime.episodes ?? 0, max(knownCount, rows.count)))").font(.subheadline.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 12).padding(.vertical, 5).background(Theme.accent.opacity(0.12), in: Capsule())
                Spacer()
                Menu {
                    Picker("Show episodes", selection: $filter) { ForEach(["All", "Unwatched", "Watched"], id: \.self) { Text($0).tag($0) } }
                    Toggle("Newest first", isOn: $newest)
                } label: { Image(systemName: "line.3.horizontal.decrease.circle").font(.title2).frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Episode filters")
            }
            TextField("Search loaded episodes or titles", text: $query).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                .accessibilityIdentifier("anime-episode-search")
            if loading && rows.isEmpty { ProgressView("Loading episode details…").font(.caption) }
            if let error {
                NoticeView(message: error) { Task { await load(reset: true, refresh: true) } }
            }
            if let trackingError { Text(trackingError).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("episode-tracking-error") }
            Text("Watched progress follows AniList's episode total. Marking an episode also marks earlier episodes watched.")
                .font(.caption2).foregroundStyle(.secondary)
            if filtered.isEmpty && !loading {
                Text(available.isEmpty ? "Episode details have not been announced. Find streams still lets you choose an episode." : "No episodes match these filters.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            LazyVStack(spacing: 12) {
                ForEach(Array(filtered.prefix(displayLimit))) { episode in
                    AnimeEpisodeCard(episode: episode, watched: episode.number <= watched, canPlay: canPlay(episode),
                        canTrack: !trackingBusy && (episode.number <= watched || canPlay(episode)), signedIn: store.isSignedIn,
                        play: { play(episode.number) }, track: { track(episode) })
                }
            }
            if filtered.count > displayLimit {
                Button("Show more episodes") { displayLimit += 24 }.frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.bordered)
            } else if more {
                Button("Load more episode details") { Task { await load(reset: false) } }
                    .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.bordered).disabled(loading)
            }
            if let source {
                HStack {
                    Link("Episode metadata · " + source.source, destination: source.sourceURL)
                    Spacer()
                }.font(.caption2).foregroundStyle(.secondary)
                if let notice = source.notice { Text(notice).font(.caption2).foregroundStyle(.secondary) }
            }
        }.accessibilityIdentifier("anime-episodes")
            .task(id: "\(anime.id)-\(refreshID)") { await load(reset: true, refresh: refreshID != appliedRefreshID) }
            .onChange(of: filter) { _, _ in displayLimit = 12 }
            .onChange(of: query) { _, _ in displayLimit = 12 }
    }
    private func track(_ episode: AnimeEpisodeMetadata) {
        guard store.isSignedIn && episode.number > watched else { edit(); return }
        trackingError = nil
        Task {
            do { try await store.markWatched(anime: anime, through: episode.number) }
            catch { trackingError = error.localizedDescription }
        }
    }
    private func canPlay(_ episode: AnimeEpisodeMetadata) -> Bool {
        guard anime.status != "NOT_YET_RELEASED" else { return false }
        if let aired = anime.releasedEpisodeCount() { return episode.number <= aired }
        return !episode.isFuture()
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
