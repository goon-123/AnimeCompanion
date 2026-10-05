import SwiftUI
import AnimeCore

struct FeaturedAnimeCarousel: View {
    let anime: [Anime]
    let height: CGFloat
    @State private var selected = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 13) {
                TabView(selection: $selected) {
                    ForEach(Array(anime.enumerated()), id: \.element.id) { index, item in
                        FeaturedAnimePanel(anime: item, wide: geometry.size.width >= 700)
                            .tag(index)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never))
                    .clipShape(RoundedRectangle(cornerRadius: 25))
                    .accessibilityIdentifier("explore-featured-carousel")
                HStack(spacing: 9) {
                    ForEach(anime.indices, id: \.self) { index in
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { selected = index }
                        } label: {
                            Capsule().fill(selected == index ? Color.white : Color.white.opacity(0.28))
                                .frame(width: selected == index ? 26 : 7, height: 7).frame(minWidth: 44, minHeight: 44)
                        }.buttonStyle(.plain).accessibilityLabel("Featured title \(index + 1) of \(anime.count)")
                            .accessibilityValue(selected == index ? "Selected" : "")
                            .accessibilityIdentifier("featured-page-\(index)")
                    }
                }
            }
        }.frame(height: height + 45)
            .onChange(of: anime.map(\.id)) { _, _ in selected = min(selected, max(0, anime.count - 1)) }
    }
}

private struct FeaturedAnimePanel: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @Environment(\.dynamicTypeSize) private var textSize
    let anime: Anime
    let wide: Bool
    @State private var preview: AnimeImagePreview?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if wide {
                    AsyncImage(url: URL(string: anime.bannerImage ?? "")) { image in image.resizable().scaledToFill() }
                        placeholder: { Theme.surface }
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        .overlay(.black.opacity(0.68)).accessibilityHidden(true)
                    HStack(spacing: 30) {
                        poster(width: min(geometry.size.width * 0.48, geometry.size.height / 1.45), height: geometry.size.height)
                        information.padding(.trailing, 28)
                    }.padding(.leading, 22)
                } else {
                    poster(width: geometry.size.width, height: geometry.size.height)
                    LinearGradient(stops: [.init(color: .clear, location: 0.20), .init(color: .black.opacity(0.35), location: 0.43), .init(color: .black.opacity(0.90), location: 0.72), .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)
                    VStack { Spacer(minLength: 12); information.padding(22) }
                }
                VStack {
                    HStack {
                        Text("FEATURED").font(.caption2.weight(.bold)).tracking(2).padding(11).silverGlass(in: Capsule())
                        Spacer()
                        if let url = anime.coverURL {
                            Button { preview = AnimeImagePreview(url: url, title: anime.displayTitle) } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.subheadline.weight(.semibold))
                                    .frame(width: 44, height: 44).silverGlass(in: Circle())
                            }.buttonStyle(.plain).accessibilityLabel("Expand featured artwork")
                                .accessibilityIdentifier("featured-expand-\(anime.id)")
                        }
                    }
                    Spacer()
                }.padding(16)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.foregroundStyle(.white)
            .fullScreenCover(item: $preview) { AnimeImageViewer(preview: $0) }
    }
    private func poster(width: CGFloat, height: CGFloat) -> some View {
        AsyncImage(url: anime.coverURL) { image in image.resizable().aspectRatio(contentMode: wide ? .fit : .fill) }
            placeholder: { ZStack { Theme.surface; Image(systemName: "sparkles.tv").font(.largeTitle) } }
            .frame(width: width, height: height).clipped().contentShape(Rectangle())
            .onTapGesture {
                if let url = anime.coverURL { preview = AnimeImagePreview(url: url, title: anime.displayTitle) }
            }.accessibilityHidden(true)
    }
    private var information: some View {
        VStack(alignment: wide ? .leading : .center, spacing: 13) {
            if let entry = store.entry(for: anime.id) {
                Label(entry.status?.label ?? "In library", systemImage: entry.status == .completed ? "checkmark.circle.fill" : "bookmark.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.mint)
            }
            Text(anime.displayTitle).font(wide ? .largeTitle.bold() : .title.bold())
                .multilineTextAlignment(wide ? .leading : .center).lineLimit(textSize.isAccessibilitySize ? 4 : 3)
                .accessibilityIdentifier("featured-title-\(anime.id)")
            Text((anime.genres ?? []).joined(separator: " · ")).font(.subheadline.weight(.medium))
                .multilineTextAlignment(wide ? .leading : .center).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.white.opacity(0.85)).accessibilityIdentifier("featured-genres-\(anime.id)")
            HStack(spacing: 10) {
                if let score = anime.averageScore { Label("\(Double(score) / 10, specifier: "%.1f")", systemImage: "star.fill").foregroundStyle(.yellow) }
                Label(dubs.progress(for: anime)?.label(for: anime) ?? "Checking dub…", systemImage: "mic.fill")
                    .foregroundStyle(.mint).accessibilityIdentifier("featured-dub-\(anime.id)")
            }.font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if let next = dubs.nextDub(for: anime.id) {
                Text(next.certainty == .delayed ? "Dub delayed · Episode \(next.episode)" : "\(next.certainty == .unverified ? "Dub estimate" : "Next dub") · Episode \(next.episode)")
                    .font(.caption.weight(.semibold)).foregroundStyle(.mint)
                if let date = next.date { Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(.white.opacity(0.8)) }
            } else if let next = anime.nextAiringEpisode, next.date > Date() {
                Text("Next sub · Episode \(next.episode) · \(next.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                    .font(.caption).foregroundStyle(.white.opacity(0.8))
            }
            Text(anime.synopsis).font(.subheadline).foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(wide ? .leading : .center).lineLimit(wide ? 4 : 2)
            NavigationLink(value: AnimeRoute(id: anime.id)) {
                Label("View details", systemImage: "info.circle.fill").font(.headline)
                    .frame(minWidth: 170, minHeight: 52).padding(.horizontal, 20)
                    .foregroundStyle(.black).background(.white, in: Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("featured-details-\(anime.id)")
        }.frame(maxWidth: .infinity, alignment: wide ? .leading : .center)
    }
}
