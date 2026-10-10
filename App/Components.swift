import SwiftUI
import AnimeCore

struct AnimeCover: View {
    let anime: Anime
    var width: CGFloat = 130
    var cornerRadius: CGFloat = 14
    var body: some View {
        AsyncImage(url: anime.coverURL) { image in image.resizable().scaledToFill() }
        placeholder: { ZStack { Theme.surface; Image(systemName: "sparkles.tv").foregroundStyle(.secondary) } }
            .frame(width: width, height: width * 1.45).clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .contentShape(Rectangle())
            .accessibilityHidden(true)
    }
}

struct AnimeCard: View {
    let anime: Anime
    var posterWidth: CGFloat = 150
    var body: some View {
        NavigationLink(value: AnimeRoute(id: anime.id)) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    AnimeCover(anime: anime, width: posterWidth)
                    DiscoveryAiringDot(anime: anime, overArtwork: true).padding(8)
                }
                Text(anime.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2, reservesSpace: true)
                HStack(spacing: 5) {
                    if let score = anime.averageScore { Label("\(score)%", systemImage: "star.fill").font(.caption) }
                    Text((anime.format ?? "Anime").replacingOccurrences(of: "_", with: " ")).font(.caption).foregroundStyle(.secondary)
                }
                DiscoveryIndicators(anime: anime)
                AnimeGenres(anime: anime).accessibilityIdentifier("explore-genres-\(anime.id)")
            }.frame(width: posterWidth).foregroundStyle(.primary).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("explore-shelf-entry-\(anime.id)")
    }
}

/// Wrap every reported genre without truncating metadata in a narrow grid cell.
struct AnimeGenres: View {
    let anime: Anime
    var body: some View {
        if let genres = anime.genres, !genres.isEmpty {
            Text(genres.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Genres: \(genres.joined(separator: ", "))")
        }
    }
}

/// A single menu choice closes immediately after updating its saved preference.
struct MenuChoice: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") }
            else { Text(title) }
        }
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "Selected" : "")
        .menuActionDismissBehavior(.enabled)
    }
}

struct AnimeShelf: View {
    let title: String
    let anime: [Anime]
    var body: some View {
        if !anime.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.title3.bold()).padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) { ForEach(anime) { AnimeCard(anime: $0) } }.padding(.horizontal)
                }
            }
        }
    }
}

struct NoticeView: View {
    let message: String
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.circle").font(.subheadline).fixedSize(horizontal: false, vertical: true)
            if let action { Button("Try again", action: action).buttonStyle(.bordered) }
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ReleaseRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let event: ReleaseEvent
    var posterWidth: CGFloat? = nil
    var body: some View {
        NavigationLink(value: AnimeRoute(id: event.anime.id)) {
            HStack(spacing: 12) {
                AnimeCover(anime: event.anime, width: posterWidth ?? (sizeClass == .regular ? 76 : 48))
                VStack(alignment: .leading, spacing: 5) {
                    Text(event.anime.displayTitle).font(sizeClass == .regular ? .headline : .subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Label("\(event.kind.rawValue.uppercased()) · Episode \(event.episode)", systemImage: event.kind == .dub ? "mic" : "tv").font(.caption)
                    if let date = event.date {
                        Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                    } else { Text(event.note ?? "Date not confirmed").font(.caption).foregroundStyle(.secondary) }
                    if event.certainty == .unverified { Text("Unverified date from source").font(.caption).foregroundStyle(.orange) }
                    if event.certainty == .delayed { Text(event.note ?? "Delayed").font(.caption).foregroundStyle(.orange) }
                }
                Spacer(minLength: 0)
            }.padding(.vertical, 5)
        }.buttonStyle(.plain).accessibilityIdentifier("release-entry-\(event.anime.id)-\(event.kind.rawValue)-\(event.episode)")
    }
}
