import SwiftUI
import AnimeCore

struct LibraryAnimeRow: View {
    let entry: LibraryEntry
    let anime: Anime
    let nextDub: ReleaseEvent?
    var dub: LibraryDubProgress? = nil
    var posterWidth: CGFloat = 76
    var airing: LibraryAiringProgress? = nil

    var body: some View {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top, spacing: 12) {
            AnimeLink(id: anime.id) {
                HStack(alignment: .top, spacing: 11) {
                    AnimeCover(anime: anime, width: posterWidth, cornerRadius: 6)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(anime.displayTitle).font(.headline).lineLimit(3).foregroundStyle(.primary)
                            DiscoveryAiringDot(anime: anime, identifierPrefix: "library")
                        }
                        Text("Watched \(entry.progressValue)/\(anime.episodes.map(String.init) ?? "?")").font(.subheadline).foregroundStyle(.secondary)
                        LibraryNextEpisodeLabel(entry: entry, anime: anime)
                        LibraryDubLabel(anime: anime, progress: dub)
                        if let score = anime.averageScore { Label("AniList \(Double(score) / 10, specifier: "%.1f")", systemImage: "star.fill").font(.caption).foregroundStyle(Theme.highlight) }
                        if airing != nil, let nextDub, let date = nextDub.date {
                            Text("\(nextDub.certainty == .unverified ? "DUB ESTIMATE" : "DUB") · Episode \(nextDub.episode) · \(date.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(nextDub.certainty == .verified ? Color.mint : Color.orange)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("library-entry-\(anime.id)")
        }
        AnimeGenres(anime: anime).accessibilityIdentifier("library-genres-\(anime.id)")
        if let airing { LibraryAiringStatus(status: airing, animeID: anime.id) }
      }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(airing?.state.color.opacity(0.25) ?? Theme.border, lineWidth: 1) }
            .modifier(LibraryEntryActions(entry: entry, anime: anime))
    }
}

struct LibraryAnimeTile: View {
    let entry: LibraryEntry
    let anime: Anime
    let dub: LibraryDubProgress?
    var posterWidth: CGFloat = 360
    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        AnimeLink(id: anime.id) {
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geometry in
                    AnimeCover(anime: anime, width: geometry.size.width, cornerRadius: 8)
                        .overlay(alignment: .topLeading) {
                            DiscoveryAiringDot(anime: anime, overArtwork: true, identifierPrefix: "library").padding(7)
                        }
                }.aspectRatio(1 / 1.45, contentMode: .fit)
                Text(anime.displayTitle).font(.caption.bold()).lineLimit(2, reservesSpace: true)
                Text("Watched \(entry.progressValue)/\(anime.episodes.map(String.init) ?? "?")").font(.caption2).foregroundStyle(.secondary)
                LibraryNextEpisodeLabel(entry: entry, anime: anime)
                LibraryDubLabel(anime: anime, progress: dub)
                if let score = anime.averageScore { Label("\(Double(score) / 10, specifier: "%.1f")", systemImage: "star.fill").font(.caption2).foregroundStyle(Theme.highlight) }
            }.foregroundStyle(.primary).frame(maxWidth: posterWidth, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("library-entry-\(anime.id)")
        AnimeGenres(anime: anime).accessibilityIdentifier("library-genres-\(anime.id)")
      }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .modifier(LibraryEntryActions(entry: entry, anime: anime))
    }
}

struct LibraryNextEpisodeLabel: View {
    let entry: LibraryEntry
    let anime: Anime
    var body: some View {
        Text(LibraryWatchProgress(anime: anime, entry: entry).label)
            .font(.caption.weight(.semibold)).foregroundStyle(.primary)
            .accessibilityIdentifier("library-next-episode-\(anime.id)")
    }
}

struct LibraryDubLabel: View {
    let anime: Anime
    let progress: LibraryDubProgress?
    var body: some View {
        DubStatusBadge(anime: anime, progress: progress).accessibilityIdentifier("library-dub-\(anime.id)")
    }
}

/// Keep artwork unobstructed. The same actions remain available on a long press
/// and through named VoiceOver actions; opening a card never changes progress.
struct LibraryEntryActions: ViewModifier {
    @EnvironmentObject private var store: AppStore
    let entry: LibraryEntry
    let anime: Anime
    @State private var editing = false
    @State private var watching = false
    @State private var error: String?
    private var updating: Bool { store.loadingLibrary || store.savingMedia.contains(anime.id) }
    private var canMarkNext: Bool {
        !updating && store.savedAt != nil && !(anime.episodes.map { $0 > 0 && entry.progressValue >= $0 } ?? false)
    }
    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Watch episode \(PlaybackEpisodeSelection.initial(anime: anime, entry: entry, resumeEpisode: nil))", systemImage: "play.fill") { watching = true }
                .disabled(anime.status == "NOT_YET_RELEASED")
                .accessibilityLabel("Watch episode \(PlaybackEpisodeSelection.initial(anime: anime, entry: entry, resumeEpisode: nil)) of \(anime.displayTitle) in VidHub")
                .accessibilityIdentifier("library-watch-\(anime.id)")
            Button("Mark next episode watched", systemImage: "plus") { markNext() }
                .disabled(!canMarkNext)
                .accessibilityLabel("Mark next episode of \(anime.displayTitle) watched").accessibilityIdentifier("library-next-\(anime.id)")
            Button("Edit tracking, rating and notes", systemImage: "pencil") { editing = true }.disabled(updating)
                .accessibilityIdentifier("library-edit-\(anime.id)")
            Menu("Move to list") {
                ForEach(LibraryStatus.allCases) { status in Button(status.label) { update(progress: entry.progressValue, status: status) } }
            }.disabled(updating)
        }
            .accessibilityHint("Touch and hold for playback and tracking actions")
            .accessibilityAction(named: Text("Edit tracking")) { if !updating { editing = true } }
            .accessibilityAction(named: Text("Mark next episode watched")) { markNext() }
            .sheet(isPresented: $editing) {
                TrackingEditorView(anime: anime, entry: store.entry(for: anime.id))
            }
            .sheet(isPresented: $watching) { WatchAnimeView(anime: anime) }
            .alert("Couldn’t update your library", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
    }
    private func markNext() {
        guard canMarkNext else { return }
        Task { do { try await store.markNextWatched(anime: anime) } catch { self.error = error.localizedDescription } }
    }
    private func update(progress: Int, status: LibraryStatus) {
        Task { do { try await store.save(anime: anime, progress: progress, status: status) } catch { self.error = error.localizedDescription } }
    }
}

struct LibraryGuestView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var showSettings: Bool
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical").font(.system(size: 46))
            Text("Your anime, together").font(.title2.bold())
            Text("Connect AniList to see your lists and update episode progress.").multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button {
                if AppConfiguration.clientID == nil { showSettings = true } else { Task { await store.connect() } }
            } label: {
                if store.connecting { ProgressView() } else { Text("Connect AniList").frame(maxWidth: .infinity) }
            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.connecting).tint(Theme.accent).foregroundStyle(Theme.background)
            if let error = store.accountError { NoticeView(message: error) }
            Text("Browsing and news work without an account.").font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(maxWidth: 480).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

