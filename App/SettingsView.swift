import SwiftUI
import AnimeCore

/// A compact directory. Credentials, provider management and long explanations
/// live on their own screens instead of competing with everyday preferences.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let selectAccount: (TrackingAccount) -> Void
    var body: some View {
        AppNavigationStack {
            SettingsDirectoryView(close: { dismiss() }, selectAccount: selectAccount)
        }
    }
}

struct SettingsDirectoryView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var mangaBaka: MangaBakaStore
    @State private var setupGuide = false
    @State private var query = ""
    let close: () -> Void
    let selectAccount: (TrackingAccount) -> Void
    private func matches(_ value: String) -> Bool { query.isEmpty || value.localizedCaseInsensitiveContains(query) }
    var body: some View {
        Form {
            Section("Accounts") {
                if matches("Switch account profiles AniList MangaBaka") {
                    NavigationLink { AccountSwitcherView(showsSettings: false, close: close, select: selectAccount) } label: {
                        SettingsCategoryLabel(title: "Switch account", detail: "Your connected libraries", symbol: "person.2.crop.square.stack", tint: Theme.accent)
                    }.accessibilityIdentifier("settings-account-switcher")
                }
                if matches("AniList account sync anime") {
                    NavigationLink { AniListSettingsView() } label: {
                        SettingsCategoryLabel(title: "AniList", detail: store.viewer.map { $0.name } ?? (store.isSignedIn ? "Connected" : "Connect your anime library"), symbol: "play.rectangle", tint: .blue)
                    }.accessibilityIdentifier("settings-account")
                }
                if matches("MangaBaka account sync manga novel") {
                    NavigationLink { MangaBakaAccountView() } label: {
                        SettingsCategoryLabel(title: "MangaBaka", detail: mangaBaka.profile?.name ?? (mangaBaka.connected ? "Connected" : "Connect manga & novels"), symbol: "books.vertical", tint: .teal)
                    }.accessibilityIdentifier("settings-mangabaka-account")
                }
            }
            if query.isEmpty {
                Section("Your experience") {
                    NavigationLink { SourcesSettingsView() } label: {
                        SettingsCategoryLabel(title: "Sources & playback", detail: "Extensions, Stremio, AIOStreams, TorBox & VidHub", symbol: "puzzlepiece.extension", tint: Theme.accent)
                    }.accessibilityIdentifier("settings-sources")
                    NavigationLink { AppearanceSettingsView() } label: {
                        SettingsCategoryLabel(title: "Appearance & layout", detail: "Theme, Home, navigation & Explore", symbol: "paintpalette", tint: .indigo)
                    }.accessibilityIdentifier("settings-personalization")
                }
            } else {
                SourcesSettingsRows(query: query)
                if matches("Appearance layout color theme light dark system Home navigation tabs iPad Explore") {
                    NavigationLink("Appearance & layout") { AppearanceSettingsView() }.accessibilityIdentifier("settings-personalization")
                }
            }
            Section("Preferences") {
                if matches("Community discussions Reddit MyAnimeList AniList comments sources") {
                    NavigationLink { CommunitySourcesView() } label: {
                        SettingsCategoryLabel(title: "Community sources", detail: "Discussions, readers & access", symbol: "bubble.left.and.bubble.right", tint: Theme.accent)
                    }.accessibilityIdentifier("settings-community")
                }
                if matches("Content browsing explicit adult ratings filters privacy") {
                    NavigationLink { BrowsingSettingsView() } label: {
                        SettingsCategoryLabel(title: "Content preferences", detail: "Ratings, explicit content & filtering", symbol: "line.3.horizontal.decrease.circle", tint: .orange)
                    }.accessibilityIdentifier("settings-browsing")
                }
                if matches("Library defaults status watching reading progress sorting") {
                    NavigationLink { LibraryPreferencesView() } label: {
                        SettingsCategoryLabel(title: "Library defaults", detail: "Your starting lists & status", symbol: "books.vertical", tint: .teal)
                    }.accessibilityIdentifier("settings-library-defaults")
                }
                if matches("Watch tracking progress completion airing dub") {
                    NavigationLink { TrackingSettingsView() } label: {
                        SettingsCategoryLabel(title: "Watch tracking", detail: "Catch-up status & completion", symbol: "checkmark.circle", tint: .green)
                    }.accessibilityIdentifier("settings-tracking")
                }
            }
            Section {
                if matches("Setup guide onboarding connect configure") {
                    Button { setupGuide = true } label: { Label("Setup Guide", systemImage: "sparkles") }.accessibilityIdentifier("settings-setup-guide")
                }
                if matches("About data sources licenses version") {
                    NavigationLink { AboutSettingsView() } label: { Label("About & data sources", systemImage: "info.circle") }.accessibilityIdentifier("settings-about")
                }
            } footer: {
                Text("AnimeCompanion \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")")
                    .font(.caption).frame(maxWidth: .infinity).padding(.top, 8)
            }
        }.navigationTitle("Settings").searchable(text: $query, prompt: "Search settings & services")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
            .fullScreenCover(isPresented: $setupGuide) { FirstRunSetupView(revisiting: true) { setupGuide = false } }
    }
}

