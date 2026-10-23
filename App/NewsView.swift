import SwiftUI
import SafariServices
import AnimeCore

struct NewsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var navigation: AppNavigationStore
    var anime: Anime? = nil
    @AppStorage("news.readingHistory") private var historyJSON = ""
    @AppStorage("news.popularPeriod") private var periodValue = NewsPeriod.week.rawValue
    @State private var articles: [NewsArticle] = []
    @State private var unavailable: [String] = []
    @State private var sourceFilter = "all"
    @State private var loading = false
    @State private var error: String?
    @State private var selected: NewsArticle?
    private var history: NewsReadingHistory { (try? JSONDecoder().decode(NewsReadingHistory.self, from: Data(historyJSON.utf8))) ?? NewsReadingHistory() }
    private var period: NewsPeriod { NewsPeriod(rawValue: periodValue) ?? .week }
    private var filtered: [NewsArticle] {
        articles.filter { article in
            (sourceFilter == "all" || article.source.rawValue == sourceFilter) &&
            (anime.map { AnimeUpdates.headline(article, matches: $0) } ?? true)
        }
    }

    var body: some View {
        List {
            if anime == nil {
                Section("Discover") {
                    NavigationLink { AnimeVisualsView() } label: { Label("Visuals", systemImage: "photo.on.rectangle") }
                        .accessibilityIdentifier("news-open-visuals")
                    Button { navigation.selectedTab = .schedule } label: { Label("Release schedules", systemImage: "calendar") }
                        .accessibilityIdentifier("news-open-schedule")
                }
            } else if let anime {
                Section {
                    Text(anime.displayTitle).font(.headline)
                    Text("Title matches in recent publisher headlines, not a complete news archive.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("News sources", selection: $sourceFilter) {
                    Text("All sources").tag("all")
                    ForEach(NewsSource.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                }.accessibilityIdentifier("news-sources")
                Text("Anime News Network · Crunchyroll · Anime Corner").font(.caption).foregroundStyle(.secondary)
            }
            if anime == nil { Section("Popular \(period.label.lowercased())") {
                Picker("Popular news period", selection: $periodValue) {
                    ForEach(NewsPeriod.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                }.pickerStyle(.segmented).accessibilityIdentifier("news-popular-period")
                Text("Most opened on this device in the last \(period.days) days.").font(.caption).foregroundStyle(.secondary)
                let popular = history.popular(in: period)
                if popular.isEmpty {
                    Text("Your most-opened stories will appear here as you read.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(Array(popular.prefix(5))) { item in
                    NewsArticleRow(article: item.article, opens: item.opens, open: open)
                }
            } }
            Section("Latest headlines") {
                if loading && articles.isEmpty { ProgressView("Loading headlines…") }
                if let error { NoticeView(message: error) { Task { await load(refresh: true) } } }
                ForEach(filtered) { article in NewsArticleRow(article: article, open: open) }
                if filtered.isEmpty && !loading && error == nil {
                    Text(anime == nil ? "No headlines from this source yet. Pull to refresh." : "No matching headlines in the current feeds. Try another news source or check again later.").foregroundStyle(.secondary)
                }
                if !unavailable.isEmpty { Text("Temporarily unavailable: " + unavailable.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
            }
        }.accessibilityIdentifier("news-list").scrollContentBackground(.hidden).readableContent().background(Theme.background)
            .navigationTitle(anime == nil ? "Anime News" : "Headlines").task { if articles.isEmpty { await load() } }.refreshable { await load(refresh: true) }
            .sheet(item: $selected) { ArticleBrowser(url: $0.url).ignoresSafeArea() }
    }
    private func open(_ article: NewsArticle) {
        var updated = history; updated.record(article)
        if let data = try? JSONEncoder().encode(updated), let text = String(data: data, encoding: .utf8) { historyJSON = text }
        selected = article
    }
    private func load(refresh: Bool = false) async {
        guard !loading else { return }; loading = true; error = nil
        defer { loading = false }
        do {
            let snapshot = try await store.news.snapshot(refresh: refresh)
            try Task.checkCancellation()
            articles = snapshot.articles; unavailable = snapshot.unavailableSources
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct NewsArticleRow: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    let article: NewsArticle
    var opens: Int? = nil
    let open: (NewsArticle) -> Void
    @State private var imageURL: URL?
    var body: some View {
        Button { open(article.withImage(imageURL)) } label: {
            HStack(alignment: .top, spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 7) {
                    Text(article.title).font(.subheadline.bold()).foregroundStyle(.primary).multilineTextAlignment(.leading).lineLimit(4)
                    Text(article.source.label).font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        if let date = article.publishedAt { Text(date, style: .relative) }
                        if let opens { Text("· \(opens) \(opens == 1 ? "open" : "opens")") }
                    }.font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.vertical, 7)
        }.buttonStyle(.plain).task(id: article.id) { imageURL = await store.news.thumbnail(for: article) }
    }
    private var thumbnail: some View {
        ArtworkPhaseView(url: imageURL ?? article.imageURL, pointSize: sizeClass == .regular ? 132 : 96) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else {
                ZStack { Theme.surface; Image(systemName: "newspaper").font(.title2).foregroundStyle(.secondary) }
            }
        }.frame(width: sizeClass == .regular ? 132 : 96, height: sizeClass == .regular ? 104 : 80)
            .clipShape(RoundedRectangle(cornerRadius: 9)).accessibilityHidden(true)
    }
}

struct ArticleBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
