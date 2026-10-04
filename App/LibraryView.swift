import SwiftUI
import AnimeCore

private enum LibrarySort: String, CaseIterable {
    case airing = "Airing schedule", title = "Title", updated = "Last updated", progress = "Progress", score = "Your score"
}

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selected: LibraryStatus = .watching
    @State private var query = ""
    @State private var sort = LibrarySort.airing
    @State private var reversed = false
    @State private var showSettings = false
    @State private var continueExpanded = false
    @State private var comingExpanded = false
    @State private var dubEvents: [ReleaseEvent] = []
    @State private var dubError: String?
    @FocusState private var searchFocused: Bool
    private let statuses: [LibraryStatus] = [.watching, .planning, .completed, .dropped, .paused, .rewatching]

    private var comingUp: [ReleaseEvent] {
        let originals = store.watching.compactMap { entry -> ReleaseEvent? in
            guard let anime = entry.media, let next = anime.nextAiringEpisode else { return nil }
            return ReleaseEvent(anime: anime, episode: next.episode, kind: .sub, date: next.date, certainty: .broadcast)
        }
        let ids = Set(store.watching.map(\.mediaId))
        let end = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date().addingTimeInterval(604800)
        return (originals + dubEvents.filter { ids.contains($0.anime.id) }).filter {
            guard let date = $0.date else { return false }; return date >= Date() && date < end
        }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
    private var filtered: [LibraryEntry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = store.entries.filter { entry in
            guard entry.status == selected, let anime = entry.media else { return false }
            return text.isEmpty || [anime.displayTitle, anime.title?.romaji ?? "", anime.title?.english ?? ""].contains { $0.localizedCaseInsensitiveContains(text) }
        }
        return entries.sorted { a, b in
            switch sort {
            case .airing:
                let first = a.media?.nextAiringEpisode?.date, second = b.media?.nextAiringEpisode?.date
                // Keep entries without announced airings at the end in either direction.
                if (first == nil) != (second == nil) { return first != nil }
                if let first, let second, first != second { return reversed ? first > second : first < second }
            case .title: break
            case .updated:
                if a.updatedAt != b.updatedAt { return reversed ? (a.updatedAt ?? 0) < (b.updatedAt ?? 0) : (a.updatedAt ?? 0) > (b.updatedAt ?? 0) }
            case .progress:
                if a.progressValue != b.progressValue { return reversed ? a.progressValue < b.progressValue : a.progressValue > b.progressValue }
            case .score:
                if a.score != b.score { return reversed ? (a.score ?? 0) < (b.score ?? 0) : (a.score ?? 0) > (b.score ?? 0) }
            }
            let order = (a.media?.displayTitle ?? "").localizedStandardCompare(b.media?.displayTitle ?? "")
            if order == .orderedSame { return a.mediaId < b.mediaId }
            return reversed && sort == .title ? order == .orderedDescending : order == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if store.isSignedIn {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        searchBar
                        personalSections
                        statusTabs
                        sortingBar
                        if let error = store.libraryError { NoticeView(message: error) { Task { await store.reloadLibrary() } } }
                        if store.loadingLibrary { ProgressView("Syncing AniList…").frame(maxWidth: .infinity) }
                        LazyVStack(spacing: 12) {
                            ForEach(filtered) { entry in
                                if let anime = entry.media {
                                    LibraryAnimeRow(entry: entry, anime: anime, nextDub: nextDub(for: anime.id))
                                }
                            }
                        }
                        if filtered.isEmpty && !store.loadingLibrary && store.libraryError == nil {
                            ContentUnavailableView(query.isEmpty ? "Your \(selected.label.lowercased()) list is empty" : "No matching anime",
                                                   systemImage: "books.vertical", description: Text(query.isEmpty ? "Add a title from Explore." : "Try another title or list status."))
                        }
                        if let date = store.savedAt { Text("Last synced \(date.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.horizontal, 12).padding(.vertical)
                }.scrollDismissesKeyboard(.interactively).refreshable { await store.reloadLibrary(); await loadDubs(refresh: true) }
            } else {
                LibraryGuestView(showSettings: $showSettings)
            }
        }.background(Theme.background).navigationTitle("My Library").navigationBarTitleDisplayMode(.inline).animeNavigation()
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Account and settings") } }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .task(id: store.entries.map(\.mediaId)) { await loadDubs() }
    }
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search your anime", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                .accessibilityIdentifier("library-search")
            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear library search") }
        }.padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
    private var statusTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(statuses) { status in
                    Button { selected = status } label: {
                        Text(status.label).font(.subheadline.bold()).padding(.horizontal, 14).padding(.vertical, 12)
                            .foregroundStyle(selected == status ? Color.black : Color.white)
                            .background(selected == status ? Color.white : Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityIdentifier("library-status-\(status.rawValue)")
                        .accessibilityAddTraits(selected == status ? .isSelected : [])
                }
            }
        }
    }
    private var sortingBar: some View {
        HStack {
            Text("\(filtered.count)").font(.subheadline.bold()).padding(.horizontal, 11).padding(.vertical, 5).background(Theme.surface, in: Capsule())
                .accessibilityLabel("\(filtered.count) anime in this list")
            Spacer()
            Menu {
                Picker("Sort your library", selection: $sort) { ForEach(LibrarySort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            } label: { Label(sort.rawValue, systemImage: "arrow.up.arrow.down").font(.subheadline).padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10)) }
            Button { reversed.toggle() } label: { Image(systemName: reversed ? "arrow.down" : "arrow.up").frame(width: 40, height: 40).background(Theme.surface, in: Circle()) }
                .accessibilityLabel("Reverse library sort")
        }
    }
    private var personalSections: some View {
        VStack(spacing: 12) {
            if !store.watching.isEmpty {
                DisclosureGroup("Continue watching", isExpanded: $continueExpanded) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(store.watching) { entry in
                                if let anime = entry.media {
                                    VStack(alignment: .leading, spacing: 6) {
                                        AnimeCard(anime: anime)
                                        Text("\(entry.progressValue)/\(anime.episodes.map(String.init) ?? "?") episodes").font(.caption).foregroundStyle(.secondary)
                                    }.frame(width: 130)
                                }
                            }
                        }.padding(.vertical, 10)
                    }
                }.accessibilityIdentifier("library-continue-watching")
                DisclosureGroup("Coming up for you", isExpanded: $comingExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(comingUp.prefix(8))) { ReleaseRow(event: $0) }
                        if comingUp.isEmpty { Text("No listed releases for your watching list in the next seven days.").font(.caption).foregroundStyle(.secondary) }
                        if let dubError { Text(dubError).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.top, 10)
                }.accessibilityIdentifier("library-coming-up")
            }
        }.font(.subheadline.weight(.semibold))
    }
    private func nextDub(for id: Int) -> ReleaseEvent? {
        dubEvents.first { $0.anime.id == id && ($0.date ?? .distantPast) >= Date() }
    }
    private func loadDubs(refresh: Bool = false) async {
        let entries = store.entries; let ids = Set(entries.map(\.mediaId))
        dubEvents = []; dubError = nil
        guard !ids.isEmpty else { return }
        do {
            let snapshot = try await store.dubs.snapshot(refresh: refresh)
            try Task.checkCancellation()
            guard ids == Set(store.entries.map(\.mediaId)) else { return }
            let known = Dictionary(uniqueKeysWithValues: entries.compactMap { $0.media.map { ($0.id, $0) } })
            dubEvents = snapshot.events(knownMedia: known).filter { ids.contains($0.anime.id) }
        } catch is CancellationError {} catch { if ids == Set(store.entries.map(\.mediaId)) { dubError = "Dub dates are temporarily unavailable." } }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var clientID = AppConfiguration.clientID ?? ""
    @State private var confirmation = false
    var body: some View {
        NavigationStack {
            Form {
                Section("AniList connection") {
                    if store.isSignedIn {
                        Text(store.viewer.map { "Signed in as \($0.name)" } ?? "Connected to AniList")
                        Button("Refresh library") { Task { await store.reloadLibrary() } }.disabled(store.loadingLibrary)
                        Button("Disconnect", role: .destructive) { confirmation = true }.disabled(!store.savingMedia.isEmpty)
                    } else {
                        TextField("AniList app ID", text: $clientID).keyboardType(.numberPad)
                        Button("Connect AniList") {
                            UserDefaults.standard.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "anilist.clientID")
                            Task { await store.connect() }
                        }.disabled(Int(clientID) == nil || store.connecting)
                        if store.connecting { ProgressView("Opening AniList…") }
                        Link("Register this app on AniList", destination: URL(string: "https://anilist.co/settings/developer")!)
                        Text("Use this redirect URL when creating the app:").font(.caption)
                        Text(AppConfiguration.callback.absoluteString).font(.caption.monospaced()).textSelection(.enabled)
                        Text("Enter the client ID only. Your AniList password stays on AniList.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = store.accountError { Text(error).foregroundStyle(.red) }
                }
                Section("Data sources") {
                    Link("Anime metadata and lists · AniList", destination: URL(string: "https://anilist.co")!)
                    Link("Dub dates · AniSchedule by Bas1874", destination: URL(string: "https://github.com/Bas1874/AniSchedule")!)
                    Link("Dub data © MyDubList · CC BY 4.0", destination: URL(string: "https://mydublist.com")!)
                    Link("MyDubList dataset license", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                    Text("Data is matched by IDs and formatted for display; no source records are edited.").font(.caption).foregroundStyle(.secondary)
                    Link("Report inaccurate dub data", destination: URL(string: "https://github.com/Joelis57/MyDubList/issues/new/choose")!)
                    Link("News · Anime News Network", destination: URL(string: "https://www.animenewsnetwork.com")!)
                }
                Section("About") {
                    Text("Anime Companion · First build")
                    Text("Broadcast times and dub dates may change. Times use your device timezone. Original Japanese broadcasts do not guarantee local subtitle availability.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .confirmationDialog("Disconnect from AniList?", isPresented: $confirmation) {
                    Button("Disconnect", role: .destructive) { store.disconnect() }
                } message: { Text("Your AniList lists stay on AniList. This removes the saved connection from this device.") }
        }
    }
}
