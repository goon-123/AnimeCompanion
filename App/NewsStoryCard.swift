import SwiftUI
import AnimeCore

struct NewsStoryCard: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var typeSize
    let article: NewsArticle
    var featured = false
    var compact = false
    let isRead: Bool
    let isSaved: Bool
    var reason: String?
    let open: (NewsArticle) -> Void
    let openExternally: (NewsArticle) -> Void
    let save: (NewsArticle) -> Void
    let markRead: (NewsArticle) -> Void
    let source: (NewsSource) -> Void
    @State private var imageURL: URL?
    private var enriched: NewsArticle { article.withImage(imageURL) }
    private var topic: NewsTopic? { [NewsTopic.dubs, .trailers, .manga, .reviews, .events, .industry, .announcements].first { $0.matches(article) } }
    private var identifier: String { article.url.lastPathComponent }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { open(enriched) } label: {
                if compact && !typeSize.isAccessibilitySize {
                    HStack(alignment: .top, spacing: 14) {
                        artwork.frame(width: 100, height: 92).clipShape(RoundedRectangle(cornerRadius: 12))
                        storyText
                    }.padding([.horizontal, .top], 16)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        if featured { storyText.padding(16) }
                        ZStack(alignment: .topLeading) {
                            artwork.frame(height: featured ? 235 : 170).clipped()
                            if featured {
                                Label("IN FOCUS", systemImage: "sparkles").font(.caption2.bold())
                                    .padding(9).background(.black.opacity(0.7), in: Capsule()).padding(14)
                            }
                        }
                        if !featured { storyText.padding(16) }
                    }
                }
            }.buttonStyle(.plain).accessibilityIdentifier("news-story-\(identifier)")
            controls.padding(.horizontal, 12).padding(.bottom, 5)
        }.background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.06), lineWidth: 1).allowsHitTesting(false) }
            .task(id: article.id) {
                let image = await store.news.thumbnail(for: article)
                guard !Task.isCancelled else { return }; imageURL = image
            }
    }
    private var artwork: some View {
        GeometryReader { geometry in
            ArtworkPhaseView(url: imageURL ?? article.imageURL, pointSize: max(geometry.size.width, geometry.size.height)) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else {
                    ZStack {
                        LinearGradient(colors: [.cyan.opacity(0.22), .indigo.opacity(0.22), Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: topic?.symbol ?? "newspaper").font(.system(size: compact ? 30 : 52, weight: .light)).foregroundStyle(.white.opacity(0.3))
                    }.frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }.accessibilityHidden(true)
    }
    private var storyText: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let topic {
                Text(topic.label.uppercased()).font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(.cyan)
            }
            Text(article.title).font(featured ? .title2.bold() : .headline).foregroundStyle(.primary)
                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            if !compact, let summary = article.summary, !summary.isEmpty {
                Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(featured ? 3 : 2).multilineTextAlignment(.leading)
            }
            if let reason {
                Label(reason, systemImage: "sparkles").font(.caption).foregroundStyle(.cyan).lineLimit(2).multilineTextAlignment(.leading)
            }
            HStack(spacing: 5) {
                if isRead { Label("Read", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary) }
                else { Circle().fill(.cyan).frame(width: 5, height: 5); Text("Unread").foregroundStyle(.secondary) }
                if let date = article.publishedAt { Text("·"); Text(date, style: .relative) }
            }.font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var controls: some View {
        HStack(spacing: 0) {
            Button { source(article.source) } label: {
                Text(article.source.label).font(.caption.weight(.medium)).lineLimit(1).frame(minHeight: 44)
            }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("More from \(article.source.label)")
            Spacer(minLength: 5)
            Button { save(enriched) } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark").frame(width: 44, height: 44).foregroundStyle(isSaved ? Color.cyan : Color.white)
            }.buttonStyle(.plain).accessibilityLabel(isSaved ? "Remove saved story" : "Save story").accessibilityIdentifier("news-save-\(identifier)")
            Menu {
                Button(isRead ? "Mark as unread" : "Mark as read", systemImage: isRead ? "circle" : "checkmark.circle") { markRead(article) }
                ShareLink(item: article.url) { Label("Share story", systemImage: "square.and.arrow.up") }
                Button("Open in Safari", systemImage: "safari") { openExternally(enriched) }
                Button("More from \(article.source.label)", systemImage: "newspaper") { source(article.source) }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .accessibilityLabel("Story options").accessibilityIdentifier("news-options-\(identifier)")
        }
    }
}
