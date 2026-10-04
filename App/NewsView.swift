import SwiftUI
import SafariServices
import AnimeCore

struct NewsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var articles: [NewsArticle] = []
    @State private var loading = false
    @State private var error: String?
    @State private var selected: NewsArticle?
    var body: some View {
        List {
            Section { Text("Anime News Network").font(.subheadline).foregroundStyle(.secondary) }
            if loading && articles.isEmpty { ProgressView("Loading headlines…") }
            if let error { NoticeView(message: error) { Task { await load(refresh: true) } } }
            ForEach(Array(articles.enumerated()), id: \.element.id) { index, article in
                Button { selected = article } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        if let imageURL = article.imageURL {
                            AsyncImage(url: imageURL) { image in image.resizable().scaledToFill() }
                            placeholder: { Theme.surface }
                                .frame(height: index == 0 ? 180 : 120).clipped().clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                        }
                        if index == 0 { Label("Latest story", systemImage: "newspaper").font(.caption).foregroundStyle(Theme.accent) }
                        Text(article.title).font(index == 0 ? .title3.bold() : .headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        HStack {
                            Text("Anime News Network")
                            if let date = article.publishedAt { Text("·"); Text(date, style: .relative) }
                        }.font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }.buttonStyle(.plain)
            }
            if articles.isEmpty && !loading && error == nil { ContentUnavailableView("No news yet", systemImage: "newspaper", description: Text("Pull to refresh for the latest headlines.")) }
        }.navigationTitle("Anime News").task { if articles.isEmpty { await load() } }.refreshable { await load(refresh: true) }
            .sheet(item: $selected) { ArticleBrowser(url: $0.url).ignoresSafeArea() }
    }
    private func load(refresh: Bool = false) async {
        guard !loading else { return }; loading = true; error = nil
        defer { loading = false }
        do { articles = try await store.news.articles(refresh: refresh) }
        catch { self.error = error.localizedDescription }
    }
}

struct ArticleBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
