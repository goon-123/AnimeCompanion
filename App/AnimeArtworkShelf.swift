import SwiftUI
import AnimeCore

struct AnimeArtworkShelf: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ScaledMetric(relativeTo: .caption) private var footerHeight: CGFloat = 86
    let anime: Anime
    var refreshID = 0
    @State private var gallery: AnimeVisualGallery?
    @State private var loading = false
    @State private var preview: AnimeImagePreview?
    private var width: CGFloat { sizeClass == .regular ? 200 : 168 }
    private var images: [AnimeVisual] { gallery?.images ?? [] }
    private var previews: [AnimeImagePreview] { images.map { $0.preview } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Artwork & covers").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                if loading { ProgressView() }
                NavigationLink(value: AnimeVisualsRoute(anime: anime)) { Image(systemName: "arrow.up.right.circle").font(.title2).frame(width: 44, height: 44) }
                    .accessibilityLabel("Open full artwork gallery")
            }
            if !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(images) { image in
                            AnimeVisualCard(image: image) { preview = image.preview }.frame(width: width)
                        }
                    }
                }
                // A horizontal lazy shelf inside the vertical detail scroll must
                // have a stable height before any asynchronous bitmap arrives.
                .frame(height: width * 1.45 + footerHeight)
            }
            if let notice = gallery?.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if images.isEmpty && !loading && gallery?.notice == nil { Text("No LiveChart artwork is listed yet.").font(.caption).foregroundStyle(.secondary) }
        }.accessibilityIdentifier("series-anime-artwork")
            .task(id: "\(anime.id)-\(refreshID)") {
                loading = true
                let value = await store.visuals.gallery(for: anime, refresh: refreshID > 0)
                guard !Task.isCancelled else { return }
                gallery = value; loading = false
            }
            .fullScreenCover(item: $preview) { AnimeImageViewer(preview: $0, gallery: previews) }
    }
}

extension AnimeVisual {
    var preview: AnimeImagePreview { AnimeImagePreview(url: imageURL, title: title, credit: copyright, source: source.label) }
}

/// The poster reserves its bounds in every loading state. A failed thumbnail
/// tries the original image; a failed original exposes a retry on the card.
struct AnimeVisualCard: View {
    @ScaledMetric(relativeTo: .caption) private var footerHeight: CGFloat = 86
    let image: AnimeVisual
    let open: () -> Void
    @State private var original = false
    @State private var failed = false
    @State private var retry = 0
    var body: some View {
        Button {
            if failed { failed = false; retry += 1 }
            else { open() }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { geometry in
                    ArtworkPhaseView(url: original ? image.imageURL : image.thumbnailURL,
                                     pointSize: max(geometry.size.width, geometry.size.height), retryToken: retry) { phase in
                        ZStack {
                            Theme.secondarySurface
                            if let bitmap = phase.image { bitmap.resizable().scaledToFit() }
                            else {
                                VStack(spacing: 8) {
                                    Image(systemName: phase.error == nil ? "photo" : "arrow.clockwise.circle").font(.title)
                                    if phase.error != nil { Text("Tap to retry").font(.caption) }
                                }.foregroundStyle(.secondary)
                            }
                        }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
                            .onChange(of: phase.error != nil, initial: true) { _, hasError in
                                if hasError && !original && image.thumbnailURL != image.imageURL { original = true }
                                else { failed = hasError }
                            }
                    }
                }.aspectRatio(1 / 1.45, contentMode: .fit)
                VStack(alignment: .leading, spacing: 4) {
                    Text(image.title).font(.caption.weight(.semibold)).lineLimit(2)
                    Text(image.source.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    if let credit = image.copyright { Text(credit).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                }.padding(10).frame(maxWidth: .infinity, minHeight: footerHeight, maxHeight: footerHeight, alignment: .topLeading)
            }.background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 14)).foregroundStyle(.primary)
        }.buttonStyle(.plain)
            .accessibilityLabel(failed ? "Retry \(image.title)" : "Expand \(image.title), \(image.source.label)")
    }
}
