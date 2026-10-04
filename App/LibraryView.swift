import SwiftUI
import AnimeCore

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selected: LibraryStatus = .watching
    @State private var showSettings = false
    var body: some View {
        Group {
            if store.isSignedIn {
                List {
                    Section {
                        Picker("List", selection: $selected) { ForEach(LibraryStatus.allCases) { Text($0.label).tag($0) } }
                        if let name = store.viewer?.name { Text("Connected as \(name)").font(.caption).foregroundStyle(.secondary) }
                        if let date = store.savedAt { Text("Last synced \(date.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary) }
                    }
                    if let error = store.libraryError { NoticeView(message: error) { Task { await store.reloadLibrary() } } }
                    if store.loadingLibrary { ProgressView("Syncing AniList…") }
                    let entries = store.entries.filter { $0.status == selected }
                    ForEach(entries) { entry in
                        if let anime = entry.media {
                            VStack(alignment: .leading, spacing: 10) {
                                NavigationLink(value: AnimeRoute(id: anime.id)) {
                                    HStack(spacing: 12) {
                                        AnimeCover(anime: anime, width: 52)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(anime.displayTitle).font(.headline)
                                            Text("Episode \(entry.progressValue) / \(anime.episodes.map(String.init) ?? "?")").font(.subheadline).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                ProgressControl(anime: anime)
                            }.padding(.vertical, 6)
                        }
                    }
                    if entries.isEmpty && !store.loadingLibrary && store.libraryError == nil { Text("Your \(selected.label.lowercased()) list is empty.").foregroundStyle(.secondary) }
                }.refreshable { await store.reloadLibrary() }
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "books.vertical").font(.system(size: 46)).foregroundStyle(Theme.accent)
                    Text("Your anime, together").font(.title2.bold())
                    Text("Connect AniList to see your lists and update episode progress.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button { if AppConfiguration.clientID == nil { showSettings = true } else { Task { await store.connect() } } } label: {
                        if store.connecting { ProgressView() } else { Text("Connect AniList").frame(maxWidth: .infinity) }
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.connecting)
                    if let error = store.accountError { NoticeView(message: error) }
                    Text("Browsing and news work without an account.").font(.caption).foregroundStyle(.secondary)
                }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
            }
        }.navigationTitle("My Library").animeNavigation()
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Account and settings") } }
            .sheet(isPresented: $showSettings) { SettingsView() }
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
