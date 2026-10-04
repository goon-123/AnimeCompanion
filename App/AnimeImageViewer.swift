import SwiftUI

struct AnimeImagePreview: Identifiable {
    let url: URL
    let title: String
    var id: String { url.absoluteString }
}

struct AnimeImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    let preview: AnimeImagePreview
    @State private var scale: CGFloat = 1
    @State private var startScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var startOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            GeometryReader { geometry in
                AsyncImage(url: preview.url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(scale).offset(offset)
                            .gesture(MagnificationGesture().onChanged { value in scale = min(6, max(1, startScale * value)) }
                                .onEnded { _ in startScale = scale; if scale == 1 { offset = .zero; startOffset = .zero } })
                            .simultaneousGesture(DragGesture().onChanged { value in
                                if scale > 1 { offset = CGSize(width: startOffset.width + value.translation.width, height: startOffset.height + value.translation.height) }
                            }.onEnded { _ in startOffset = offset })
                            .onTapGesture(count: 2) { withAnimation { scale = scale > 1 ? 1 : 2.5; startScale = scale; offset = .zero; startOffset = .zero } }
                            .accessibilityLabel(preview.title)
                    case .failure:
                        ContentUnavailableView("Image unavailable", systemImage: "photo", description: Text("Please close this image and try again."))
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    default:
                        ProgressView("Loading image…").frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                .onChange(of: geometry.size) { _, _ in
                    // Refit after rotation/window resizing instead of retaining an offscreen pan.
                    scale = 1; startScale = 1; offset = .zero; startOffset = .zero
                }
            }.clipped()
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44).background(.black.opacity(0.65), in: Circle()) }
                    .accessibilityLabel("Close enlarged image")
                Spacer()
                ShareLink(item: preview.url) { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44).background(.black.opacity(0.65), in: Circle()) }
                    .accessibilityLabel("Share anime image")
            }.padding()
        }.foregroundStyle(.white).accessibilityElement(children: .contain).accessibilityIdentifier("expanded-anime-image")
    }
}
