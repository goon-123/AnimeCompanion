import SwiftUI
import AnimeCore

/// One shared fetch for all visible Explore cards and category pages.
@MainActor
final class ExploreDubStore: ObservableObject {
    @Published private(set) var snapshot: DubSnapshot?
    @Published private(set) var index: DubIndex?
    @Published private(set) var loaded = false
    @Published private(set) var loading = false
    @Published private(set) var unavailable = false
    private var nextReleases: [Int: ReleaseEvent] = [:]
    private var fetchTask: Task<Void, Never>?

    func load(using client: DubClient, refresh: Bool = false) async {
        if let fetchTask { await fetchTask.value; return }
        guard refresh || !loaded || snapshot.map({ Date().timeIntervalSince($0.fetchedAt) >= 600 }) == true else { return }
        let work = Task { await fetch(using: client, refresh: refresh) }
        fetchTask = work
        await work.value
        fetchTask = nil
    }
    private func fetch(using client: DubClient, refresh: Bool) async {
        loading = true
        defer { loading = false }
        async let dates = try? client.snapshot(refresh: refresh)
        async let availability = try? client.index(refresh: refresh)
        let (newSnapshot, newIndex) = await (dates, availability)
        snapshot = newSnapshot ?? snapshot; index = newIndex ?? index
        unavailable = newSnapshot == nil || newIndex == nil || !(newSnapshot?.warnings().isEmpty ?? true)
        var next: [Int: ReleaseEvent] = [:]
        for event in snapshot?.events() ?? [] {
            guard event.certainty != .recorded,
                  event.date.map({ $0 > Date() }) ?? (event.certainty == .delayed),
                  next[event.anime.id] == nil else { continue }
            next[event.anime.id] = event
        }
        nextReleases = next
        loaded = true
    }
    func progress(for anime: Anime) -> LibraryDubProgress? {
        loaded ? LibraryDubProgress(anime: anime, snapshot: snapshot, index: index) : nil
    }
    func nextDub(for id: Int) -> ReleaseEvent? {
        guard let event = nextReleases[id],
              event.date.map({ $0 > Date() }) ?? (event.certainty == .delayed) else { return nil }
        return event
    }
}

struct DiscoveryIndicators: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    let anime: Anime

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.isSignedIn {
                HStack(spacing: 4) {
                    Image(systemName: libraryIcon).accessibilityHidden(true)
                    Text(libraryLabel).accessibilityIdentifier("explore-library-\(anime.id)")
                }.foregroundStyle(libraryColor).padding(.horizontal, 6).padding(.vertical, 4)
                    .background(libraryColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                if let entry = store.entry(for: anime.id), entry.status != .completed,
                   entry.status == .rewatching || (entry.repeatCount ?? 0) > 0 {
                    Label("Watched before", systemImage: "checkmark.circle.fill").foregroundStyle(.mint)
                }
            }
            DubStatusBadge(anime: anime, progress: dubs.progress(for: anime))
                .accessibilityIdentifier("explore-dub-\(anime.id)")
            if let next = anime.nextAiringEpisode, next.date > Date() {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next sub · Ep \(next.episode)").foregroundStyle(Theme.highlight).accessibilityIdentifier("explore-next-sub-\(anime.id)")
                    Text(next.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                        .foregroundStyle(.secondary).accessibilityIdentifier("explore-next-sub-time-\(anime.id)")
                }
            } else {
                Text(airingLabel).foregroundStyle(.secondary).accessibilityIdentifier("explore-next-sub-\(anime.id)")
            }
            if let next = dubs.nextDub(for: anime.id) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dubAiringLabel(next)).foregroundStyle(next.certainty == .verified ? Color.mint : Color.orange)
                    if let date = next.date {
                        Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()).foregroundStyle(.secondary)
                    } else { Text("Date unconfirmed").foregroundStyle(.secondary) }
                }.accessibilityIdentifier("explore-next-dub-\(anime.id)")
            }
        }.font(.caption2.weight(.medium)).fixedSize(horizontal: false, vertical: true)
    }
    private var libraryLabel: String {
        if let entry = store.entry(for: anime.id) { return entry.status?.label ?? "In library" }
        if store.loadingLibrary { return "Syncing library…" }
        if store.libraryError != nil { return "List status unavailable" }
        return "Not in library"
    }
    private var libraryIcon: String {
        switch store.entry(for: anime.id)?.status {
        case .completed: return "checkmark.circle.fill"
        case .watching, .rewatching: return "play.circle.fill"
        default: return store.entry(for: anime.id) == nil ? "books.vertical" : "bookmark.fill"
        }
    }
    private var libraryColor: Color {
        switch store.entry(for: anime.id)?.status {
        case .completed: return .mint
        case .watching, .rewatching: return Theme.highlight
        default: return .secondary
        }
    }
    private var airingLabel: String {
        switch anime.status {
        case "FINISHED": return "Finished airing"
        case "CANCELLED": return "Broadcast cancelled"
        case "HIATUS": return "Broadcast on hiatus"
        case "NOT_YET_RELEASED":
            if let start = anime.startDate, start.year != nil { return "Premiere · \(start.label)" }
            return "Next sub · not scheduled"
        default: return "Next sub · not scheduled"
        }
    }
    private func dubAiringLabel(_ event: ReleaseEvent) -> String {
        switch event.certainty {
        case .delayed: return "Dub delayed · Ep \(event.episode)"
        case .unverified: return "Dub estimate · Ep \(event.episode)"
        default: return "Next dub · Ep \(event.episode)"
        }
    }
}

struct DiscoveryDataNote: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Green: reported dub releases or availability. Amber: estimates. Yellow: announced dubs. Dub counts compare English releases with original episodes already aired. Times use your device timezone.")
            if dubs.unavailable {
                Text("Some dub information is temporarily unavailable.")
                Button("Retry dub information") { Task { await dubs.load(using: store.dubs, refresh: true) } }.disabled(dubs.loading)
            }
            Text("Metadata · AniList   Dubs · AniSchedule / MyDubList")
        }.font(.caption2).foregroundStyle(.secondary)
    }
}

extension DubStatusTone {
    var color: Color {
        switch self {
        case .available: return .mint
        case .estimated: return .orange
        case .announced: return .yellow
        case .neutral: return .secondary
        }
    }
}

struct DubStatusBadge: View {
    let anime: Anime
    let progress: LibraryDubProgress?
    private var color: Color { (progress?.tone ?? .neutral).color }
    var body: some View {
        Label(progress?.label(for: anime) ?? "Checking dub…", systemImage: "mic.fill")
            .font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
            .fixedSize(horizontal: false, vertical: true)
    }
}

