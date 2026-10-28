import SwiftUI
import AnimeCore

struct MangaBakaAnimeRoute: Hashable { let id: Int }
struct MangaBakaAnimeSearchRoute: Hashable { let title: String }

/// Resolve the written work's exact AniList identity; never guess an anime ID
/// from a MangaBaka ID or turn a title search into an automatic selection.
struct MangaBakaAnimeSection: View {
    @EnvironmentObject private var store: AppStore
    let series: MangaBakaSeries
    var refreshToken = 0
    @State private var matches: [RelatedAnime]?
    @State private var error: String?
    @State private var retry = 0
    @State private var generation = UUID()
    private var visible: [RelatedAnime] {
        (matches ?? []).filter { store.includeAdult || $0.isAdult == false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Related anime", systemImage: "play.rectangle").font(.title2.bold())
            ForEach(visible) { anime in
                NavigationLink(value: MangaBakaAnimeRoute(id: anime.id)) {
                    HStack(spacing: 14) {
                        ArtworkImage(url: anime.coverURL, pointSize: 56) { $0.resizable().scaledToFill() }
                            placeholder: { Theme.surface }
                            .frame(width: 56, height: 80).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(anime.displayTitle).font(.headline).foregroundStyle(.primary)
                            Text("Open anime").font(.caption).foregroundStyle(.mint)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14)).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("mangabaka-open-anime-\(anime.id)")
            }
            if matches == nil && error == nil { ProgressView("Finding related anime…") }
            if let error { NoticeView(message: error) { retry += 1 } }
            if matches != nil && visible.isEmpty && error == nil {
                Text("No anime is linked for this listing. You can search the anime catalog below.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            NavigationLink(value: MangaBakaAnimeSearchRoute(title: series.displayTitle)) {
                Label("Search anime", systemImage: "magnifyingglass").font(.subheadline.bold()).frame(minHeight: 44)
            }.accessibilityIdentifier("mangabaka-search-anime")
        }.accessibilityIdentifier("mangabaka-anime-adaptations")
            .task(id: "\(series.id)-\(series.anilistID ?? 0)-\(store.includeAdult)-\(refreshToken)-\(retry)") { await load() }
    }

    @MainActor private func load() async {
        let request = UUID(); generation = request; matches = nil; error = nil
        guard let id = series.anilistID, id > 0 else { matches = []; return }
        do {
            let result = try await store.aniList.animeAdaptations(mangaID: id, includeAdult: store.includeAdult,
                refresh: refreshToken > 0 || retry > 0)
            try Task.checkCancellation()
            guard generation == request else { return }
            matches = result
        } catch is CancellationError { }
        catch {
            guard generation == request, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}
