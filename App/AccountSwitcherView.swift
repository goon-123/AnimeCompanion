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
                // The navigation bar supplies its own button surface on iOS 26.
                // A second framed circle here produced the overlapping rings.
                Image(systemName: "person.crop.circle.fill").font(.system(size: 28))
                    .foregroundStyle(.primary).frame(width: 44, height: 44)
                if let active {
                    Text(active == .aniList ? "A" : "M").font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white).frame(width: 14, height: 14)
                        .background(active == .aniList ? Color.blue : Color.teal, in: Circle())
                        .overlay { Circle().stroke(Theme.surface, lineWidth: 1.5) }
                        .padding(.trailing, 4).padding(.bottom, 4)
                        .accessibilityHidden(true)
                }
            }.frame(width: 44, height: 44).contentShape(Rectangle())
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
        AppNavigationStack {
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
                ForEach(TrackingAccount.allCases.filter { $0 != .mangaBaka || reading.savedAccounts.count <= 1 }) { account in
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
                Text("Saved accounts stay signed in. Tap an account to open its library. Each service keeps its own progress.")
            }
            if reading.savedAccounts.count > 1 {
                Section("MangaBaka accounts") {
                    ForEach(reading.savedAccounts) { account in
                        Button {
                            reading.selectAccount(account.id)
                            if reading.activeAccountID == account.id { select(.mangaBaka) }
                        } label: {
                            HStack {
                                Label(account.name, systemImage: "person.crop.circle").foregroundStyle(.primary)
                                Spacer()
                                if reading.activeAccountID == account.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint) }
                            }
                        }.buttonStyle(.plain).disabled(reading.connecting || !reading.saving.isEmpty)
                            .accessibilityIdentifier("account-switch-mangabaka-" + (account.profile?.id ?? account.id.uuidString))
                    }
                }
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
            if account == .aniList { AniListSettingsView(useAccount: { select(.aniList) }) }
            else { MangaBakaAccountView(useAccount: { select(.mangaBaka) }) }
        }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } }
    }
}
