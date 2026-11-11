import SwiftUI
import AnimeCore

struct MangaBakaLibraryView: View {
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var preferences: AppStore
    @AppStorage("library.reading.defaultStatus") private var defaultStatus = LibraryScope.reading.initialStatus
    @State private var state = LibraryScope.reading.openingStatus()
    @State private var search = ""
    @AppStorage("mangabaka.library.layout") private var layout = "grid"
    @AppStorage("mangabaka.library.sort") private var sortValue = ReadingLibrarySort.updated.rawValue
    @AppStorage("mangabaka.library.ascending") private var ascending = false
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var connection = false
    @State private var appSettings = false
    @State private var contentRatings = false
    @State private var display = false
    @State private var availableWidth: CGFloat = 390
    private var posters = PosterPreferences(.library)
    private var entries: [MangaBakaLibraryEntry] {
        let values = account.library.filter { entry in
            guard selectedState == nil || entry.state == selectedState else { return false }
            guard let series = entry.series, series.isVisible(contentFilter: preferences.mangaBakaContent) else { return false }
            return search.isEmpty || series.searchTitles.contains { $0.localizedCaseInsensitiveContains(search) }
        }
        return (ReadingLibrarySort(rawValue: sortValue) ?? .updated).sorted(values, ascending: ascending)
    }
    var body: some View {
        Group {
            if account.connected { connectedLibrary }
            else {
                ContentUnavailableView {
                    Label("Your reading life, together", systemImage: "books.vertical")
                } description: {
                    Text("Connect MangaBaka to keep manga, manhwa, novels and more in My Library. You can explore without signing in.")
                } actions: { Button("Connect MangaBaka") { connection = true }.buttonStyle(.borderedProminent) }
            }
        }.background(Theme.background).navigationTitle("My Library").navigationBarTitleDisplayMode(.inline)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Display options", systemImage: "rectangle.grid.2x2") { display = true }
                    Button("Content ratings", systemImage: "eye") { contentRatings = true }
                    Button("Account & settings", systemImage: "gearshape") { appSettings = true }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Library options")
            } }
            .appSettingsSheet(isPresented: $appSettings)
            .sheet(isPresented: $display) { DisplayOptionsView(scope: .library) }
            .sheet(isPresented: $contentRatings) {
                AppNavigationStack { MangaBakaContentSettingsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { contentRatings = false } } } }
            }
            .sheet(isPresented: $connection) {
                AppNavigationStack { MangaBakaAccountView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { connection = false } } } }
            }
            .onChange(of: defaultStatus) { _, _ in state = LibraryScope.reading.openingStatus() }
            .task(id: "\(state)-\(account.revision)") { await account.loadCompleteLibrary(state: selectedState, refresh: true) }
    }
    private var selectedState: String? { state == "all" ? nil : state }
    private var connectedLibrary: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MangaBaka").font(.title2.bold())
                        Text(account.profile?.name ?? "Your reading library").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let total = account.libraryTotal { Text("\(total.formatted()) titles").font(.caption).foregroundStyle(.secondary) }
                }
                HStack {
                    ReadingLibrarySortControls(scope: .reading, sortValue: $sortValue, ascending: $ascending)
                    Spacer(minLength: 8)
                    Picker("Library layout", selection: $layout) {
                        Image(systemName: "square.grid.2x2").accessibilityLabel("Poster grid").tag("grid")
                        Image(systemName: "list.bullet").accessibilityLabel("Detailed list").tag("list")
                    }.pickerStyle(.segmented).frame(width: 108).accessibilityIdentifier("reading-library-layout")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        status("All", value: "all")
                        ForEach(MangaBakaReadingStatus.allCases, id: \.self) { value in status(value.label, value: value.rawValue) }
                    }
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter loaded titles", text: $search).textInputAutocapitalization(.never)
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear filter") }
                }.padding(13).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                if account.hasMoreLibrary {
                    Text("\(account.library.count.formatted()) titles loaded. Syncing the rest of this list for complete search and sorting…").font(.caption).foregroundStyle(.secondary)
                }
                if let error = account.libraryError { NoticeView(message: error) { Task { await account.loadCompleteLibrary(state: selectedState, refresh: true) } } }
                if let notice = account.notice { Text(notice).font(.caption).foregroundStyle(.mint) }
                if entries.isEmpty && !account.loadingLibrary && account.libraryError == nil {
                    ContentUnavailableView("No visible titles", systemImage: "book.closed",
                        description: Text(account.hasMoreLibrary ? "Load more entries, or adjust your filters." : "Add a series from Explore, or choose another reading status."))
                }
                if layout == "grid" {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: CGFloat(LibraryArtworkSizing.gridMinimum(preferred: posters.libraryGridMinimum, accessible: textSize.isAccessibilitySize))), spacing: 14)], alignment: .leading, spacing: 22) {
                        ForEach(entries) { entry in
                            if let series = entry.series {
                                NavigationLink(value: MangaBakaSeriesRoute(series: series)) { MangaBakaLibraryTile(entry: entry, series: series) }
                                    .buttonStyle(.plain)
                                    .contextMenu { MangaLibrarySourceMenu(series: series) }
                            }
                        }
                    }.accessibilityIdentifier("mangabaka-library-grid")
                } else {
                    ForEach(entries) { entry in
                        if let series = entry.series {
                            NavigationLink(value: MangaBakaSeriesRoute(series: series)) {
                                MangaBakaLibraryRow(entry: entry, series: series,
                                    posterWidth: CGFloat(LibraryArtworkSizing.listWidth(preferred: posters.listWidth, availableWidth: Double(max(0, min(availableWidth, 1000) - 40)), accessible: textSize.isAccessibilitySize)))
                            }
                                .buttonStyle(.plain)
                                .contextMenu { MangaLibrarySourceMenu(series: series) }
                        }
                    }
                }
                if account.loadingLibrary { ProgressView("Loading your library…").frame(maxWidth: .infinity).padding() }
                else if account.hasMoreLibrary {
                    Button("Continue syncing My Library") { Task { await account.loadCompleteLibrary(state: selectedState) } }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity)
                }
                MangaBakaAttribution().padding(.top, 12)
            }.padding(20).frame(maxWidth: layout == "grid" ? 1180 : 1000).frame(maxWidth: .infinity)
        }.refreshable { await account.loadCompleteLibrary(state: selectedState, refresh: true) }
    }
    private func status(_ title: String, value: String) -> some View {
        CompanionFilterChip(title: title, selected: state == value) { state = value }
            .accessibilityIdentifier("mangabaka-library-status-" + value)
    }
}

