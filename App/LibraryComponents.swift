import SwiftUI
import AnimeCore

struct LibraryAnimeRow: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .caption) private var genreHeight: CGFloat = 44
    let entry: LibraryEntry
    let anime: Anime
    var dub: LibraryDubProgress? = nil
    var posterWidth: CGFloat = 76

    private var coverWidth: CGFloat { textSize.isAccessibilitySize ? min(posterWidth, 60) : posterWidth }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AnimeLink(id: anime.id) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(anime.displayTitle).font(.subheadline.weight(.semibold))
                            .lineLimit(textSize.isAccessibilitySize ? nil : 3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        LibraryEntryProgress(entry: entry, anime: anime)
                        if !(anime.genres ?? []).isEmpty {
                            // The independent genre buttons sit above this reserved
                            // area; the rest of the card remains one detail link.
                            Color.clear.frame(height: genreHeight)
                        }
                    }.foregroundStyle(.primary).padding(14)
                        .frame(maxWidth: .infinity, minHeight: coverWidth * 1.45, alignment: .topLeading)
                        .padding(.leading, coverWidth)
                        // Artwork measures the completed metadata layout, so it fills
                        // long titles, genre space and Dynamic Type rows edge to edge.
                        .overlay(alignment: .leading) {
                            LibraryPoster(anime: anime, dub: dub, compact: true).frame(width: coverWidth)
                        }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("library-entry-\(anime.id)")
            AnimeGenres(anime: anime).accessibilityIdentifier("library-genres-\(anime.id)")
                .padding(.leading, coverWidth + 14).padding(.trailing, 14).padding(.bottom, 14)
        }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(Theme.border, lineWidth: 1).allowsHitTesting(false) }
            .modifier(LibraryEntryActions(entry: entry, anime: anime))
    }
}

struct LibraryAnimeTile: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let entry: LibraryEntry
    let anime: Anime
    let dub: LibraryDubProgress?
    var posterWidth: CGFloat = 360
    var body: some View {
      VStack(alignment: .leading, spacing: 0) {
        AnimeLink(id: anime.id) {
            VStack(alignment: .leading, spacing: 0) {
                LibraryPoster(anime: anime, dub: dub).aspectRatio(1 / 1.45, contentMode: .fit)
                VStack(alignment: .leading, spacing: 10) {
                    Text(anime.displayTitle).font(.subheadline.weight(.semibold))
                        .lineLimit(textSize.isAccessibilitySize ? 4 : 2, reservesSpace: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LibraryEntryProgress(entry: entry, anime: anime)
                }.padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
            }.foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("library-entry-\(anime.id)")
        AnimeGenres(anime: anime).accessibilityIdentifier("library-genres-\(anime.id)")
            .padding(.horizontal, 10).padding(.bottom, 6)
      }.frame(maxWidth: posterWidth, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1).allowsHitTesting(false) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .modifier(LibraryEntryActions(entry: entry, anime: anime))
    }
}

/// The same badge positions work on narrow row covers and large grid posters:
/// airing at the top, DUB above the rating at the bottom, with no overlap.
private struct LibraryPoster: View {
    let anime: Anime
    let dub: LibraryDubProgress?
    var compact = false
    var body: some View {
        GeometryReader { geometry in
            ArtworkImage(url: anime.coverURL, pointSize: max(geometry.size.width, geometry.size.height)) {
                image in image.resizable().scaledToFill()
            } placeholder: { Theme.surface }
                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                .overlay(alignment: .topLeading) {
                    DiscoveryAiringDot(anime: anime, overArtwork: true, identifierPrefix: "library").padding(compact ? 6 : 8)
                }
                .overlay(alignment: .bottomTrailing) {
                    VStack(alignment: .trailing, spacing: 6) {
                        if dub?.hasAvailableDub == true {
                            Text("DUB").font(.system(size: 10, weight: .heavy)).tracking(0.8)
                                .foregroundStyle(Color.mint).padding(.horizontal, 7).padding(.vertical, 5)
                                .background(.black.opacity(0.80), in: RoundedRectangle(cornerRadius: 6))
                                .accessibilityLabel("English dub available")
                                .accessibilityIdentifier("library-dub-\(anime.id)")
                        }
                        LibraryRatingLabel(anime: anime, overArtwork: true, compact: compact)
                    }.padding(compact ? 6 : 8)
                }
        }
    }
}

/// Text stays authoritative for ongoing series whose total episode count is unknown.
/// The decorative track is shown only for a known, positive total.
private struct LibraryEntryProgress: View {
    let entry: LibraryEntry
    let anime: Anime
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Watched \(entry.progressValue)/\(anime.episodes.map(String.init) ?? "?")")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let total = anime.episodes, total > 0 {
                GeometryReader { geometry in
                    Capsule().fill(Theme.accent.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Theme.accent)
                                .frame(width: geometry.size.width * min(1, max(0, Double(entry.progressValue) / Double(total))))
                        }
                }.frame(height: 3).accessibilityHidden(true)
            }
            LibraryNextEpisodeLabel(entry: entry, anime: anime)
        }
    }
}

private struct LibraryRatingLabel: View {
    let anime: Anime
    var overArtwork = false
    var compact = false
    var body: some View {
        if let score = anime.averageScore {
            HStack(spacing: 4) {
                Image(systemName: "star.fill").foregroundStyle(overArtwork ? Color.yellow : Theme.highlight)
                Text("\(Double(score) / 10, specifier: "%.1f")")
                    .foregroundStyle(overArtwork ? Color.white : Theme.highlight)
            }.font(overArtwork ? .system(size: compact ? 10 : 12, weight: .semibold) : .caption.weight(.semibold)).monospacedDigit().fixedSize()
                .padding(.horizontal, overArtwork ? (compact ? 5 : 7) : 0).padding(.vertical, overArtwork ? 5 : 0)
                .background {
                    if overArtwork { RoundedRectangle(cornerRadius: 7).fill(.black.opacity(0.78)) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("AniList rating \(Double(score) / 10, specifier: "%.1f") out of 10"))
                .accessibilityIdentifier("library-rating-\(anime.id)")
        }
    }
}

struct LibraryNextEpisodeLabel: View {
    let entry: LibraryEntry
    let anime: Anime
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let broadcast = LibraryBroadcastSummary(anime: anime, watched: entry.progressValue, now: context.date)
            let countdown = broadcast.countdown(at: context.date) ?? (anime.isCurrentlyAiring ? "Next airing TBA" : nil)
            Text(LibraryWatchProgress(anime: anime, entry: entry).label + (countdown.map { " · \($0)" } ?? ""))
                .font(.caption.weight(.semibold)).foregroundStyle(broadcast.state.color)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityValue(broadcast.state == .caughtUp ? "Caught up with original broadcast" : broadcast.state == .behind ? "Behind original broadcast" : "Broadcast count unavailable")
                .accessibilityIdentifier("library-next-episode-\(anime.id)")
        }
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

