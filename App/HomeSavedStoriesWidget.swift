import SwiftUI
import AnimeCore

struct HomeSavedStoriesWidget: View {
    @EnvironmentObject private var navigation: AppNavigationStore
    @AppStorage("news.reader.v1") private var readerJSON = ""
    @AppStorage("news.readingHistory") private var historyJSON = ""
    @AppStorage("news.preferences.v1") private var preferencesJSON = ""
    let limit: Int
    @State private var selected: NewsArticle?
    private var reader: NewsReaderState { decode(readerJSON) ?? NewsReaderState() }
    private var articles: [NewsArticle] {
        var query = NewsFeedQuery(); query.collection = .saved
        return Array(NewsFeed.articles([], query: query, preferences: decode(preferencesJSON) ?? NewsPreferences(),
            reader: reader, history: decode(historyJSON) ?? NewsReadingHistory(), library: []).prefix(limit))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CompanionSectionHeading(title: "Saved stories")
                Button("See all") { navigation.openNews(.saved) }.font(.caption.weight(.semibold)).frame(minHeight: 44)
            }
            if articles.isEmpty {
                HomeWidgetEmpty(symbol: "bookmark", title: "Keep a story for later.", detail: "Bookmark a headline in News to see it here.")
            } else {
                VStack(spacing: 10) {
                    ForEach(articles) { article in
                        Button { open(article) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: reader.isRead(article) ? "bookmark" : "bookmark.fill").foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(article.title).font(.subheadline.weight(.semibold)).lineLimit(3)
                                    Text(article.source.label).font(.caption).foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.primary).companionPanel(padding: 12)
                        }.buttonStyle(.plain).contextMenu {
                            Button("Remove saved story", systemImage: "bookmark.slash") {
                                var value = reader; value.toggleSaved(article); readerJSON = encode(value)
                            }
                        }
                    }
                }
            }
        }.sheet(item: $selected) { ArticleBrowser(url: $0.url).ignoresSafeArea() }
    }
    private func open(_ article: NewsArticle) {
        guard article.source.accepts(article.url) else { return }
        var history: NewsReadingHistory = decode(historyJSON) ?? NewsReadingHistory()
        history.record(article); historyJSON = encode(history)
        var value = reader; value.migrate(history); value.markRead(article); readerJSON = encode(value)
        selected = article
    }
    private func decode<T: Decodable>(_ value: String) -> T? { try? JSONDecoder().decode(T.self, from: Data(value.utf8)) }
    private func encode<T: Encodable>(_ value: T) -> String { (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
}
