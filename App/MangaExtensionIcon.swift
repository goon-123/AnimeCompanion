import SwiftUI
import AnimeCore

/// Repository artwork uses the public image cache, never a source/account session.
struct MangaExtensionIcon: View {
    let entry: MangaExtensionDescriptor
    var size: CGFloat = 44
    private var pipeline: ArtworkPipeline {
        #if DEBUG
        if MangaReaderPreview.owns(entry.id) { return MangaReaderPreview.iconPipeline }
        #endif
        return .shared
    }
    var body: some View {
        ArtworkPhaseView(url: entry.iconURL, pointSize: size, pipeline: pipeline) { phase in
            Group {
                if let image = phase.image {
                    image.resizable().scaledToFit().padding(4)
                        .accessibilityHidden(false)
                        .accessibilityLabel("\(entry.name) source icon")
                        .accessibilityIdentifier("manga-icon-loaded-\(entry.id)")
                } else {
                    Image(systemName: "book.closed.fill").font(.title3).foregroundStyle(MangaStyle.accent)
                        .accessibilityLabel("\(entry.name) source")
                }
            }.frame(width: size, height: size).background(MangaStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
