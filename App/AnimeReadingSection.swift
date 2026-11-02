import SwiftUI
import AnimeCore

/// Resolve written media by their own AniList IDs, never by treating an anime
/// ID or a title similarity as proof of a particular manga/novel adaptation.
struct AnimeReadingSection: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var navigation: AppNavigationStore
    let anime: Anime
    let refreshID: Int
    @Binding var appliedRefreshID: Int
    @State private var series: [MangaBakaSeries] = []
    @State private var resolved = Set<Int>()
    @State private var loading = false
    @State private var notice: String?
    @State private var retry = 0
    private var written: [RelatedAnime] { AnimeSeriesContent.writtenMedia(for: anime, includeAdult: store.includeAdult) }
    private var visible: [MangaBakaSeries] { series.filter { $0.isVisible(contentFilter: store.mangaBakaContent) } }
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Read the story").font(.title2.bold())
                Text("Find the manga, manhwa or novel, choose a reading source, or continue from a source you've linked.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(visible) { item in
                VStack(alignment: .leading, spacing: 12) {
                    NavigationLink(value: MangaBakaSeriesRoute(series: item)) {
                        HStack(spacing: 12) {
                            MangaBakaCover(series: item, width: 72)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.displayTitle).font(.headline).foregroundStyle(.primary).lineLimit(3)
                                Text(item.formatLabel).font(.caption).foregroundStyle(.secondary)
                                Label("Series details & tracking", systemImage: "arrow.up.right").font(.caption).foregroundStyle(Theme.accent)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.buttonStyle(.plain)
                    if item.type == "novel" {
                        Text("Novel metadata and tracking are available in series details. Use its publisher or reading-service links to read.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        MangaBakaSourceLinkSection(series: item)
                    }
                }.companionPanel(padding: 14).accessibilityIdentifier("anime-read-series-\(item.id)")
            }
            let remaining = written.filter { !resolved.contains($0.id) }
            if !remaining.isEmpty {
                Text("Related reading").font(.headline)
                ForEach(remaining) { media in
                    NavigationLink(value: RelatedMangaBakaRoute(media: media)) {
                        HStack(spacing: 12) {
                            AnimeCover(anime: Anime(related: media), width: 68, cornerRadius: 10, badgeStyle: .none)
                            Text(media.displayTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.companionPanel(padding: 12)
                    }.buttonStyle(.plain)
                }
            }
            if series.count > visible.count {
                Label("Some linked titles are hidden by your manga content settings.", systemImage: "eye.slash").font(.caption).foregroundStyle(.secondary)
            }
            if loading { ProgressView("Finding linked manga and novels…") }
            if let notice {
                NoticeView(message: notice) { retry += 1 }
            }
            if !loading && visible.isEmpty && written.isEmpty {
                Text("No written adaptation is linked in this anime's metadata. You can still search your reading sources or MangaBaka.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                Button { navigation.openMangaSearch(for: anime) } label: {
                    Label("Search installed reading sources", systemImage: "magnifyingglass").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("anime-read-search-sources")
                NavigationLink(value: MangaBakaBrowseRoute(query: .init(text: anime.displayTitle))) {
                    Label("Search MangaBaka", systemImage: "books.vertical").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.bordered).accessibilityIdentifier("anime-read-search-catalog")
                if !account.connected {
                    Text("Connect MangaBaka to save reading progress and remember a chosen source.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.mangaBakaNavigation().accessibilityIdentifier("series-read-tab")
            .task(id: "\(anime.id)-\(store.includeAdult)-\(store.mangaBakaContent)-\(refreshID)-\(retry)") { await load() }
    }
    @MainActor private func load() async {
        loading = true; notice = nil; resolved = []
        defer { loading = false }
        let refresh = refreshID != appliedRefreshID || retry > 0
        var found: [MangaBakaSeries] = [], ids = Set<Int>(), failures = 0
        for relation in written.prefix(8) {
            do {
                let records = try await account.api.series(anilistID: relation.id, refresh: refresh)
                try Task.checkCancellation()
                for item in records where ids.insert(item.id).inserted { found.append(item) }
                if !records.isEmpty { resolved.insert(relation.id) }
                series = found
            } catch is CancellationError { return }
            catch { failures += 1 }
        }
        guard !Task.isCancelled else { return }
        series = found; appliedRefreshID = refreshID
        if failures > 0 { notice = "Some MangaBaka links couldn't load. Related reading and manual search are still available." }
    }
}
