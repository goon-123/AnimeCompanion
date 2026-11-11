import SwiftUI
import AnimeCore

struct CinematicMangaHero: View {
    let series: MangaBakaSeries
    let expand: (URL) -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var textSize
    private var bannerHeight: CGFloat { sizeClass == .regular ? 520 : 370 }
    private var posterWidth: CGFloat { sizeClass == .regular ? 190 : 138 }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    ArtworkImage(url: series.fullCoverURL ?? series.coverURL, pointSize: max(geometry.size.width, bannerHeight)) {
                        $0.resizable().scaledToFill()
                    } placeholder: { Theme.surface }
                        .frame(width: geometry.size.width, height: bannerHeight).clipped()
                        .blur(radius: 5).saturation(0.75).scaleEffect(1.06)
                    LinearGradient(stops: [.init(color: .black.opacity(0.15), location: 0),
                        .init(color: .black.opacity(0.08), location: 0.35),
                        .init(color: Theme.background.opacity(0.7), location: 0.78),
                        .init(color: Theme.background, location: 1)], startPoint: .top, endPoint: .bottom)
                }.frame(width: geometry.size.width, height: bannerHeight).clipped().accessibilityHidden(true)
            }.frame(height: bannerHeight)
            Group {
                if textSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 18) { poster; identity }
                } else {
                    HStack(alignment: .bottom, spacing: 18) { poster; identity }
                }
            }.padding(.horizontal, 20).padding(.top, -76).padding(.bottom, 20)
                .readableContent(width: 1060).frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityIdentifier("cinematic-manga-hero")
    }
    private var poster: some View {
        Button { if let url = series.fullCoverURL ?? series.coverURL { expand(url) } } label: {
            ArtworkImage(url: series.fullCoverURL ?? series.coverURL, pointSize: posterWidth * 1.45) {
                $0.resizable().scaledToFit()
            } placeholder: { Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(Theme.accent) }
                .frame(width: posterWidth, height: posterWidth * 1.45)
                .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15), lineWidth: 1) }
                .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
        }.buttonStyle(.plain).accessibilityLabel("Enlarge series cover").accessibilityIdentifier("mangabaka-series-cover")
    }
    private var identity: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text([Optional(series.formatLabel), series.year.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                .font(.caption.weight(.semibold)).foregroundStyle(.mint)
            Text(series.displayTitle).font(sizeClass == .regular ? .largeTitle.bold() : .title2.bold())
                .lineLimit(textSize.isAccessibilitySize ? nil : 5).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled).accessibilityIdentifier("mangabaka-series-title")
            if let native = series.nativeTitle, !native.isEmpty, native != series.displayTitle {
                Text(native).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 10) {
                if let rating = series.rating, rating > 0 {
                    Label(rating.formatted(.number.precision(.fractionLength(0...1))) + "%", systemImage: "star.fill")
                        .foregroundStyle(Theme.highlight)
                }
                Text(series.status.replacingOccurrences(of: "_", with: " ").capitalized).foregroundStyle(.secondary)
            }.font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