private struct AppSettingsSheet: ViewModifier {
    @EnvironmentObject private var navigation: AppNavigationStore
    @Binding var isPresented: Bool
    @State private var selectedAccount: TrackingAccount?
    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: {
            navigation.applyLayoutPreference(); navigation.applyTabPreferences()
            if let selectedAccount { self.selectedAccount = nil; navigation.openAccountLibrary(selectedAccount) }
        }) {
            SettingsView { account in selectedAccount = account; isPresented = false }
        }
    }
}

extension View {
    func appSettingsSheet(isPresented: Binding<Bool>) -> some View {
        modifier(AppSettingsSheet(isPresented: isPresented))
    }
}

struct TabletLayoutSettingsView: View {
    @AppStorage(TabletLayout.preferenceKey) private var layoutValue = TabletLayout.sidebar.rawValue
    var body: some View {
        Form {
            Section {
                Toggle("Sidebar navigation", isOn: Binding(get: { TabletLayout(preference: layoutValue) == .sidebar },
                    set: { layoutValue = ($0 ? TabletLayout.sidebar : .fullWidth).rawValue }))
                    .accessibilityIdentifier("settings-ipad-sidebar")
                Toggle("Side-by-side browsing", isOn: Binding(get: {
                    TabletLayout(preference: layoutValue) == .sideBySide
                }, set: { layoutValue = ($0 ? TabletLayout.sideBySide : .fullWidth).rawValue }))
                    .accessibilityIdentifier("settings-ipad-split-view")
            } header: { Text("iPad layout") } footer: {
                Text("Choose sidebar navigation for quick access to every area. Side-by-side browsing keeps anime results beside details. Turn both off for single-column pages. Compact windows adapt automatically. Changes apply when Settings closes.")
            }
        }.navigationTitle("iPad layout").navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsCategoryLabel: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(tint)
                .frame(width: 34, height: 34).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 3)
        }
    }
}

struct AniListSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var clientID = AppConfiguration.clientID ?? ""
    @State private var confirmation = false
    var useAccount: (() -> Void)? = nil
    var body: some View {
        Form {
            Section("Connection") {
                if store.isSignedIn {
                    Label(store.viewer.map { "Signed in as \($0.name)" } ?? "Connected to AniList", systemImage: "checkmark.circle.fill").foregroundStyle(.mint)
                    if let useAccount {
                        Button(action: useAccount) { Label("Open AniList library", systemImage: "play.rectangle") }
                            .foregroundStyle(.mint).accessibilityIdentifier("account-use-anilist")
                    }
                    Button("Refresh library") { Task { await store.reloadLibrary() } }.disabled(store.loadingLibrary || !store.savingMedia.isEmpty)
                    if store.loadingLibrary { ProgressView("Refreshing library…") }
                    Button("Disconnect", role: .destructive) { confirmation = true }.disabled(!store.savingMedia.isEmpty)
                } else {
                    TextField("AniList app ID", text: $clientID).keyboardType(.numberPad)
                    Button("Connect AniList") {
                        UserDefaults.standard.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "anilist.clientID")
                        Task { await store.connect() }
                    }.disabled(Int(clientID) == nil || store.connecting)
                    if store.connecting { ProgressView("Opening AniList…") }
                }
                if let error = store.accountError { Text(error).foregroundStyle(.orange) }
            }
            if !store.isSignedIn {
                Section("App registration") {
                    Link("Register this app on AniList", destination: URL(string: "https://anilist.co/settings/developer")!)
                    LabeledContent("Redirect URL") { Text(AppConfiguration.callback.absoluteString).font(.caption.monospaced()).textSelection(.enabled) }
                    Text("Enter the client ID only. Your AniList password stays on AniList.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("AniList account").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Disconnect from AniList?", isPresented: $confirmation) {
                Button("Disconnect", role: .destructive) { store.disconnect() }
            } message: { Text("Your lists stay on AniList. This removes the connection from this device.") }
    }
}

private struct BrowsingSettingsView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Form {
            Section {
                Toggle("Show adult content (18+)", isOn: $store.includeAdult).accessibilityIdentifier("settings-adult-content")
            } header: { Text("AniList & video sources") } footer: {
                Text("Applies to anime browsing, libraries, schedules and known adult video providers. Hidden entries stay in your online lists.")
            }
            MangaBakaRatingSection(filter: $store.mangaBakaContent)
            Section {
                NavigationLink("More MangaBaka content options") { MangaBakaContentSettingsView() }
            }
        }.navigationTitle("Browsing & content").navigationBarTitleDisplayMode(.inline)
    }
}

