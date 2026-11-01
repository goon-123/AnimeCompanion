import SwiftUI
import AnimeCore

/// Permanent access keeps every Home feature reachable even if its preview
/// widget is hidden in Customize Home.
struct HomeFeatureShortcuts: View {
    @EnvironmentObject private var navigation: AppNavigationStore
    var body: some View {
        HStack(spacing: 10) {
            tile("Calendar", detail: "Your week", symbol: "calendar", id: "schedule") { navigation.openSchedule() }
            tile("Airing Now", detail: "Catch up", symbol: "play.rectangle", id: "airing") { navigation.openSchedule(page: .airing) }
            tile("News", detail: "Your briefing", symbol: "newspaper", id: "news") { navigation.openNews() }
        }
    }
    private func tile(_ title: String, detail: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent).accessibilityHidden(true)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .companionPanel(padding: 12).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("home-open-" + id)
    }
}

/// A small presentation of the existing feed, preferences, bookmarks and read
/// history. The full NewsView remains the place for searching and filtering.
struct HomeNewsSection: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("news.reader.v1") private var readerJSON = ""
    @AppStorage("news.readingHistory") private var historyJSON = ""
    @AppStorage("news.preferences.v1") private var preferencesJSON = ""
    var refreshID = 0
    @State private var appliedRefreshID = 0
    @State private var snapshot: NewsSnapshot?
    @State private var selected: NewsArticle?
    @State private var loading = false
    @State private var error: String?
    @State private var requestID = UUID()
    private var reader: NewsReaderState { decode(readerJSON) ?? NewsReaderState() }
    private var preferences: NewsPreferences { decode(preferencesJSON) ?? NewsPreferences() }
    private var stories: [NewsArticle] {
        Array(NewsFeed.articles(snapshot?.articles ?? [], query: NewsFeedQuery(), preferences: preferences,
            reader: reader, history: decode(historyJSON) ?? NewsReadingHistory(), library: []).prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CompanionSectionHeading(title: "Headlines")
                Menu {
                    Button("Latest headlines") { navigation.openNews() }
                    Button("For You", systemImage: "sparkles") { navigation.openNews(.forYou) }
                    Button("Saved stories", systemImage: "bookmark") { navigation.openNews(.saved) }
                    Button("Reading history", systemImage: "clock") { navigation.openNews(.history) }
                } label: {
                    Label("All news", systemImage: "chevron.down").font(.caption.weight(.semibold)).frame(minHeight: 44)
                }.accessibilityIdentifier("home-news-collections")
            }
            if !stories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(stories) { article in
                            Button { open(article) } label: {
                                HomeNewsBanner(article: article, isSaved: reader.isSaved(article))
                                    .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in min(550, width * 0.92) }
                            }.buttonStyle(.plain).accessibilityIdentifier("home-news-story-" + article.id)
                                .contextMenu {
                                    Button(reader.isSaved(article) ? "Remove saved story" : "Save story", systemImage: "bookmark") { toggleSaved(article) }
                                    Button("More headlines", systemImage: "newspaper") { navigation.openNews() }
                                }
                                .accessibilityAction(named: reader.isSaved(article) ? "Remove saved story" : "Save story") { toggleSaved(article) }
                        }
                    }
                }
                if snapshot?.isStale == true || error != nil {
                    Text("Showing saved headlines · Pull to refresh").font(.caption2).foregroundStyle(.secondary)
                }
            } else if loading {
                ProgressView("Loading headlines…").frame(maxWidth: .infinity, minHeight: 72).companionPanel(padding: 12)
            } else {
                Button { navigation.openNews() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "newspaper").font(.title2).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(error == nil ? "Your anime briefing" : "Headlines are taking a break").font(.subheadline.weight(.semibold))
                            Text(preferences.enabledSources.isEmpty ? "Choose publishers and interests in News." : "Open News for stories, saved articles and your interests.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(Theme.accent)
                    }.foregroundStyle(.primary).companionPanel(padding: 14)
                }.buttonStyle(.plain)
            }
        }.accessibilityIdentifier("home-news-widget")
            .task(id: "\(scenePhase)-\(refreshID)") {
                guard scenePhase == .active else { return }
                await load(refresh: refreshID != appliedRefreshID)
                if !Task.isCancelled { appliedRefreshID = refreshID }
            }
            .sheet(item: $selected) { ArticleBrowser(url: $0.url).ignoresSafeArea() }
    }
    @MainActor private func load(refresh: Bool = false) async {
        let attempt = UUID(); requestID = attempt; loading = true; error = nil
        defer { if requestID == attempt { loading = false } }
        if let cached = await store.news.cachedSnapshot(), requestID == attempt, !Task.isCancelled { snapshot = cached }
        do {
            let fresh = try await store.news.snapshot(refresh: refresh)
            try Task.checkCancellation()
            if requestID == attempt { snapshot = fresh }
        } catch is CancellationError {} catch { if requestID == attempt { self.error = error.localizedDescription } }
    }
    private func open(_ article: NewsArticle) {
        guard article.source.accepts(article.url) else { return }
        var history: NewsReadingHistory = decode(historyJSON) ?? NewsReadingHistory()
        history.record(article); historyJSON = encode(history)
        var state = reader; state.migrate(history); state.markRead(article); readerJSON = encode(state)
        selected = article
    }
    private func toggleSaved(_ article: NewsArticle) {
        var state = reader; state.toggleSaved(article); readerJSON = encode(state)
    }
    private func decode<T: Decodable>(_ value: String) -> T? { try? JSONDecoder().decode(T.self, from: Data(value.utf8)) }
    private func encode<T: Encodable>(_ value: T) -> String { (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
}

private struct HomeNewsBanner: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var textSize
    let article: NewsArticle
    let isSaved: Bool
    @State private var imageURL: URL?
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Theme.accent.opacity(0.20)
                ArtworkImage(url: imageURL ?? article.imageURL, pointSize: geometry.size.width) { image in
                    image.resizable().scaledToFill()
                } placeholder: { Theme.accent.opacity(0.14) }
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(article.source.label.uppercased()).fontWeight(.bold)
                        if isSaved { Image(systemName: "bookmark.fill").accessibilityLabel("Saved") }
                    }.font(.caption2).foregroundStyle(.white.opacity(0.85))
                    Text(article.title).font(.headline).lineLimit(3).foregroundStyle(.white)
                    if let date = article.publishedAt { Text(date, style: .relative).font(.caption2).foregroundStyle(.white.opacity(0.80)) }
                }.padding(14)
            }.clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        }.frame(height: textSize.isAccessibilitySize ? 250 : 160)
            .accessibilityElement(children: .combine)
            .task(id: article.id) { imageURL = await store.news.thumbnail(for: article) }
    }
}
