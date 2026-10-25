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
            VStack(alignment: .leading, spacing: 20) {
                header
                if store.isSignedIn {
                    summary
                    if let error = store.libraryError { NoticeView(message: error) { Task { await store.reloadLibrary() } } }
                    if store.loadingLibrary { ProgressView("Syncing AniList…").frame(maxWidth: .infinity) }
                    if store.airingProgressSource == .dub && dubs.loading { ProgressView("Checking English dub releases…").frame(maxWidth: .infinity) }
                    LazyVStack(spacing: 14) {
                        ForEach(AiringWatchlistGroup.allCases) { group in
                            let grouped = visible.filter { AiringWatchlistGroup(state: $0.status.state) == group }
                            if !grouped.isEmpty {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack {
                                        Text(group.title).font(.headline)
                                        Spacer()
                                        Text("\(grouped.count)").font(.caption).foregroundStyle(.secondary)
                                    }.padding(.top, 6).accessibilityIdentifier("schedule-group-\(group.rawValue)")
                                    if layout == "grid" {
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 230 : 160), spacing: 14)], alignment: .leading, spacing: 18) {
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
            HStack {
                Text("View").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("Airing Now layout", selection: $layout) {
                    Label("List", systemImage: "list.bullet").tag("list")
                    Label("Grid", systemImage: "square.grid.2x2").tag("grid")
                }.pickerStyle(.segmented).frame(maxWidth: 220).accessibilityIdentifier("schedule-airing-layout")
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

private struct AiringWatchlistGridCard: View {
    let entry: LibraryEntry
    let anime: Anime
    let status: LibraryAiringProgress
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AnimeLink(id: anime.id) {
                VStack(alignment: .leading, spacing: 9) {
                    GeometryReader { geometry in AnimeCover(anime: anime, width: geometry.size.width, cornerRadius: 12) }
                        .aspectRatio(1 / 1.45, contentMode: .fit)
                        .overlay(alignment: .topTrailing) { DiscoveryAiringDot(anime: anime, overArtwork: true, identifierPrefix: "library").padding(8) }
                    Text(anime.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(3, reservesSpace: true)
                    Text(status.source.label).font(.caption2).foregroundStyle(.secondary)
                }.foregroundStyle(.primary).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("library-entry-\(anime.id)")
            LibraryAiringStatus(status: status, animeID: anime.id, compact: true)
            LibraryEntryActions(entry: entry, anime: anime, horizontal: true).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(10).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(status.state.color.opacity(0.25), lineWidth: 1) }
    }
}

/// One release/progress block per title, rather than repeating the generic
/// Library row's watched, next, dub, rating and schedule information.
private struct AiringWatchlistCard: View {
    let entry: LibraryEntry
    let anime: Anime
    let status: LibraryAiringProgress
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                AnimeLink(id: anime.id) {
                    HStack(alignment: .top, spacing: 12) {
                        AnimeCover(anime: anime, width: 58, cornerRadius: 7)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(anime.displayTitle).font(.headline).lineLimit(3)
                                DiscoveryAiringDot(anime: anime, identifierPrefix: "library")
                            }
                            Text(status.source.label).font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.foregroundStyle(.primary).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("library-entry-\(anime.id)")
                LibraryAiringStatus(status: status, animeID: anime.id, compact: true)
                AnimeGenres(anime: anime).accessibilityIdentifier("library-genres-\(anime.id)")
            }
            LibraryEntryActions(entry: entry, anime: anime)
        }.padding(12).background(Theme.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(status.state.color.opacity(0.25), lineWidth: 1) }
    }
}
