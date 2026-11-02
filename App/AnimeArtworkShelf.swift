import SwiftUI
import AnimeCore

/// Artwork is visible in the series flow; opening a separate gallery is optional.
struct AnimeArtworkShelf: View {
    @EnvironmentObject private var store: AppStore
    let anime: Anime
    var refreshID = 0
    @State private var gallery: AnimeVisualGallery?
    @State private var loading = false
    @State private var preview: AnimeImagePreview?
    private var images: [AnimeVisual] { gallery?.images ?? AnimeVisualGallery.aniListImages(anime) }
    private var previews: [AnimeImagePreview] {
        images.map { AnimeImagePreview(url: $0.imageURL, title: $0.title, credit: $0.copyright, source: $0.source.label) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Artwork & covers").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                if loading { ProgressView() }
                NavigationLink(value: AnimeVisualsRoute(anime: anime)) { Image(systemName: "arrow.up.right.circle").font(.title2).frame(width: 44, height: 44) }
                    .accessibilityLabel("Open full artwork gallery")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(images) { image in
                        Button { preview = AnimeImagePreview(url: image.imageURL, title: image.title, credit: image.copyright, source: image.source.label) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ArtworkImage(url: image.thumbnailURL, pointSize: 320) { $0.resizable().scaledToFit() } placeholder: { Theme.accent.opacity(0.1) }
                                    .frame(width: 180, height: 244).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 14))
                                Text(image.title).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                                Text(image.source.label).font(.caption2).foregroundStyle(.secondary)
                            }.frame(width: 180, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }
            }
            if let notice = gallery?.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if images.isEmpty && !loading { Text("No artwork is listed yet.").font(.caption).foregroundStyle(.secondary) }
        }.accessibilityIdentifier("series-anime-artwork")
            .task(id: "\(anime.id)-\(refreshID)") {
                loading = true
                let value = await store.visuals.gallery(for: anime, refresh: refreshID > 0)
                if !Task.isCancelled { gallery = value }
                loading = false
            }
            .fullScreenCover(item: $preview) { AnimeImageViewer(preview: $0, gallery: previews) }
    }
}
