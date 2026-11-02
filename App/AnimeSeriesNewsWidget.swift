import SwiftUI
import AnimeCore

/// The same publisher feeds, title archive and local reading state as NewsView,
/// presented as a compact horizontal shelf without an artificial preview limit.
struct AnimeSeriesNewsWidget: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.seriesPosterWidth) private var posterWidth
    @AppStorage("news.reader.v1") private var readerJSON = ""
    @AppStorage("news.readingHistory") private var historyJSON = ""
    @AppStorage("news.preferences.v1") private var preferencesJSON = ""
    let anime: Anime
    var refreshID = 0
    @State private var appliedRefreshID = 0
    @State private var recent: NewsSnapshot?
    @State private var archive: SeriesNewsSnapshot?
    @State private var loading = false
    @State private var notice: String?
    @State private var selected: NewsArticle?
    @State private var requestID = UUID()
    private var reader: NewsReaderState { decode(readerJSON) ?? NewsReaderState() }
    private var width: CGFloat { min(340, max(180, posterWidth * 2)) }
    private func stories(reader: NewsReaderState) -> [NewsArticle] {
        let matches = NewsLibraryTitle(anime: anime)
        let values = ((recent?.articles ?? []) + (archive?.articles ?? [])).filter { matches.matches($0) }
        return NewsFeed.articles(values, query: NewsFeedQuery(),
            preferences: decode(preferencesJSON) ?? NewsPreferences(), reader: reader,
            history: NewsReadingHistory(), library: []).filter { matches.matches($0) }
    }
    var body: some View {
        let state = reader
        let values = stories(reader: state)
        return VStack(alignment: .leading, spacing: 12) {
            heading
            if !values.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(values) { article in
                            story(article, read: state.isRead(article), saved: state.isSaved(article))
                        }
                    }
                }.accessibilityIdentifier("series-news-shelf")
            } else if loading {
                ProgressView("Finding series headlines…").font(.caption).frame(maxWidth: .infinity, minHeight: 70)
            } else {
                Text("No matching stories from your enabled publishers yet.")
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 12)
            }
            if let notice {
                HStack {
                    Text(notice).font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("Retry") { Task { await load(refresh: true) } }.font(.caption).disabled(loading)
                }
            }
        }.accessibilityIdentifier("series-news-widget")
            .task(id: "\(anime.id)-\(store.includeAdult)-\(refreshID)") {
                await load(refresh: refreshID != appliedRefreshID)
            }
            .sheet(item: $selected) { ArticleBrowser(url: $0.url).ignoresSafeArea() }
            .onChange(of: store.includeAdult) { _, _ in if !store.isVisible(anime) { selected = nil } }
    }
    private var heading: some View {
        HStack {
            Text("Series news").font(.title3.bold()).accessibilityAddTraits(.isHeader)
            if loading { ProgressView().controlSize(.small) }
            Spacer()
            NavigationLink { NewsView(anime: anime).toolbar(.hidden, for: .tabBar) } label: { Text("View all").font(.caption.weight(.semibold)).frame(minHeight: 44) }
                .accessibilityIdentifier("series-news-view-all")
        }
    }
    private func story(_ article: NewsArticle, read: Bool, saved: Bool) -> some View {
        Button { open(article) } label: {
            VStack(alignment: .leading, spacing: 9) {
                ArtworkImage(url: article.imageURL, pointSize: width) { $0.resizable().scaledToFill() } placeholder: {
                    ZStack { Theme.secondarySurface; Image(systemName: "newspaper").font(.title2).foregroundStyle(Theme.accent) }
                }.frame(width: width, height: width * 0.48).clipped().clipShape(RoundedRectangle(cornerRadius: 11)).accessibilityHidden(true)
                Text(article.title).font(.subheadline.weight(.semibold)).lineLimit(3, reservesSpace: true).multilineTextAlignment(.leading)
                HStack(spacing: 5) {
                    Text(article.source.label).lineLimit(1)
                    if read { Image(systemName: "checkmark").accessibilityLabel("Read") }
                    if let date = article.publishedAt { Text("·"); Text(date, style: .relative).lineLimit(1) }
                }.font(.caption2).foregroundStyle(.secondary)
            }.frame(width: width, alignment: .leading).foregroundStyle(.primary).companionPanel(padding: 10)
        }.buttonStyle(.plain).accessibilityLabel(article.title)
            .accessibilityHint("Open story from \(article.source.label)")
            .contextMenu {
                Button(saved ? "Remove saved story" : "Save story", systemImage: saved ? "bookmark.slash" : "bookmark") {
                    var value = reader; value.toggleSaved(article); readerJSON = encode(value)
                }
                ShareLink(item: article.url) { Label("Share story", systemImage: "square.and.arrow.up") }
            }
    }
    private func open(_ article: NewsArticle) {
        guard store.isVisible(anime), article.source.accepts(article.url) else { return }
        var history: NewsReadingHistory = decode(historyJSON) ?? NewsReadingHistory()
        history.record(article); historyJSON = encode(history)
        var value = reader; value.migrate(history); value.markRead(article); readerJSON = encode(value)
        selected = article
    }
    @MainActor private func load(refresh: Bool = false) async {
        guard store.isVisible(anime) else { return }
        let attempt = UUID(); requestID = attempt
        loading = true; notice = nil
        defer { if requestID == attempt { loading = false } }
        if recent == nil {
            let cached = await store.news.cachedSnapshot()
            guard !Task.isCancelled, requestID == attempt else { return }
            recent = cached
        }
        if archive == nil {
            let cached = await store.news.cachedSeriesSnapshot(for: anime)
            guard !Task.isCancelled, requestID == attempt else { return }
            archive = cached
        }
        async let feeds = try? store.news.snapshot(refresh: refresh)
        async let series = try? store.news.seriesSnapshot(for: anime, refresh: refresh)
        let (feed, related) = await (feeds, series)
        guard !Task.isCancelled, requestID == attempt, store.isVisible(anime) else { return }
        if let feed { recent = feed }
        if let related { archive = related }
        if feed == nil || related == nil || related?.unavailable == true || related?.isStale == true ||
            feed?.isStale == true || feed?.unavailableSources.isEmpty == false {
            notice = "Some publishers couldn't be refreshed. Showing available stories."
        }
        appliedRefreshID = refreshID
    }
    private func decode<T: Decodable>(_ value: String) -> T? { try? JSONDecoder().decode(T.self, from: Data(value.utf8)) }
    private func encode<T: Encodable>(_ value: T) -> String {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
