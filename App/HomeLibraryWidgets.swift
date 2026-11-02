import SwiftUI
import AnimeCore

struct HomeLibraryWidget: View {
    @EnvironmentObject private var anime: AppStore
    @EnvironmentObject private var books: MangaBakaStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @Environment(\.homeVisuals) private var visuals
    let section: HomeSection
    let limit: Int
    @State private var pickedID: Int?
    private var entries: [LibraryEntry] { anime.isSignedIn ? HomeLibraryContent.unique(anime.visibleEntries) : [] }
    private var planned: [LibraryEntry] { HomeLibraryContent.planned(entries) }
    private var candidates: [Anime] { HomeLibraryContent.shuffleCandidates(entries) }
    private var visibleBooks: [MangaBakaLibraryEntry] {
        guard books.connected else { return [] }
        var seen = Set<Int>()
        return books.library.map { books.entries[$0.id] ?? $0 }.filter {
            guard let series = $0.series else { return false }
            return series.isVisible(contentFilter: anime.mangaBakaContent) && seen.insert($0.id).inserted
        }
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CompanionSectionHeading(title: section.title)
                    Button("Library") { navigation.openAccountLibrary(.aniList) }.font(visuals.actionTextFont).frame(minHeight: 44)
                }
                switch section {
                case .catchUp: catchUp(at: timeline.date)
                case .libraryStats: stats
                case .planned: plannedShelf
                case .randomPick: randomPick
                default: EmptyView()
                }
            }
        }
    }
    @ViewBuilder private func catchUp(at now: Date) -> some View {
        let items = HomeLibraryContent.catchUp(entries, now: now)
        if items.isEmpty {
            HomeWidgetEmpty(symbol: "checkmark.circle", title: anime.isSignedIn ? "No confirmed episodes behind." : "Connect your watching list.",
                            detail: "Uses originally aired episodes, regardless of your dub preference.")
        } else {
            VStack(spacing: 10) {
                ForEach(Array(items.prefix(limit))) { item in
                    AnimeLink(id: item.id) {
                        HomeLibraryRow(anime: item.anime, detail: "\(item.remaining) episode\(item.remaining == 1 ? "" : "s") behind · \(item.entry.progressValue)/\(item.aired) aired", highlighted: true)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private var stats: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: visuals.value(130, 180)), spacing: 10)], spacing: 10) {
            stat("Watching", count: entries.filter { $0.status == .watching || $0.status == .rewatching }.count, symbol: "play.circle")
            stat("Completed anime", count: entries.filter { $0.status == .completed }.count, symbol: "checkmark.circle")
            stat("Plan to watch", count: planned.count, symbol: "bookmark")
            stat("Reading", count: visibleBooks.filter { ["reading", "rereading"].contains($0.state) }.count, symbol: "book")
        }
    }
    private func stat(_ title: String, count: Int, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label { Text(title) } icon: { Image(systemName: symbol).font(visuals.enlarged ? .title2 : .caption) }
                .font(visuals.enlarged ? .subheadline : .caption).foregroundStyle(.secondary)
            Text(count, format: .number).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(Theme.accent)
        }.frame(maxWidth: .infinity, alignment: .leading).companionPanel(padding: 14)
            .accessibilityElement(children: .combine)
    }
    @ViewBuilder private var plannedShelf: some View {
        if planned.isEmpty {
            HomeWidgetEmpty(symbol: "bookmark", title: "Your next favorites go here.", detail: "Add titles to Plan to watch in AniList or your library.")
        } else {
            VStack(spacing: 10) {
                ForEach(Array(planned.prefix(limit))) { entry in
                    if let value = entry.media {
                        AnimeLink(id: value.id) {
                            HomeLibraryRow(anime: value, detail: value.status == "NOT_YET_RELEASED" ? "Not yet aired" : "Saved for later")
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
    @ViewBuilder private var randomPick: some View {
        if let value = candidates.first(where: { $0.id == pickedID }) ?? candidates.first {
            VStack(alignment: .leading, spacing: 10) {
                AnimeLink(id: value.id) { HomeLibraryRow(anime: value, detail: "From your plan-to-watch list") }.buttonStyle(.plain)
                Button("Another pick", systemImage: "shuffle") {
                    pickedID = candidates.filter { $0.id != value.id }.randomElement()?.id
                }.buttonStyle(.bordered).disabled(candidates.count < 2)
                    .accessibilityIdentifier("home-shuffle-pick")
            }.onAppear { if pickedID == nil { pickedID = candidates.randomElement()?.id } }
        } else {
            HomeWidgetEmpty(symbol: "shuffle", title: "Save a few possibilities.", detail: "Shuffle picks from your planned titles with confirmed aired episodes.")
        }
    }
}

struct HomeLibraryRow: View {
    @Environment(\.homeVisuals) private var visuals
    let anime: Anime
    let detail: String
    var highlighted = false
    var body: some View {
        HomeMediaCardLayout(spacing: 10) {
            AnimeCover(anime: anime, width: visuals.rowCover, cornerRadius: 8, identifierPrefix: "home-widget", badgeStyle: .none)
        } content: {
            VStack(alignment: .leading, spacing: 5) {
                Text(anime.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(detail).font(.caption).foregroundStyle(highlighted ? Theme.highlight : Color.secondary)
            }
        }.companionPanel(padding: visuals.value(10, 14))
    }
}

struct HomeWidgetEmpty: View {
    @Environment(\.homeVisuals) private var visuals
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(visuals.iconFont).foregroundStyle(Theme.accent).frame(width: visuals.value(26, 40))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).companionPanel(padding: 14)
    }
}
