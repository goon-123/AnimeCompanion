import SwiftUI
import AnimeCore

/// A compact directory. Credentials, provider management and long explanations
/// live on their own screens instead of competing with everyday preferences.
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var seanime: SeanimeStore
    @EnvironmentObject private var mangaBaka: MangaBakaStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { AniListSettingsView() } label: {
                        SettingsCategoryLabel(title: "AniList account", detail: store.isSignedIn ? store.viewer.map { "Signed in as \($0.name)" } ?? "Connected" : "Connect to sync your library", symbol: "person.crop.circle.fill", tint: .blue)
                    }.accessibilityIdentifier("settings-account")
                    NavigationLink { MangaBakaAccountView() } label: {
                        SettingsCategoryLabel(title: "MangaBaka account", detail: mangaBaka.connected ? mangaBaka.profile?.name ?? "Connected" : "Manga & novels · Library sync", symbol: "books.vertical.fill", tint: .teal)
                    }.accessibilityIdentifier("settings-mangabaka-account")
                }
                Section("Playback & sources") {
                    NavigationLink { TorBoxSettingsView() } label: {
                        SettingsCategoryLabel(title: "TorBox", detail: seanime.hasTorBoxKey ? "Key saved · Cloud files & connection" : "Connect your account · Cloud files", symbol: "cloud.fill", tint: .mint)
                    }.accessibilityIdentifier("settings-torbox")
                    NavigationLink { PlaybackSettingsView() } label: {
                        SettingsCategoryLabel(title: "Stremio add-ons", detail: "\(playback.installations.count) installed · Manifests & catalogs", symbol: "puzzlepiece.extension.fill", tint: .purple)
                    }.accessibilityIdentifier("playback-settings")
                    NavigationLink { SeanimeSettingsView() } label: {
                        SettingsCategoryLabel(title: "Seanime extensions", detail: "\(seanime.installations.count) installed · Torrent providers", symbol: "shippingbox.fill", tint: .orange)
                    }.accessibilityIdentifier("seanime-settings")
                    NavigationLink { PlayerSettingsView() } label: {
                        SettingsCategoryLabel(title: "Video player", detail: "VidHub · Playback & resume", symbol: "play.rectangle.fill", tint: .pink)
                    }.accessibilityIdentifier("settings-player")
                    NavigationLink { SafariVideoSettingsView() } label: {
                        SettingsCategoryLabel(title: "Safari → VidHub", detail: "Open website videos in your player", symbol: "safari.fill", tint: .cyan)
                    }.accessibilityIdentifier("settings-safari-vidhub")
                }
                Section("Reading") {
                    NavigationLink { MangaExtensionsView() } label: {
                        SettingsCategoryLabel(title: "Manga extensions", detail: "Keiyoushi · Manga & manhwa sources", symbol: "book.closed.fill", tint: .teal)
                    }.accessibilityIdentifier("settings-manga-extensions")
                }
                Section("Preferences") {
                    NavigationLink { ExploreDesignSettingsView() } label: {
                        SettingsCategoryLabel(title: "Explore design", detail: "Combined shelves, mixed grid or Classic", symbol: "rectangle.stack.fill", tint: .mint)
                    }.accessibilityIdentifier("settings-explore-design")
                    NavigationLink { TabCustomizationView() } label: {
                        SettingsCategoryLabel(title: "Bottom tabs", detail: "Reorder or hide sections", symbol: "rectangle.bottomthird.inset.filled", tint: .cyan)
                    }.accessibilityIdentifier("settings-bottom-tabs")
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        NavigationLink { TabletLayoutSettingsView() } label: {
                            SettingsCategoryLabel(title: "iPad layout", detail: "Full-width pages or side-by-side browsing", symbol: "rectangle.split.2x1", tint: .cyan)
                        }.accessibilityIdentifier("settings-ipad-layout")
                    }
                    NavigationLink { BrowsingSettingsView() } label: {
                        SettingsCategoryLabel(title: "Browsing & content", detail: "Metadata source & adult content", symbol: "square.grid.2x2.fill", tint: .indigo)
                    }.accessibilityIdentifier("settings-browsing")
                    NavigationLink { TrackingSettingsView() } label: {
                        SettingsCategoryLabel(title: "Watch tracking", detail: "Catch-up status & completion", symbol: "checkmark.circle.fill", tint: .green)
                    }.accessibilityIdentifier("settings-tracking")
                }
                Section {
                    NavigationLink { AboutSettingsView() } label: { Label("About & data sources", systemImage: "info.circle") }
                        .accessibilityIdentifier("settings-about")
                } footer: {
                    Text("Anime Companion \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")")
                        .frame(maxWidth: .infinity).padding(.top, 8)
                }
            }.navigationTitle("Settings")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct AppSettingsSheet: ViewModifier {
    @EnvironmentObject private var navigation: AppNavigationStore
    @Binding var isPresented: Bool
    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: { navigation.applyLayoutPreference(); navigation.applyTabPreferences() }) { SettingsView() }
    }
}

extension View {
    func appSettingsSheet(isPresented: Binding<Bool>) -> some View {
        modifier(AppSettingsSheet(isPresented: isPresented))
    }
}

private struct TabletLayoutSettingsView: View {
    @AppStorage(TabletLayout.preferenceKey) private var layoutValue = TabletLayout.fullWidth.rawValue
    var body: some View {
        Form {
            Section {
                Toggle("Side-by-side browsing", isOn: Binding(get: {
                    TabletLayout(preference: layoutValue) == .sideBySide
                }, set: { layoutValue = ($0 ? TabletLayout.sideBySide : .fullWidth).rawValue }))
                    .accessibilityIdentifier("settings-ipad-split-view")
            } header: { Text("iPad layout") } footer: {
                Text("Off: browse full-width pages and open titles like on iPhone. On: keep browsing beside anime details. Compact windows use one column. News always uses the full page. Your choice is saved and applies when you close Settings.")
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
            Image(systemName: symbol).font(.body.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(tint.gradient, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 3)
        }
    }
}

private struct AniListSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var clientID = AppConfiguration.clientID ?? ""
    @State private var confirmation = false
    var body: some View {
        Form {
            Section("Connection") {
                if store.isSignedIn {
                    Label(store.viewer.map { "Signed in as \($0.name)" } ?? "Connected to AniList", systemImage: "checkmark.circle.fill").foregroundStyle(.mint)
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
            } header: { Text("Content") } footer: {
                Text("Applies to anime and MangaBaka browsing, search, libraries, schedules and known adult providers. Hidden entries stay in your online lists. External websites use their own filters.")
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
