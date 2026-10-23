import SwiftUI

struct AnimeImagePreview: Identifiable {
    let url: URL
    let title: String
    var credit: String? = nil
    var source: String? = nil
    var id: String { url.absoluteString }
}

struct AnimeImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    let preview: AnimeImagePreview
    let gallery: [AnimeImagePreview]
    @State private var selection: String
    init(preview: AnimeImagePreview, gallery: [AnimeImagePreview] = []) {
        self.preview = preview
        var seen = Set<String>()
        self.gallery = (gallery.isEmpty ? [preview] : gallery).filter { seen.insert($0.id).inserted }
        _selection = State(initialValue: preview.id)
    }
    private var index: Int { gallery.firstIndex(where: { $0.id == selection }) ?? 0 }
    private var current: AnimeImagePreview { gallery.indices.contains(index) ? gallery[index] : preview }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $selection) {
                ForEach(Array(gallery.enumerated()), id: \.element.id) { offset, item in
                    Group {
                        if abs(offset - index) <= 1 { ZoomableAnimeArtwork(preview: item, active: offset == index) }
                        else { Color.black }
                    }.tag(item.id)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44).background(.black.opacity(0.65), in: Circle()) }
                        .accessibilityLabel("Close enlarged image")
                    Spacer()
                    Text("\(index + 1) of \(gallery.count)").font(.subheadline.monospacedDigit())
                        .accessibilityIdentifier("expanded-image-position")
                    Spacer()
                    ShareLink(item: current.url) { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44).background(.black.opacity(0.65), in: Circle()) }
                        .accessibilityLabel("Share anime image")
                }.padding().background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))
                Spacer()
                VStack(spacing: 6) {
                    Text(current.title).font(.headline).multilineTextAlignment(.center).accessibilityIdentifier("expanded-image-caption")
                    if let source = current.source { Text(source).font(.caption).foregroundStyle(.secondary) }
                    if let credit = current.credit { Text(credit).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                    if gallery.count > 1 {
                        HStack(spacing: 48) {
                            Button { selection = gallery[index - 1].id } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                                .disabled(index == 0).accessibilityLabel("Previous artwork").accessibilityIdentifier("expanded-image-previous")
                            Button { selection = gallery[index + 1].id } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                                .disabled(index >= gallery.count - 1).accessibilityLabel("Next artwork").accessibilityIdentifier("expanded-image-next")
                        }.buttonStyle(.bordered)
                    }
                }.padding().frame(maxWidth: .infinity)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.92)], startPoint: .top, endPoint: .bottom))
            }
        }.foregroundStyle(.white).accessibilityElement(children: .contain).accessibilityIdentifier("expanded-anime-image")
    }
}

private struct ZoomableAnimeArtwork: View {
    let preview: AnimeImagePreview
    let active: Bool
    @State private var scale: CGFloat = 1
    @State private var startScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var startOffset: CGSize = .zero
    @State private var retryToken = 0

    var body: some View {
            GeometryReader { geometry in
                ArtworkPhaseView(url: preview.url, pointSize: active ? 3200 : 900, retryToken: retryToken) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(scale).offset(offset)
                            .gesture(MagnificationGesture().onChanged { value in scale = min(6, max(1, startScale * value)) }
                                .onEnded { _ in startScale = scale; if scale == 1 { offset = .zero; startOffset = .zero } })
                            .highPriorityGesture(DragGesture().onChanged { value in
                                if scale > 1 { offset = CGSize(width: startOffset.width + value.translation.width, height: startOffset.height + value.translation.height) }
                            }.onEnded { _ in startOffset = offset }, including: scale > 1 ? .all : .subviews)
                            .onTapGesture(count: 2) { withAnimation { scale = scale > 1 ? 1 : 2.5; startScale = scale; offset = .zero; startOffset = .zero } }
                            .accessibilityLabel(preview.title)
                            .accessibilityValue(scale > 1 ? "Zoomed in" : "Fit to screen")
                    case .failure:
                        VStack(spacing: 16) {
                            ContentUnavailableView("Image unavailable", systemImage: "photo", description: Text("Please try loading this image again."))
                            Button("Retry") { retryToken += 1 }.buttonStyle(.bordered)
                                .accessibilityIdentifier("artwork-retry")
                        }.frame(width: geometry.size.width, height: geometry.size.height)
                    default:
                        ProgressView("Loading image…").frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
                .onChange(of: geometry.size) { _, _ in
                    // Refit after rotation/window resizing instead of retaining an offscreen pan.
                    scale = 1; startScale = 1; offset = .zero; startOffset = .zero
                }
            }.clipped().onChange(of: active) { _, _ in
                scale = 1; startScale = 1; offset = .zero; startOffset = .zero
            }
    }
}
