import SwiftUI
import AnimeCore

/// Shared, continuously refreshed dub evidence for discovery, details, library and schedule.
@MainActor
final class ExploreDubStore: ObservableObject {
    @Published private(set) var snapshot: DubSnapshot?
    @Published private(set) var index: DubIndex?
    @Published private(set) var loaded = false
    @Published private(set) var loading = false
    @Published private(set) var unavailable = false
    @Published private(set) var notice: String?
    @Published private(set) var revision = 0
    private var nextReleases: [Int: ReleaseEvent] = [:]
    private var fetchTask: Task<Void, Never>?
    private var refreshFailed = false

    func load(using client: DubClient, refresh: Bool = false) async {
        if let fetchTask { await fetchTask.value; return }
        guard refresh || !loaded || snapshot == nil || snapshot.map({ Date().timeIntervalSince($0.fetchedAt) >= DubRefreshPolicy.activeInterval }) == true else { return }
        let work = Task { await fetch(using: client, refresh: refresh) }
        fetchTask = work
        await work.value
        fetchTask = nil
    }
    /// The scene task is cancelled on backgrounding and starts with a fresh request on return.
    func keepUpdated(using client: DubClient) async {
        while !Task.isCancelled {
            await load(using: client, refresh: true)
            guard !Task.isCancelled else { return }
            let interval = refreshFailed ? DubRefreshPolicy.retryInterval : DubRefreshPolicy.activeInterval
            do { try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) }
            catch { return }
        }
    }
    private func fetch(using client: DubClient, refresh: Bool) async {
        loading = true
        defer { loading = false }
        async let dates = try? client.snapshot(refresh: refresh)
        async let availability = try? client.index(refresh: refresh)
        let (newSnapshot, newIndex) = await (dates, availability)
        if let fresh = newSnapshot, let previous = snapshot {
            snapshot = DubSnapshot(
                upcoming: fresh.scheduleProvider == nil ? previous.upcoming : fresh.upcoming,
                history: fresh.historyProvider == nil ? previous.history : fresh.history, fetchedAt: fresh.fetchedAt,
                scheduleProvider: fresh.scheduleProvider ?? previous.scheduleProvider,
                historyProvider: fresh.historyProvider ?? previous.historyProvider,
                scheduleUpdatedAt: fresh.scheduleProvider == nil ? previous.scheduleUpdatedAt : fresh.scheduleUpdatedAt,
                historyUpdatedAt: fresh.historyProvider == nil ? previous.historyUpdatedAt : fresh.historyUpdatedAt)
        } else { snapshot = newSnapshot ?? snapshot }
        index = newIndex ?? index
        refreshFailed = newSnapshot == nil || newIndex == nil || newSnapshot?.historyProvider == nil || newSnapshot?.scheduleProvider == nil
        var warnings = newSnapshot?.warnings() ?? snapshot?.warnings() ?? []
        if newSnapshot == nil { warnings.insert("Dub releases could not be refreshed. Showing previously loaded information where available.", at: 0) }
        if newIndex == nil { warnings.append("Dub availability could not be refreshed.") }
        notice = warnings.isEmpty ? nil : warnings.joined(separator: "\n")
        unavailable = notice != nil
        var next: [Int: ReleaseEvent] = [:]
        for event in snapshot?.events() ?? [] {
            guard event.certainty != .recorded,
                  event.date.map({ $0 > Date() }) ?? (event.certainty == .delayed),
                  next[event.anime.id] == nil else { continue }
            next[event.anime.id] = event
        }
        nextReleases = next
        loaded = true
        revision += 1
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
    var identifierPrefix = "explore"

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 6) {
                libraryBadge
                dubBadge
            }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 5) {
                libraryBadge
                dubBadge
            }
        }.font(.caption2.weight(.medium))
    }
    @ViewBuilder private var libraryBadge: some View {
        if store.isSignedIn {
            HStack(spacing: 4) {
                Image(systemName: libraryIcon).accessibilityHidden(true)
                Text(libraryLabel).accessibilityIdentifier("\(identifierPrefix)-library-\(anime.id)")
            }.foregroundStyle(libraryColor).padding(.horizontal, 7).padding(.vertical, 4)
                .background(libraryColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
        }
    }
    private var dubBadge: some View {
        DiscoveryDubBadge(progress: dubs.progress(for: anime))
            .accessibilityIdentifier("\(identifierPrefix)-dub-\(anime.id)")
    }
    private var libraryLabel: String {
        if let entry = store.entry(for: anime.id) { return entry.status?.label ?? "In library" }
        if store.loadingLibrary { return "Syncing list…" }
        if store.libraryError != nil { return "List unavailable" }
        return "Not on list"
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
}

struct DiscoveryAiringDot: View {
    let anime: Anime
    var overArtwork = false
    var identifierPrefix = "explore"

    var body: some View {
        if anime.isCurrentlyAiring {
            Image(systemName: "circle.fill").font(.system(size: 9)).foregroundStyle(.green)
                .padding(overArtwork ? 5 : 2)
                .background {
                    if overArtwork { Circle().fill(.black.opacity(0.65)) }
                }
                .accessibilityLabel("Currently airing")
                .accessibilityIdentifier("\(identifierPrefix)-airing-\(anime.id)")
        }
    }
}

struct DiscoveryDubBadge: View {
    let progress: LibraryDubProgress?
    private var color: Color { (progress?.discoveryStatus.tone ?? .neutral).color }

    var body: some View {
        Label(progress?.discoveryStatus.label ?? "Checking dub…", systemImage: "mic.fill")
            .font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHint("English dub availability. Episode counts and schedules are in anime details.")
    }
}

struct DiscoveryDataNote: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Green dot: currently airing. Dub badges show English availability; amber means estimated or unconfirmed, yellow means announced. Open details for episode counts and dates.")
            if dubs.unavailable {
                Text(dubs.notice ?? "Some dub information is temporarily unavailable.")
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

