import SwiftUI
import AnimeCore

struct MangaBakaLibraryView: View {
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var preferences: AppStore
    @State private var state = "all"
    @State private var search = ""
    @State private var connection = false
    private var entries: [MangaBakaLibraryEntry] {
        account.library.filter { entry in
            guard let series = entry.series, series.isVisible(includeAdult: preferences.includeAdult) else { return false }
            return search.isEmpty || series.searchTitles.contains { $0.localizedCaseInsensitiveContains(search) }
        }
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { connection = true } label: { Image(systemName: "person.crop.circle") }.accessibilityLabel("MangaBaka account")
                }
            }
            .sheet(isPresented: $connection) {
                NavigationStack { MangaBakaAccountView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { connection = false } } } }
            }
            .task(id: "\(state)-\(account.revision)") { await account.loadLibrary(state: selectedState, refresh: true) }
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
                if !search.isEmpty && account.hasMoreLibrary {
                    Text("Filtering \(account.library.count) loaded titles. Load more to search the rest of this list.").font(.caption).foregroundStyle(.secondary)
                }
                if let error = account.libraryError { NoticeView(message: error) { Task { await account.loadLibrary(state: selectedState, refresh: true) } } }
                if let notice = account.notice { Text(notice).font(.caption).foregroundStyle(.mint) }
                if entries.isEmpty && !account.loadingLibrary && account.libraryError == nil {
                    ContentUnavailableView("No visible titles", systemImage: "book.closed",
                        description: Text(account.hasMoreLibrary ? "Load more entries, or adjust your filters." : "Add a series from Explore, or choose another reading status."))
                }
                ForEach(entries) { entry in
                    if let series = entry.series {
                        NavigationLink(value: MangaBakaSeriesRoute(series: series)) { row(entry, series: series) }.buttonStyle(.plain)
                    }
                }
                if account.loadingLibrary { ProgressView("Loading your library…").frame(maxWidth: .infinity).padding() }
                else if account.hasMoreLibrary {
                    Button("Load more from My Library") { Task { await account.loadLibrary(state: selectedState, next: true) } }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity)
                }
                MangaBakaAttribution().padding(.top, 12)
            }.padding(20).frame(maxWidth: 1000).frame(maxWidth: .infinity)
        }.refreshable { await account.loadLibrary(state: selectedState, refresh: true) }
    }
    private func status(_ title: String, value: String) -> some View {
        Button { state = value } label: {
            Text(title).font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 9)
                .background(state == value ? Color.white : Theme.surface, in: Capsule())
                .foregroundStyle(state == value ? Color.black : Color.white)
        }.buttonStyle(.plain).accessibilityAddTraits(state == value ? .isSelected : [])
    }
    private func row(_ entry: MangaBakaLibraryEntry, series: MangaBakaSeries) -> some View {
        HStack(spacing: 16) {
            MangaBakaCover(series: series, width: 80)
            VStack(alignment: .leading, spacing: 9) {
                Text(series.displayTitle).font(.headline).lineLimit(3)
                Text(series.formatLabel + " · " + (MangaBakaReadingStatus(rawValue: entry.state)?.label ?? entry.state.capitalized))
                    .font(.caption).foregroundStyle(.secondary)
                Text("Ch. \(entry.chapter ?? 0, specifier: "%g")" + (entry.volume.map { " · Vol. " + $0.formatted() } ?? "")).font(.subheadline.monospacedDigit())
                if let total = series.totalChapters, total > 0 {
                    ProgressView(value: min(max(0, entry.chapter ?? 0), total), total: total).tint(.mint)
                }
                if let rating = entry.rating { Label("\(rating)/100", systemImage: "star.fill").font(.caption).foregroundStyle(.yellow) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(13).background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
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
    @State private var error: String?
    @State private var removing = false
    private var busy: Bool { account.saving.contains(series.id) }
    private var ratings: [Int] {
        let step = min(100, max(1, account.profile?.ratingSteps ?? 1))
        return Set(Array(stride(from: 0, through: 100, by: step)) + (rating >= 0 ? [rating] : [])).sorted()
    }
    var body: some View {
        Form {
            Section { Text(series.displayTitle).font(.headline) }
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
            if let error { Section { Text(error).foregroundStyle(.orange); if !ready { Button("Try again") { Task { await load() } } } }
        }.disabled(busy).navigationTitle(existing ? "Edit reading entry" : "Add to My Library").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(!ready || busy) }
            }.task { await load() }
            .confirmationDialog("Remove this title from MangaBaka?", isPresented: $removing) {
                Button("Remove from My Library", role: .destructive) {
                    Task { do { try await account.remove(series); dismiss() } catch { self.error = error.localizedDescription } }
                }
            } message: { Text("Its saved progress, score and notes will be removed from your MangaBaka library, not just this device.") }
    }
    private func load() async {
        ready = false; error = nil
        do {
            let entry = try await account.loadEntry(series); try Task.checkCancellation()
            existing = entry != nil
            if let entry {
                guard MangaBakaReadingStatus(rawValue: entry.state) != nil else { throw MangaBakaError.message("This entry uses a reading status the app does not yet support. Edit it on MangaBaka.") }
                status = entry.state; chapter = entry.chapter.map { $0.formatted(.number.grouping(.never)) } ?? ""
                volume = entry.volume.map { $0.formatted(.number.grouping(.never)) } ?? ""
                rating = entry.rating ?? -1; note = entry.note ?? ""; isPrivate = entry.isPrivate
            }
            ready = true
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
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
    private func save() async {
        error = nil
        do {
            let update = try MangaBakaLibraryUpdate(state: status, chapter: number(chapter), volume: number(volume),
                rating: rating < 0 ? nil : rating, note: note.isEmpty ? nil : note, isPrivate: isPrivate)
            try await account.save(series, update: update, existing: existing); dismiss()
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

struct MangaBakaAccountView: View {
    @EnvironmentObject private var account: MangaBakaStore
    @State private var clientID = UserDefaults.standard.string(forKey: "mangabaka.clientID") ?? ""
    @State private var apiKey = ""
    @State private var confirmation = false
    var body: some View {
        Form {
            Section {
                Label(account.connected ? "Connected to MangaBaka" : "Bring your reading library", systemImage: account.connected ? "checkmark.circle.fill" : "books.vertical")
                    .font(.headline).foregroundStyle(account.connected ? .mint : .primary)
                if let profile = account.profile { Text(profile.name).foregroundStyle(.secondary) }
                Text("Browse without an account. Connect to view your lists, save progress, rate titles and get personal recommendations.").font(.subheadline).foregroundStyle(.secondary)
                if account.connected {
                    Button("Disconnect", role: .destructive) { confirmation = true }.disabled(!account.saving.isEmpty)
                }
                if let error = account.accountError { Text(error).foregroundStyle(.orange) }
                if account.connecting { ProgressView("Connecting securely…") }
            }
            Section("Sign in with MangaBaka") {
                TextField("OAuth app ID", text: $clientID).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Sign in with MangaBaka") {
                    UserDefaults.standard.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "mangabaka.clientID")
                    Task { await account.connect() }
                }.disabled(clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || account.connecting || !account.saving.isEmpty)
                Text("Browser sign-in needs a MangaBaka-registered public OAuth app ID. Use the redirect below and enable PKCE (S256), library.read, library.write and offline_access. Your password is entered only on MangaBaka.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Redirect") { Text(MangaBakaOAuth.callback.absoluteString).font(.caption.monospaced()).textSelection(.enabled) }
                Link("MangaBaka API & developer information", destination: URL(string: "https://mangabaka.org/data/api")!)
            }
            Section {
                DisclosureGroup("Use your own API key") {
                    SecureField("MangaBaka API key", text: $apiKey).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    Button("Connect with key") {
                        let key = apiKey; apiKey = ""
                        Task { await account.connect(apiKey: key) }
                    }.disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || account.connecting || !account.saving.isEmpty)
                    Text("If MangaBaka has issued you a personal key, you can connect with it instead. It needs access to your profile and library. Never enter another person's key or an OAuth app secret.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } footer: { Text("Connection credentials are saved in this device's Keychain. Private library data and personal recommendations are not written to the public catalog cache. Disconnect removes local account data; your MangaBaka library stays online.") }
        }.navigationTitle("MangaBaka account").navigationBarTitleDisplayMode(.inline)
            .onAppear { if clientID.isEmpty { clientID = account.clientID } }
            .onDisappear { apiKey = "" }
            .confirmationDialog("Disconnect MangaBaka?", isPresented: $confirmation) {
                Button("Disconnect", role: .destructive) { account.disconnect() }
            } message: { Text("Your MangaBaka library stays online. The connection and private lists are removed from this device.") }
    }
}
