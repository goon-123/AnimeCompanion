import SwiftUI
import AnimeCore

struct RelatedSeriesShelf: View {
    struct Item { let anime: RelatedAnime; let caption: String? }
    let title: String?
    let items: [Item]
    @Environment(\.seriesPosterWidth) private var posterWidth
    @ScaledMetric(relativeTo: .subheadline) private var footerHeight: CGFloat = 124
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title).font(.headline) }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in RelatedAnimeCard(anime: item.anime, caption: item.caption) }
                }.frame(maxHeight: .infinity, alignment: .top)
            }.frame(height: posterWidth * 1.45 + footerHeight, alignment: .top)
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
