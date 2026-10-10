import SwiftUI
import AnimeCore

private struct AiringWatchlistItem: Identifiable {
    let entry: LibraryEntry
    let status: LibraryAiringProgress
    var id: Int { entry.mediaId }
}

struct AiringNowView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var dubs: ExploreDubStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @Environment(\.scenePhase) private var scenePhase
    @Binding var showSettings: Bool
    @State private var behindOnly = false
    @State private var now = Date()

    private var items: [AiringWatchlistItem] {
        store.watching.compactMap { entry in
            guard let anime = entry.media,
                  let status = LibraryAiringProgress(anime: anime, watched: entry.progressValue,
                      source: store.airingProgressSource, dub: dubs.progress(for: anime), nextDub: dubs.nextDub(for: anime.id), now: now) else { return nil }
            return AiringWatchlistItem(entry: entry, status: status)
        }.sorted { first, second in
            if first.status.behindCount != second.status.behindCount { return first.status.behindCount > second.status.behindCount }
            if first.status.nextDate != second.status.nextDate { return (first.status.nextDate ?? .distantFuture) < (second.status.nextDate ?? .distantFuture) }
            return (first.entry.media?.displayTitle ?? "").localizedStandardCompare(second.entry.media?.displayTitle ?? "") == .orderedAscending
        }
    }
    private var visible: [AiringWatchlistItem] { items.filter { !behindOnly || $0.status.state == .behind } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if store.isSignedIn {
                    summary
                    if let error = store.libraryError { NoticeView(message: error) { Task { await store.reloadLibrary() } } }
                    if store.loadingLibrary { ProgressView("Syncing AniList…").frame(maxWidth: .infinity) }
                    if store.airingProgressSource == .dub && dubs.loading { ProgressView("Checking English dub releases…").frame(maxWidth: .infinity) }
                    LazyVStack(spacing: 14) {
                        ForEach(visible) { item in
                            if let anime = item.entry.media {
                                LibraryAnimeRow(entry: item.entry, anime: anime, nextDub: dubs.nextDub(for: anime.id),
                                    dub: dubs.progress(for: anime), airing: item.status)
                            }
                        }
                    }.accessibilityIdentifier("schedule-airing-list")
                    if visible.isEmpty && !store.loadingLibrary && !(store.airingProgressSource == .dub && dubs.loading) {
                        ContentUnavailableView(behindOnly ? "You're caught up" : "No airing titles yet",
                            systemImage: behindOnly ? "checkmark.circle" : "antenna.radiowaves.left.and.right",
                            description: Text(behindOnly ? "None of your airing titles have confirmed episodes left to catch up on." :
                                (store.airingProgressSource == .dub ? "No ongoing English dub schedule is listed for your watching list. Try Original broadcast or browse the weekly schedule." : "Add a currently airing title to your watching list to see its progress and next release here.")))
                    }
                    if let notice = dubs.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    Text("Times in \(TimeZone.current.identifier). Catch-up compares your watched progress with released episodes. Unknown counts stay neutral.")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let date = store.savedAt { Text("Last synced \(date.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.secondary) }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Your watchlist, at a glance", systemImage: "books.vertical").font(.headline)
                        Text("Connect AniList to see what you're watching, catch up on released episodes, and check the next airing time.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Connect AniList") { showSettings = true }.buttonStyle(.borderedProminent)
                        Text("You can browse Weekly Schedule without an account.").font(.caption).foregroundStyle(.secondary)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                }
            }.padding(16).readableContent(width: 1000)
        }.accessibilityIdentifier("schedule-airing-scroll")
            .refreshable {
                if store.isSignedIn { await store.reloadLibrary() }
                await dubs.load(using: store.dubs, refresh: true)
                now = Date()
            }
            .task { await dubs.load(using: store.dubs) }
            .task(id: "\(scenePhase)-\(navigation.selectedTab)") {
                guard scenePhase == .active, navigation.selectedTab == .schedule else { return }
                while !Task.isCancelled {
                    now = Date()
                    await store.refreshLibraryIfNeeded(now: now)
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                }
            }
            .onChange(of: store.airingProgressSource) { _, _ in behindOnly = false }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR WATCHING LIST").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.secondary)
            Text("Airing Now").font(.largeTitle.bold()).accessibilityIdentifier("schedule-airing-title")
            Text("Catch up. See what's next. Keep watching.").font(.subheadline).foregroundStyle(.secondary)
        }
    }
    private var summary: some View {
        let behind = items.filter { $0.status.state == .behind }.count
        let caught = items.filter { $0.status.state == .caughtUp }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(items.count) airing").font(.headline)
                Spacer()
                Menu {
                    Picker("Compare watched progress with", selection: $store.airingProgressSource) {
                        ForEach(AiringProgressSource.allCases) { Text($0.label).tag($0) }
                    }
                } label: { Label(store.airingProgressSource.label, systemImage: "antenna.radiowaves.left.and.right").font(.caption) }
                    .accessibilityIdentifier("schedule-airing-source")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { behindFilter(behind); caughtUpLabel(caught) }
                VStack(alignment: .leading, spacing: 8) { behindFilter(behind); caughtUpLabel(caught) }
            }
            if behindOnly { Text("Showing behind titles. Tap the yellow count to show all.").font(.caption2).foregroundStyle(.secondary) }
        }.padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
    private func behindFilter(_ count: Int) -> some View {
        Button { behindOnly.toggle() } label: {
            Label("\(count) behind", systemImage: "clock.badge.exclamationmark").font(.subheadline.bold())
                .foregroundStyle(.yellow).padding(.horizontal, 12).frame(minHeight: 44)
                .background(Color.yellow.opacity(behindOnly ? 0.20 : 0.08), in: Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier("schedule-behind-filter")
            .accessibilityValue(behindOnly ? "Behind only" : "All airing titles")
    }
    private func caughtUpLabel(_ count: Int) -> some View {
        Label("\(count) caught up", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(.green)
    }
}
