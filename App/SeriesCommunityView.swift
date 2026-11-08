import SwiftUI
import AnimeCore

struct SeriesCommunityView: View {
    let anime: Anime
    @State private var tab = CommunityTab.reviews
    private enum CommunityTab: String, CaseIterable { case reviews = "Series Reviews", episodes = "Episode Comments" }
    var body: some View {
        VStack(spacing: 0) {
            Picker("Community", selection: $tab) {
                ForEach(CommunityTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).padding(16).accessibilityIdentifier("series-community-tabs")
            switch tab {
            case .reviews:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        Text(anime.displayTitle).font(.title2.bold())
                        let reviews = anime.reviews?.nodes ?? []
                        if reviews.isEmpty {
                            ContentUnavailableView("No reviews yet", systemImage: "text.bubble", description: Text("Community reviews will appear here when available."))
                        }
                        ForEach(reviews) { review in SeriesReviewCard(review: review) }
                    }.padding(20).readableContent(width: 940)
                }.accessibilityIdentifier("series-community-reviews")
            case .episodes:
                SeriesDiscussionsView(anime: anime)
            }
        }.background(Theme.background).navigationTitle("Reviews & Comments").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar).toolbarBackground(.visible, for: .navigationBar)
    }
}

private struct SeriesReviewCard: View {
    let review: AnimeReview
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(TextSanitizer.plain(review.summary ?? "Series review")).font(.headline)
            if let score = review.score { Label("\(score) / 100", systemImage: "star.fill").font(.caption.bold()).foregroundStyle(Theme.highlight) }
            if let body = review.body, !body.isEmpty {
                Text(TextSanitizer.plain(body)).font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 5).textSelection(.enabled)
                Button(expanded ? "Show less" : "Read review") { expanded.toggle() }.font(.caption.weight(.semibold))
            }
            if let raw = review.siteUrl, let url = URL(string: raw), url.scheme == "https" {
                Link("View on AniList", destination: url).font(.caption)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).companionPanel()
    }
}

/// Open only after the explicit Trailer action; episode playback uses WatchAnimeView.
struct SeriesTrailerSheet: View {
    let trailer: Trailer
    let url: URL
    var body: some View { ArticleBrowser(url: url).ignoresSafeArea() }
}