struct MangaBakaLibraryRow: View {
    let entry: MangaBakaLibraryEntry
    let series: MangaBakaSeries
    var posterWidth: CGFloat = 128
    private var statusText: String {
        let status = MangaBakaReadingStatus(rawValue: entry.state)?.label ?? entry.state.capitalized
        return series.formatLabel + " · " + status
    }
    private var progressText: String {
        let chapter = "Ch. " + (entry.chapter ?? 0).formatted()
        guard let volume = entry.volume else { return chapter }
        return chapter + " · Vol. " + volume.formatted()
    }
    var body: some View {
        HStack(spacing: 16) {
            MangaBakaCover(series: series, width: posterWidth)
            details.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(13).background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(series.displayTitle).font(.headline).lineLimit(3)
            Text(statusText).font(.caption).foregroundStyle(.secondary)
            Text(progressText).font(.subheadline.monospacedDigit())
            MangaSourceLinkBadge(series: series)
            if let total = series.totalChapters, total > 0 {
                ProgressView(value: min(max(0, entry.chapter ?? 0), total), total: total).tint(.mint)
            }
            if let rating = entry.rating { Label("\(rating)/100", systemImage: "star.fill").font(.caption).foregroundStyle(.yellow) }
        }
    }
}

struct MangaBakaTrackingView: View {
    @EnvironmentObject private var account: MangaBakaStore
    @Environment(\.dismiss) private var dismiss
    let series: MangaBakaSeries
    @State private var status = MangaBakaReadingStatus.planToRead.rawValue
    @State private var chapter = ""
    @State private var volume = ""
    @State private var rating = -1
    @State private var note = ""
    @State private var isPrivate = true
    @State private var existing = false
    @State private var ready = false
    @State private var loadedConnection: UUID?
    @State private var error: String?
    @State private var removing = false
    private var busy: Bool { account.saving.contains(series.id) }
    private var ratings: [Int] {
        let step = min(100, max(1, account.profile?.ratingSteps ?? 1))
        return Set(Array(stride(from: 0, through: 100, by: step)) + (rating >= 0 ? [rating] : [])).sorted()
    }
    var body: some View {
        Form {
            Section {
                Text(series.displayTitle).font(.headline)
                if let name = account.profile?.name { Text("MangaBaka · " + name).font(.caption).foregroundStyle(.secondary) }
            }
            if ready {
                Section("Reading progress") {
                    Picker("Status", selection: $status) {
                        ForEach(MangaBakaReadingStatus.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                    }
                    LabeledContent("Chapter") { TextField("Not set", text: $chapter).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    LabeledContent("Volume") { TextField("Not set", text: $volume).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    Picker("Your score", selection: $rating) {
                        Text("Unrated").tag(-1)
                        ForEach(ratings, id: \.self) { Text("\($0)/100").tag($0) }
                    }
                }
                Section {
                    TextField("Personal notes", text: $note, axis: .vertical).lineLimit(3...8)
                    Toggle("Private entry", isOn: $isPrivate)
                } footer: { Text("Saved to your MangaBaka account. This is separate from local reader history; reading a chapter does not automatically change this progress.") }
                if existing {
                    Section { Button("Remove from My Library", role: .destructive) { removing = true } }
                }
            } else if error == nil { ProgressView("Checking your MangaBaka entry…") }
            if let error {
                Section {
                    Text(error).foregroundStyle(.orange)
                    if !ready { Button("Try again") { Task { await load() } } }
                }
            }
        }.disabled(busy).navigationTitle(existing ? "Edit reading entry" : "Add to My Library").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { let connection = loadedConnection; Task { await save(connection: connection) } }
                        .disabled(!ready || busy || loadedConnection != account.connectionID)
                }
            }.task(id: account.connectionID) { await load() }
            .confirmationDialog("Remove this title from MangaBaka?", isPresented: $removing) {
                Button("Remove from My Library", role: .destructive) {
                    let connection = loadedConnection
                    Task {
                        guard let connection else { return }
                        do { try await account.remove(series, expectedConnection: connection); dismiss() }
                        catch is CancellationError {} catch { self.error = error.localizedDescription }
                    }
                }
            } message: { Text("Its saved progress, score and notes will be removed from your MangaBaka library, not just this device.") }
    }
    private func load() async {
        let connection = account.connectionID
        ready = false; loadedConnection = nil; error = nil; removing = false
        status = MangaBakaReadingStatus.planToRead.rawValue; chapter = ""; volume = ""
        rating = -1; note = ""; isPrivate = true; existing = false
        do {
            let entry = try await account.loadEntry(series); try Task.checkCancellation()
            guard connection == account.connectionID else { return }
            existing = entry != nil
            if let entry {
                guard MangaBakaReadingStatus(rawValue: entry.state) != nil else { throw MangaBakaError.message("This entry uses a reading status the app does not yet support. Edit it on MangaBaka.") }
                status = entry.state; chapter = entry.chapter.map { $0.formatted(.number.grouping(.never)) } ?? ""
                volume = entry.volume.map { $0.formatted(.number.grouping(.never)) } ?? ""
                rating = entry.rating ?? -1; note = entry.note ?? ""; isPrivate = entry.isPrivate
            }
            loadedConnection = connection; ready = true
        } catch is CancellationError {} catch { if connection == account.connectionID { self.error = error.localizedDescription } }
    }
    private func number(_ text: String) throws -> Double? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal; formatter.isLenient = false
        guard let value = formatter.number(from: text)?.doubleValue, value.isFinite, value >= 0 else {
            throw MangaBakaError.message("Progress must be a positive number, zero, or blank.")
        }
        return value
    }
    private func save(connection: UUID?) async {
        guard let connection, connection == account.connectionID else { return }
        error = nil
        do {
            let update = try MangaBakaLibraryUpdate(state: status, chapter: number(chapter), volume: number(volume),
                rating: rating < 0 ? nil : rating, note: note.isEmpty ? nil : note, isPrivate: isPrivate)
            try await account.save(series, update: update, existing: existing, expectedConnection: connection); dismiss()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct MangaBakaAccountView: View {
    @EnvironmentObject private var account: MangaBakaStore
    var useAccount: (() -> Void)? = nil
    @State private var removingAccount: MangaBakaAccountIdentity?
    var body: some View {
        Form {
            Section {
                Label(account.connected ? "Connected to MangaBaka" : "Bring your reading library", systemImage: account.connected ? "checkmark.circle.fill" : "books.vertical")
                    .font(.headline).foregroundStyle(account.connected ? .mint : .primary)
                if let profile = account.profile { Text(profile.name).foregroundStyle(.secondary).privacySensitive().accessibilityIdentifier("mangabaka-active-name") }
                if account.connected {
                    Text("Your reading library, progress and recommendations belong to the selected account.").font(.subheadline).foregroundStyle(.secondary)
                    if let useAccount {
                        Button(action: useAccount) { Label("Open MangaBaka library", systemImage: "books.vertical") }
                            .foregroundStyle(.mint).accessibilityIdentifier("account-use-mangabaka")
                    }
                } else {
                    Text("Explore without signing in, or add an account to track your reading library.").font(.subheadline).foregroundStyle(.secondary)
                }
                if let error = account.accountError { Text(error).foregroundStyle(.orange) }
                if account.connecting { ProgressView("Connecting securely…") }
            }
            if !account.savedAccounts.isEmpty {
                Section {
                    ForEach(account.savedAccounts) { saved in
                        Button { account.selectAccount(saved.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(.mint)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(saved.name).foregroundStyle(.primary)
                                    Text(saved.id == account.activeAccountID ? "Active" : "Tap to switch")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: saved.id == account.activeAccountID ? "checkmark.circle.fill" : "arrow.right.circle")
                                    .foregroundStyle(saved.id == account.activeAccountID ? Color.mint : .secondary)
                            }.padding(.vertical, 6).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(account.connecting || !account.saving.isEmpty)
                            .accessibilityLabel("Switch to " + saved.name)
                            .accessibilityValue(saved.id == account.activeAccountID ? "Active" : "Saved")
                            .accessibilityIdentifier("mangabaka-saved-account-" + (saved.profile?.id ?? saved.id.uuidString))
                            .swipeActions { Button("Remove", role: .destructive) { removingAccount = saved } }
                    }
                } header: { Text("Saved accounts") } footer: {
                    Text("Tap a name to switch immediately. Your other MangaBaka accounts stay saved.")
                }
            }
            Section(account.connected ? "Add another account" : "Connect your library") {
                MangaBakaKeyEntry()
            }
            if let selected = account.savedAccounts.first(where: { $0.id == account.activeAccountID }) {
                Section {
                    Button("Remove selected account", role: .destructive) { removingAccount = selected }
                        .disabled(account.connecting || !account.saving.isEmpty).accessibilityIdentifier("mangabaka-remove-selected")
                }
            }
            Section {
                Label("Stored on this device", systemImage: "lock.shield")
                Text("Each person connects with their own key. Saved accounts use this device's Keychain and keep separate reading libraries and recommendations.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("MangaBaka account").navigationBarTitleDisplayMode(.inline)
            .alert("Remove saved MangaBaka account?", isPresented: Binding(get: { removingAccount != nil }, set: { if !$0 { removingAccount = nil } })) {
                Button("Remove", role: .destructive) {
                    if let removingAccount { account.removeAccount(removingAccount.id) }
                    removingAccount = nil
                }
                Button("Cancel", role: .cancel) { removingAccount = nil }
            } message: {
                Text("Remove " + (removingAccount?.name ?? "this account") + " from this device? Other saved accounts and online libraries stay available.")
            }
    }
}