private struct TrackingSettingsView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Form {
            Section {
                Picker("Airing catch-up comparison", selection: $store.airingProgressSource) {
                    ForEach(AiringProgressSource.allCases) { Text($0.label).tag($0) }
                }.accessibilityIdentifier("settings-airing-progress-source")
            } header: { Text("Catch-up status") } footer: {
                Text("Green means caught up; yellow means behind. Only ongoing airings show this status. English dub compares reported dub releases, not original broadcasts.")
            }
            Section {
                Toggle("Complete at the final episode", isOn: $store.automaticallyComplete).accessibilityIdentifier("settings-auto-complete")
            } header: { Text("Automatic completion") } footer: {
                Text("Marking the final known episode watched moves the title to Completed. Finishing a rewatch also increases its count. You can undo the last saved change.")
            }
        }.navigationTitle("Watch tracking").navigationBarTitleDisplayMode(.inline)
    }
}

struct PlayerSettingsView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("External player", value: "VidHub")
                Text("Videos open in VidHub. Supported versions return your playback position so you can resume here.").font(.subheadline).foregroundStyle(.secondary)
                Link("VidHub integration help", destination: URL(string: "https://vidhub.okaapps.com/3rd-party-app-integration/")!)
            }
            Section("Tracking & privacy") {
                Text("Native anime playback saves resume on this device; catalog/exact-ID playback does not. Playing never marks an episode watched on AniList.")
                Text("Playing a TorBox file shares its private playback address with VidHub. Never share that address with anyone else.")
            }.font(.subheadline).foregroundStyle(.secondary)
        }.navigationTitle("Video player").navigationBarTitleDisplayMode(.inline)
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section("Anime Companion") {
                Text("Anime discovery, manga & novels · AniList & MangaBaka tracking")
                Text("Broadcast times and dub dates may change. Times use your device timezone. Japanese broadcasts do not guarantee local subtitle availability.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Metadata & lists") {
                Link("AniList", destination: URL(string: "https://anilist.co")!)
                MangaBakaAttribution()
                Link("MangaBaka data license · CC BY-NC-SA 4.0", destination: URL(string: "https://creativecommons.org/licenses/by-nc-sa/4.0/")!)
            }
            Section("English dub data") {
                Link("AniSchedule by RockinChaos", destination: DubProvider.current.repositoryURL)
                Link("Fallback · AniSchedule by Bas1874", destination: DubProvider.legacy.repositoryURL)
                Link("Data © MyDubList · CC BY 4.0", destination: URL(string: "https://mydublist.com")!)
                Link("MyDubList dataset license", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                Text("Data is matched by IDs and formatted for display; no source records are edited.").font(.caption).foregroundStyle(.secondary)
                Link("Report inaccurate dub data", destination: URL(string: "https://github.com/Joelis57/MyDubList/issues/new/choose")!)
            }
            Section("Artwork galleries") {
                Text("LiveChart visual galleries, MyAnimeList pictures through Jikan, and AniList artwork. Image copyrights belong to their respective owners.").font(.caption)
                Link("LiveChart.me", destination: URL(string: "https://www.livechart.me")!)
                Link("Jikan · MyAnimeList pictures", destination: URL(string: "https://jikan.moe")!)
                Link("AnimeAPI · ID mapping data", destination: URL(string: "https://github.com/nattadasu/animeApi")!)
                Text("Contains information from AnimeAPI, available under ODbL 1.0 and DbCL 1.0. The source mapping data is not modified.").font(.caption).foregroundStyle(.secondary)
                Link("Mapping database license · ODbL 1.0", destination: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!)
                Link("Mapping contents license · DbCL 1.0", destination: URL(string: "https://opendatacommons.org/licenses/dbcl/1-0/")!)
                NavigationLink("Artwork software credits") {
                    ScrollView {
                        Text((Bundle.main.url(forResource: "VisualGalleryLicenses", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? "License notices are unavailable in this build.")
                            .font(.caption.monospaced()).textSelection(.enabled).padding()
                    }.navigationTitle("Artwork credits").navigationBarTitleDisplayMode(.inline)
                }
            }
            Section("News") {
                Link("Anime News Network", destination: URL(string: "https://www.animenewsnetwork.com")!)
                Link("Crunchyroll", destination: URL(string: "https://www.crunchyroll.com/news")!)
                Link("Anime Corner", destination: URL(string: "https://animecorner.me")!)
                Link("LiveChart.me headlines", destination: NewsSource.liveChart.feedURL)
            }
            Section("Manga extensions") {
                Link("Keiyoushi repository", destination: URL(string: "https://keiyoushi.github.io")!)
                Link("On-device interpreter · dexvm", destination: URL(string: "https://github.com/tachibana-shin/dexvm")!)
                NavigationLink("Runtime licenses") {
                    ScrollView {
                        Text((Bundle.main.url(forResource: "MangaRuntimeLicenses", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? "License notices are unavailable in this build.")
                            .font(.caption.monospaced()).textSelection(.enabled).padding()
                    }.navigationTitle("Runtime licenses").navigationBarTitleDisplayMode(.inline)
                }
            }
        }.navigationTitle("About & data sources").navigationBarTitleDisplayMode(.inline)
    }
}
