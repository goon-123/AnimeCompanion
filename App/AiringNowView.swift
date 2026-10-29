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
    @Environment(\.dynamicTypeSize) private var textSize
    @Binding var showSettings: Bool
    @State private var behindOnly = false
    @State private var now = Date()
    @AppStorage("schedule.airing.layout") private var layout = "list"

    private var items: [AiringWatchlistItem] {
        store.watching.compactMap { entry -> AiringWatchlistItem? in
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
            VStack(alignment: .leading, spacing: 16) {
                header
                if store.isSignedIn {
                    summary
                    if let error = store.libraryError { NoticeView(message: error) { Task { await store.reloadLibrary() } } }
                    if store.loadingLibrary { ProgressView("Syncing AniList…").frame(maxWidth: .infinity) }
                    if store.airingProgressSource == .dub && dubs.loading { ProgressView("Checking English dub releases…").frame(maxWidth: .infinity) }
                    LazyVStack(spacing: 20) {
                        ForEach(AiringWatchlistGroup.allCases) { group in
                            let grouped = visible.filter { AiringWatchlistGroup(state: $0.status.state) == group }
                            if !grouped.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(group.title).font(.headline)
                                        Spacer()
                                        Text("\(grouped.count)").font(.caption).foregroundStyle(.secondary)
                                    }.padding(.top, 6).accessibilityIdentifier("schedule-group-\(group.rawValue)")
                                    if layout == "grid" {
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 230 : 160), spacing: 14, alignment: .topLeading)], alignment: .leading, spacing: 18) {
                                            ForEach(grouped) { item in
                                                if let anime = item.entry.media {
                                                    AiringWatchlistGridCard(entry: item.entry, anime: anime, status: item.status)
                                                }
                                            }
                                        }
                                    } else {
                                        ForEach(grouped) { item in
                                            if let anime = item.entry.media {
                                                AiringWatchlistCard(entry: item.entry, anime: anime, status: item.status)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }.accessibilityIdentifier(layout == "grid" ? "schedule-airing-grid" : "schedule-airing-list")
                    if visible.isEmpty && !store.loadingLibrary && !(store.airingProgressSource == .dub && dubs.loading) {
                        ContentUnavailableView(behindOnly ? "No confirmed episodes behind" : "No airing titles yet",
                            systemImage: behindOnly ? "checkmark.circle" : "antenna.radiowaves.left.and.right",
                            description: Text(behindOnly ? "None of your airing titles have confirmed episodes left to catch up on." :
                                (store.airingProgressSource == .dub ? "No ongoing English dub schedule is listed for your watching list. Try Original broadcast or browse the weekly schedule." : "Add a currently airing title to your watching list to see its progress and next release here.")))
                    }
                    if let notice = dubs.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    Text("Times in \(TimeZone.current.identifier). Progress uses released episodes; unconfirmed counts stay neutral.")
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Airing Now").font(.title2.bold()).accessibilityIdentifier("schedule-airing-title")
            Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.subheadline).foregroundStyle(.secondary)
        }
    }
    private var summary: some View {
        let behind = items.filter { $0.status.state == .behind }.count
        let caught = items.filter { $0.status.state == .caughtUp }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    Picker("Compare watched progress with", selection: $store.airingProgressSource) {
                        ForEach(AiringProgressSource.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Label(store.airingProgressSource == .broadcast ? "Japanese · Sub" : "English · Dub", systemImage: "chevron.down")
                        .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                }
                    .accessibilityIdentifier("schedule-airing-source")
                Spacer()
                Text("\(items.count) airing").font(.caption).foregroundStyle(.secondary)
                Menu {
                    Picker("Airing Now layout", selection: $layout) {
                        Label("List", systemImage: "list.bullet").tag("list")
                        Label("Grid", systemImage: "square.grid.2x2").tag("grid")
                    }
                } label: {
                    Image(systemName: layout == "grid" ? "square.grid.2x2" : "list.bullet")
                        .frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Airing Now layout").accessibilityValue(layout == "grid" ? "Grid" : "List")
                    .accessibilityIdentifier("schedule-airing-layout")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { behindFilter(behind); caughtUpLabel(caught) }
                VStack(alignment: .leading, spacing: 8) { behindFilter(behind); caughtUpLabel(caught) }
            }
            if behindOnly { Text("Showing behind titles. Tap the yellow count to show all.").font(.caption2).foregroundStyle(.secondary) }
        }
    }
    private func behindFilter(_ count: Int) -> some View {
        Button { behindOnly.toggle() } label: {
            Label("\(count) behind", systemImage: "clock.badge.exclamationmark").font(.subheadline.bold())
                .foregroundStyle(Theme.highlight).padding(.horizontal, 12).frame(minHeight: 44)
                .background(Theme.highlight.opacity(behindOnly ? 0.18 : 0.08), in: Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier("schedule-behind-filter")
            .accessibilityValue(behindOnly ? "Behind only" : "All airing titles")
    }
    private func caughtUpLabel(_ count: Int) -> some View {
        Label("\(count) caught up", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(.green)
    }
}

private struct AiringWatchlistGridCard: View {
    let entry: LibraryEntry
    let anime: Anime
    let status: LibraryAiringProgress
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AnimeLink(id: anime.id) {
                VStack(alignment: .leading, spacing: 9) {
                    AnimePoster(anime: anime, identifierPrefix: "library", cornerRadius: 12)
                        .aspectRatio(1 / 1.45, contentMode: .fit)
                    Text(anime.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(3, reservesSpace: true)
                }.foregroundStyle(.primary).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("library-entry-\(anime.id)")
            AiringReleaseProgress(status: status, animeID: anime.id)
        }.frame(maxWidth: .infinity, alignment: .topLeading)
            .modifier(LibraryEntryActions(entry: entry, anime: anime))
    }
}

/// A compact agenda row. Playback and tracking live in its context menu, leaving
/// one catch-up indicator and one next-release line visible per title.
private struct AiringWatchlistCard: View {
    let entry: LibraryEntry
    let anime: Anime
    let status: LibraryAiringProgress
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AnimeLink(id: anime.id) { AnimeCover(anime: anime, width: 62, cornerRadius: 9, identifierPrefix: "library") }
                .buttonStyle(.plain).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                AnimeLink(id: anime.id) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(anime.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(3)
                        Spacer(minLength: 0)
                    }.foregroundStyle(.primary).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("library-entry-\(anime.id)")
                AiringReleaseProgress(status: status, animeID: anime.id)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .modifier(LibraryEntryActions(entry: entry, anime: anime))
    }
}

private struct AiringReleaseProgress: View {
    let status: LibraryAiringProgress
    let animeID: Int
    private var color: Color { status.state == .behind ? Theme.highlight : status.state.color }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: status.state.symbol).accessibilityHidden(true)
                Text(status.label).accessibilityIdentifier("library-airing-status-\(animeID)")
            }.font(.caption.weight(.semibold)).foregroundStyle(color)
            Text("Watched Ep \(status.watched)" + (status.released.map { " · Aired Ep \($0)" } ?? ""))
                .font(.caption2).foregroundStyle(.secondary)
                .accessibilityIdentifier("library-airing-progress-\(animeID)")
            if let released = status.released, released > 0 {
                ProgressView(value: Double(min(status.watched, released)), total: Double(released))
                    .tint(color).accessibilityLabel("\(status.watched) watched, \(released) aired")
            }
            if let next = status.nextEpisode, let date = status.nextDate {
                Text("Next \(status.source.shortLabel)\(status.estimatedDate ? " estimate" : "") · Ep \(next) · \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("library-airing-next-\(animeID)")
            } else {
                Text("Next \(status.source.shortLabel) time not announced").font(.caption2).foregroundStyle(.secondary)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
}
