import SwiftUI
import AnimeCore

struct LibraryAnimeRow: View {
    let entry: LibraryEntry
    let anime: Anime
    let nextDub: ReleaseEvent?
    var dub: LibraryDubProgress? = nil
    var posterWidth: CGFloat = 76

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink(value: AnimeRoute(id: anime.id)) {
                HStack(alignment: .top, spacing: 11) {
                    AnimeCover(anime: anime, width: posterWidth, cornerRadius: 6)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(anime.displayTitle).font(.headline).lineLimit(3).foregroundStyle(.primary)
                        Text("Watched \(entry.progressValue)/\(anime.episodes.map(String.init) ?? "?")").font(.subheadline).foregroundStyle(.secondary)
                        LibraryDubLabel(anime: anime, progress: dub)
                        if let score = anime.averageScore { Label("AniList \(Double(score) / 10, specifier: "%.1f")", systemImage: "star.fill").font(.caption).foregroundStyle(Theme.highlight) }
                        if let next = anime.nextAiringEpisode {
                            Text("SUB · Episode \(next.episode) airs \(next.date.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(Theme.highlight)
                        }
                        if let nextDub, let date = nextDub.date {
                            Text("\(nextDub.certainty == .unverified ? "DUB ESTIMATE" : "DUB") · Episode \(nextDub.episode) · \(date.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(nextDub.certainty == .verified ? Color.mint : Color.orange)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("library-entry-\(anime.id)")
            LibraryEntryActions(entry: entry, anime: anime)
        }.padding(.vertical, 5)
    }
}

struct LibraryAnimeTile: View {
    let entry: LibraryEntry
    let anime: Anime
    let dub: LibraryDubProgress?
    var posterWidth: CGFloat = 360

    var body: some View {
        NavigationLink(value: AnimeRoute(id: anime.id)) {
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geometry in
                    AnimeCover(anime: anime, width: geometry.size.width, cornerRadius: 8)
                }.aspectRatio(1 / 1.45, contentMode: .fit)
                Text(anime.displayTitle).font(.caption.bold()).lineLimit(2, reservesSpace: true)
                Text("Watched \(entry.progressValue)/\(anime.episodes.map(String.init) ?? "?")").font(.caption2).foregroundStyle(.secondary)
                LibraryDubLabel(anime: anime, progress: dub)
                if let score = anime.averageScore { Label("\(Double(score) / 10, specifier: "%.1f")", systemImage: "star.fill").font(.caption2).foregroundStyle(Theme.highlight) }
                AnimeGenres(anime: anime).accessibilityIdentifier("library-genres-\(anime.id)")
            }.foregroundStyle(.primary).frame(maxWidth: posterWidth, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("library-entry-\(anime.id)")
            .overlay(alignment: .topTrailing) { LibraryEntryActions(entry: entry, anime: anime).padding(5) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct LibraryDubLabel: View {
    let anime: Anime
    let progress: LibraryDubProgress?
    var body: some View {
        DubStatusBadge(anime: anime, progress: progress).accessibilityIdentifier("library-dub-\(anime.id)")
    }
}

struct LibraryEntryActions: View {
    @EnvironmentObject private var store: AppStore
    let entry: LibraryEntry
    let anime: Anime
    @State private var editing = false
    @State private var error: String?
    var body: some View {
        VStack(spacing: 4) {
            Button {
                Task { do { try await store.markNextWatched(anime: anime) } catch { self.error = error.localizedDescription } }
            } label: { Image(systemName: "checkmark.badge.plus").frame(width: 44, height: 44).background(Theme.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 9)) }
                .disabled(store.loadingLibrary || store.savedAt == nil || store.savingMedia.contains(anime.id) || (anime.episodes.map { $0 > 0 && entry.progressValue >= $0 } ?? false))
                .accessibilityLabel("Mark next episode of \(anime.displayTitle) watched").accessibilityIdentifier("library-next-\(anime.id)")
        Menu {
            Button("Edit tracking, rating and notes", systemImage: "pencil") { editing = true }
            Button("Mark next episode watched", systemImage: "plus") {
                Task { do { try await store.markNextWatched(anime: anime) } catch { self.error = error.localizedDescription } }
            }
                .disabled(anime.episodes.map { $0 > 0 && entry.progressValue >= $0 } ?? false)
            Menu("Move to list") {
                ForEach(LibraryStatus.allCases) { status in Button(status.label) { update(progress: entry.progressValue, status: status) } }
            }
        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).background(Theme.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 9)) }
            .accessibilityLabel("Manage \(anime.displayTitle)")
        }
            .disabled(store.loadingLibrary || store.savingMedia.contains(anime.id))
            .sheet(isPresented: $editing) {
                TrackingEditorView(anime: anime, entry: store.entry(for: anime.id))
            }
            .alert("Couldn’t update your library", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
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
            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.connecting).tint(.white).foregroundStyle(.black)
            if let error = store.accountError { NoticeView(message: error) }
            Text("Browsing and news work without an account.").font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(maxWidth: 480).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

