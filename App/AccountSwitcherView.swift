import SwiftUI
import AnimeCore

/// The picker only changes the foreground library. Both stores keep their own
/// sessions, in-flight saves and cached progress throughout a switch.
struct AccountSwitcherButton: View {
    @EnvironmentObject private var anime: AppStore
    @EnvironmentObject private var reading: MangaBakaStore
    @EnvironmentObject private var navigation: AppNavigationStore
    @AppStorage(TrackingAccount.storageKey) private var saved = ""
    @AppStorage("library.mediaSection") private var librarySection = "all"
    @State private var presented = false
    @State private var selected: TrackingAccount?
    private var active: TrackingAccount? {
        TrackingAccount.preferred(saved: saved, librarySection: librarySection,
            connected: Set(TrackingAccount.allCases.filter { $0 == .aniList ? anime.isSignedIn : reading.connected }))
    }
    var body: some View {
        Button { presented = true } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "person.crop.circle").font(.title2)
                    .frame(width: 44, height: 44).silverGlass(in: Circle())
                if let active {
                    Text(active == .aniList ? "A" : "M").font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white).frame(width: 17, height: 17)
                        .background(active == .aniList ? Color.blue : Color.teal, in: Circle())
                        .accessibilityHidden(true)
                }
            }
        }.buttonStyle(.plain).accessibilityLabel("Switch account")
            .accessibilityValue(active.map { $0.title + " · " + name($0) } ?? "No account connected")
            .accessibilityIdentifier("account-switcher")
            .sheet(isPresented: $presented, onDismiss: {
                navigation.applyLayoutPreference(); navigation.applyTabPreferences()
                if let selected { self.selected = nil; navigation.openAccountLibrary(selected) }
            }) {
                AccountSwitcherSheet { account in selected = account; presented = false }
            }
    }
    private func name(_ account: TrackingAccount) -> String {
        account == .aniList ? anime.viewer?.name ?? "Connected" : reading.profile?.name ?? "Connected"
    }
}

private struct AccountSwitcherSheet: View {
    @Environment(\.dismiss) private var dismiss
    let select: (TrackingAccount) -> Void
    var body: some View {
        NavigationStack {
            AccountSwitcherView(close: { dismiss() }, select: select)
        }
    }
}

struct AccountSwitcherView: View {
    @EnvironmentObject private var anime: AppStore
    @EnvironmentObject private var reading: MangaBakaStore
    @AppStorage(TrackingAccount.storageKey) private var saved = ""
    @AppStorage("library.mediaSection") private var librarySection = "all"
    var showsSettings = true
    let close: () -> Void
    let select: (TrackingAccount) -> Void
    private var active: TrackingAccount? {
        TrackingAccount.preferred(saved: saved, librarySection: librarySection,
            connected: Set(TrackingAccount.allCases.filter(connected)))
    }
    var body: some View {
        Form {
            Section {
                ForEach(TrackingAccount.allCases) { account in
                    if connected(account) {
                        Button { select(account) } label: { accountLabel(account) }
                            .buttonStyle(.plain).accessibilityLabel("Switch to " + account.title)
                            .accessibilityValue(name(account) + (active == account ? " · Active" : " · Signed in"))
                            .accessibilityIdentifier("account-switch-" + account.rawValue)
                    } else {
                        NavigationLink { connection(account) } label: { accountLabel(account) }
                            .accessibilityLabel("Sign in to " + account.title)
                            .accessibilityIdentifier("account-signin-" + account.rawValue)
                    }
                }
            } header: { Text("Your accounts") } footer: {
                Text("Both accounts stay signed in. Tap an account to open its library. Each service keeps its own progress.")
            }
            Section("Manage accounts") {
                ForEach(TrackingAccount.allCases) { account in
                    NavigationLink { connection(account) } label: {
                        Label(account.title + " account", systemImage: account == .aniList ? "play.rectangle" : "books.vertical")
                    }.accessibilityIdentifier("account-manage-" + account.rawValue)
                }
            }
            if showsSettings {
                Section {
                    NavigationLink { SettingsDirectoryView(close: close, selectAccount: select) } label: {
                        Label("App settings", systemImage: "gearshape")
                    }.accessibilityIdentifier("account-app-settings")
                }
            }
        }.navigationTitle("Accounts").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
    }
    private func connected(_ account: TrackingAccount) -> Bool { account == .aniList ? anime.isSignedIn : reading.connected }
    private func name(_ account: TrackingAccount) -> String {
        account == .aniList ? anime.viewer?.name ?? "Connected to AniList" : reading.profile?.name ?? "Connected to MangaBaka"
    }
    private func accountLabel(_ account: TrackingAccount) -> some View {
        HStack(spacing: 12) {
            Image(systemName: account == .aniList ? "play.rectangle.fill" : "books.vertical.fill")
                .font(.title3).foregroundStyle(.white).frame(width: 44, height: 44)
                .background(account == .aniList ? Color.blue.gradient : Color.teal.gradient, in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(account.title).font(.headline)
                Text(connected(account) ? name(account) : "Sign in")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(account == .aniList ? "Anime library" : "Manga & novels library")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if connected(account) {
                Image(systemName: active == account ? "checkmark.circle.fill" : "arrow.right.circle")
                    .foregroundStyle(active == account ? Color.mint : Color.secondary).accessibilityHidden(true)
            }
        }.padding(.vertical, 8).contentShape(Rectangle())
    }
    @ViewBuilder private func connection(_ account: TrackingAccount) -> some View {
        Group {
            if account == .aniList { AniListSettingsView() }
            else { MangaBakaAccountView() }
        }.safeAreaInset(edge: .bottom) {
            if connected(account) {
                Button("Use " + account.title + " account") { select(account) }
                    .buttonStyle(.borderedProminent).padding().frame(maxWidth: .infinity)
                    .background(.regularMaterial).accessibilityIdentifier("account-use-" + account.rawValue)
            }
        }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
    }
}
