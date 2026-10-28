import SwiftUI
import AnimeCore

/// A version-independent first-launch marker. It is evaluated before any store
/// initializes so defaults written by AppStore on a brand-new install do not
/// accidentally classify that install as an existing one.
@MainActor
final class FirstRunSetupState: ObservableObject {
    static let lifecycleKey = "setup.lifecycle"
    static let stepKey = "setup.wizard.step"
    static let resultsKey = "setup.wizard.results"

    @Published private(set) var showOnLaunch: Bool

    init(showOnLaunch: Bool) { self.showOnLaunch = showOnLaunch }

    static func prepare(defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        #if DEBUG
        if arguments.contains("--ui-onboarding-preview") {
            defaults.set("inProgress", forKey: lifecycleKey)
            defaults.set(0, forKey: stepKey)
            defaults.removeObject(forKey: resultsKey)
            return true
        }
        // Keep existing UI snapshots and interaction tests at their normal entry point.
        if arguments.contains(where: { $0.hasPrefix("--ui-") }) { return false }
        #endif

        if let saved = defaults.string(forKey: lifecycleKey) {
            return saved == "inProgress"
        }

        // This release introduces the marker. Earlier builds already persisted
        // the immersive Explore preference when they first launched. Check it
        // (and other legacy keys) BEFORE AppStore's initializer can set it.
        let legacyKeys = [
            "explore.poster.immersive-v2",
            "app.mediaSection", "library.mediaSection",
            "content.includeAdult", "tracking.automaticallyComplete",
            "playback.enabled", "playback.audioFilter",
            "schedule.airing.layout", "library.layout",
            "torbox.files.sort"
        ]
        let existingInstallation = legacyKeys.contains { defaults.object(forKey: $0) != nil }
        defaults.set(existingInstallation ? "finished" : "inProgress", forKey: lifecycleKey)
        return !existingInstallation
    }

    func finish() {
        UserDefaults.standard.set("finished", forKey: Self.lifecycleKey)
        showOnLaunch = false
    }
}

private enum SetupPage: Int, CaseIterable {
    case welcome, aniList, mangaBaka, torrent, torBox, aioStreams, content, finish

    var title: String {
        switch self {
        case .welcome: return "Everything you love, together."
        case .aniList: return "Bring your anime library."
        case .mangaBaka: return "Pick up where you left off."
        case .torrent: return "Discover anime sources."
        case .torBox: return "Connect your cloud playback."
        case .aioStreams: return "Make stream discovery easier."
        case .content: return "Make it your space."
        case .finish: return "You're ready to explore."
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: return "Track anime, discover manga and novels, and find playback options in one place. Choose only the features you want."
        case .aniList: return "Connect AniList to sync your watchlist, ratings and episode progress across devices."
        case .mangaBaka: return "Connect MangaBaka for your manga and novel lists, reading progress, and personalized recommendations."
        case .torrent: return "Seanime extensions search anime torrent providers. Browse community extensions, review their permissions and install the ones you trust."
        case .torBox: return "TorBox can resolve supported torrents into cloud-backed playback links and lets you browse cloud files. You can add your API key securely."
        case .aioStreams: return "AIOStreams combines compatible streaming add-ons into one customizable source. Set up a new configuration or reconnect an existing one."
        case .content: return "Choose whether adult titles appear in search, browsing and your libraries. The safer option is selected by default."
        case .finish: return "Here's your setup at a glance. Anything you skipped can be configured later in Settings."
        }
    }

    var icon: String {
        switch self {
        case .welcome: return "sparkles"
        case .aniList: return "play.rectangle.on.rectangle"
        case .mangaBaka: return "books.vertical.fill"
        case .torrent: return "puzzlepiece.extension.fill"
        case .torBox: return "cloud.fill"
        case .aioStreams: return "square.stack.3d.up.fill"
        case .content: return "hand.raised.fill"
        case .finish: return "checkmark.seal.fill"
        }
    }

    var tint: Color {
        switch self {
        case .welcome: return .purple
        case .aniList: return .blue
        case .mangaBaka: return .teal
        case .torrent: return .orange
        case .torBox: return .mint
        case .aioStreams: return .indigo
        case .content: return .cyan
        case .finish: return .green
        }
    }

    var summaryLabel: String {
        switch self {
        case .aniList: return "AniList"
        case .mangaBaka: return "MangaBaka"
        case .torrent: return "Torrent extensions"
        case .torBox: return "TorBox"
        case .aioStreams: return "AIOStreams"
        case .content: return "Content preferences"
        case .welcome, .finish: return ""
        }
    }

    var key: String { String(rawValue) }
}

struct FirstRunSetupView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var mangaBaka: MangaBakaStore
    @EnvironmentObject private var seanime: SeanimeStore
    @EnvironmentObject private var playback: PlaybackStore

    let revisiting: Bool
    let onFinish: () -> Void
    @State private var index: Int
    @State private var confirmSkip = false

    init(revisiting: Bool = false, onFinish: @escaping () -> Void) {
        self.revisiting = revisiting
        self.onFinish = onFinish
        let saved = UserDefaults.standard.integer(forKey: FirstRunSetupState.stepKey)
        _index = State(initialValue: revisiting ? 0 : min(max(saved, 0), SetupPage.allCases.count - 1))
    }

    private var page: SetupPage { SetupPage(rawValue: index) ?? .welcome }

    private var results: [String: String] {
        UserDefaults.standard.dictionary(forKey: FirstRunSetupState.resultsKey) as? [String: String] ?? [:]
    }

    private func detected(_ page: SetupPage) -> Bool {
        switch page {
        case .aniList: return store.isSignedIn
        case .mangaBaka: return mangaBaka.connected
        case .torrent: return !seanime.installations.isEmpty
        case .torBox: return seanime.hasTorBoxKey
        case .aioStreams:
            return playback.installations.contains { installation in
                installation.addon.manifest.name.localizedCaseInsensitiveContains("aiostreams") ||
                installation.addon.endpoint.displayHost.localizedCaseInsensitiveContains("aiostreams")
            }
        case .content: return results[page.key] == "completed"
        case .welcome, .finish: return false
        }
    }

    private func status(_ page: SetupPage) -> (label: String, color: Color, icon: String) {
        if detected(page) {
            return (page == .content ? "Saved" : page == .torrent ? "Installed" : "Connected", .mint, "checkmark.circle.fill")
        }
        if results[page.key] == "skipped" { return ("Skipped", .secondary, "minus.circle") }
        return ("Not set up", .secondary, "circle.dotted")
    }

    private func record(_ page: SetupPage, skipped: Bool) {
        guard page != .welcome && page != .finish else { return }
        var updated = results
        updated[page.key] = skipped ? "skipped" : (page == .content || detected(page) ? "completed" : "skipped")
        UserDefaults.standard.set(updated, forKey: FirstRunSetupState.resultsKey)
    }

    private func advance(skipped: Bool = false) {
        record(page, skipped: skipped)
        guard index < SetupPage.allCases.count - 1 else { finish() ; return }
        withAnimation(.easeInOut(duration: 0.2)) { index += 1 }
        if !revisiting { UserDefaults.standard.set(index, forKey: FirstRunSetupState.stepKey) }
    }

    private func back() {
        guard index > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) { index -= 1 }
        if !revisiting { UserDefaults.standard.set(index, forKey: FirstRunSetupState.stepKey) }
    }

    private func finish() {
        if !revisiting {
            var updated = results
            for step in SetupPage.allCases where step != .welcome && step != .finish {
                if updated[step.key] == nil {
                    updated[step.key] = detected(step) ? "completed" : "skipped"
                }
            }
            UserDefaults.standard.set(updated, forKey: FirstRunSetupState.resultsKey)
            UserDefaults.standard.set(SetupPage.finish.rawValue, forKey: FirstRunSetupState.stepKey)
        }
        onFinish()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                RadialGradient(colors: [page.tint.opacity(0.22), .clear],
                               center: .topTrailing, startRadius: 8, endRadius: 460)
                    .ignoresSafeArea().allowsHitTesting(false)
                VStack(spacing: 0) {
                    progressHeader
                    ScrollView {
                        VStack(alignment: .leading, spacing: 25) {
                            hero
                            pageBody
                        }
                        .frame(maxWidth: 580, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 28)
                    }
                    footer
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Skip the rest of setup?", isPresented: $confirmSkip, titleVisibility: .visible) {
                Button("Start exploring without setup") { finish() }
                Button("Keep setting up", role: .cancel) {}
            } message: {
                Text("No accounts or extensions are required. You can return to the Setup Guide from Settings.")
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("first-run-setup")
    }

    private var progressHeader: some View {
        VStack(spacing: 13) {
            HStack {
                if index > 0 {
                    Button(action: back) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.subheadline.weight(.medium))
                    }.accessibilityIdentifier("setup-back")
                } else {
                    Text("ANIME COMPANION").font(.caption.weight(.bold)).tracking(2)
                }
                Spacer()
                Text("\(index + 1) / \(SetupPage.allCases.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if revisiting {
                    Button("Close", action: onFinish)
                        .font(.subheadline.weight(.semibold)).padding(.leading, 14)
                        .accessibilityIdentifier("setup-close")
                } else {
                    Button("Skip setup") { confirmSkip = true }
                        .font(.subheadline.weight(.semibold)).padding(.leading, 14)
                        .accessibilityIdentifier("setup-skip-all")
                }
            }
            HStack(spacing: 5) {
                ForEach(SetupPage.allCases, id: \.rawValue) { item in
                    Capsule().fill(item.rawValue <= index ? page.tint : Color.white.opacity(0.16))
                        .frame(height: 4)
                }
            }.accessibilityLabel("Setup step \(index + 1) of \(SetupPage.allCases.count)")
        }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)
            .frame(maxWidth: 650)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 27)
                    .fill(page.tint.opacity(0.16))
                    .frame(width: 100, height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 27).stroke(.white.opacity(0.14)))
                Image(systemName: page.icon)
                    .font(.system(size: 43, weight: .medium))
                    .foregroundStyle(page.tint.gradient)
            }
            Text(page == .welcome ? "WELCOME" : page == .finish ? "ALL SET" : "PERSONALIZE YOUR EXPERIENCE")
                .font(.caption.bold()).tracking(2).foregroundStyle(page.tint)
            Text(page.title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
            Text(page.subtitle)
                .font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .id(page)
    }

    @ViewBuilder private var pageBody: some View {
        switch page {
        case .welcome:
            VStack(spacing: 12) {
                feature("One combined library", symbol: "rectangle.stack.fill", detail: "Anime, manga and novels in one app")
                feature("Better discovery", symbol: "sparkles", detail: "Explore new titles and personalized picks")
                feature("Your playback choices", symbol: "play.square.stack", detail: "Add providers when you're ready")
            }
        case .aniList:
            connectionBadge(page)
            NavigationLink { AniListSettingsView().toolbar(.visible, for: .navigationBar) } label: {
                actionCard("Connect or manage AniList", detail: "Secure sign-in and library syncing", symbol: "person.crop.circle.badge.checkmark")
            }.accessibilityIdentifier("setup-anilist-connect")
            Text("You can browse anime even without an AniList account.")
                .font(.caption).foregroundStyle(.secondary)
        case .mangaBaka:
            connectionBadge(page)
            NavigationLink { MangaBakaAccountView().toolbar(.visible, for: .navigationBar) } label: {
                actionCard("Connect or manage MangaBaka", detail: "Sign in or connect with an API key", symbol: "books.vertical.fill")
            }.accessibilityIdentifier("setup-mangabaka-connect")
        case .torrent:
            connectionBadge(page)
            NavigationLink { SeanimeSettingsView().toolbar(.visible, for: .navigationBar) } label: {
                actionCard("Browse & install extensions", detail: "Open the marketplace, review and install providers", symbol: "shippingbox.fill")
            }.accessibilityIdentifier("setup-torrent-install")
            Text("Extensions run third-party code. Only install from sources you trust. They can be added or disabled later.")
                .font(.caption).foregroundStyle(.secondary)
        case .torBox:
            connectionBadge(page)
            NavigationLink { TorBoxSettingsView().toolbar(.visible, for: .navigationBar) } label: {
                actionCard("Connect TorBox", detail: "Save and verify your API key", symbol: "key.fill")
            }.accessibilityIdentifier("setup-torbox-connect")
            Text("A TorBox subscription or account is separate from Anime Companion. You can use the app without TorBox.")
                .font(.caption).foregroundStyle(.secondary)
        case .aioStreams:
            connectionBadge(page)
            NavigationLink {
                AddonDirectoryBrowser(startURL: URL(string: "https://aiostreams.elfhosted.com/stremio/configure")!)
                    .toolbar(.visible, for: .navigationBar)
            } label: {
                actionCard("Create or open AIOStreams setup", detail: "Use its configuration site, including existing accounts", symbol: "slider.horizontal.3")
            }.accessibilityIdentifier("setup-aiostreams-configure")
            NavigationLink { PlaybackSettingsView().toolbar(.visible, for: .navigationBar) } label: {
                actionCard("Install an existing manifest", detail: "Paste your private AIOStreams manifest URL", symbol: "link")
            }.accessibilityIdentifier("setup-aiostreams-install")
            Text("After configuring AIOStreams, select its manifest install link or paste the URL under Stremio add-ons. It is an optional third-party service.")
                .font(.caption).foregroundStyle(.secondary)
        case .content:
            VStack(alignment: .leading, spacing: 18) {
                Toggle(isOn: $store.includeAdult) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Allow explicit content (18+)").font(.headline)
                        Text(store.includeAdult ? "Adult titles may appear in the app." : "Adult titles are hidden from supported catalogs.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(.cyan)
                .accessibilityIdentifier("setup-explicit-content")
                Divider().overlay(.white.opacity(0.1))
                Label("Off (recommended): filter known adult titles and providers.", systemImage: "checkmark.shield")
                    .font(.subheadline).foregroundStyle(.secondary)
                Label("On: include adult titles when supported by the source.", systemImage: "eye")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Your online lists aren't deleted. External source websites control their own filters. Change this anytime in Settings → Browsing & content.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
        case .finish:
            VStack(alignment: .leading, spacing: 13) {
                ForEach([SetupPage.aniList, .mangaBaka, .torrent, .torBox, .aioStreams, .content], id: \.rawValue) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.icon).frame(width: 26).foregroundStyle(item.tint)
                        Text(item.summaryLabel).font(.subheadline.weight(.medium))
                        Spacer(minLength: 8)
                        let value = status(item)
                        Label(value.label, systemImage: value.icon)
                            .font(.caption).foregroundStyle(value.color)
                    }.padding(.vertical, 9)
                    if item != .content { Divider().opacity(0.25) }
                }
                Text("Manage all connections, add-ons and filters later in Settings → Setup Guide.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }
            .padding(18)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityIdentifier("setup-summary")
        }
    }

    private func feature(_ title: String, symbol: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).frame(width: 34).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }

    private func connectionBadge(_ page: SetupPage) -> some View {
        let value = status(page)
        return Label(value.label, systemImage: value.icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(value.color)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.surface, in: Capsule())
            .accessibilityIdentifier("setup-connection-status")
    }

    private func actionCard(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(page.tint).frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 5)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
        }.padding(18).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                if page == .finish { finish() }
                else { advance() }
            } label: {
                HStack {
                    Spacer()
                    Text(page == .welcome ? "Get Started" : page == .finish ? "Start Exploring" : "Continue")
                    Image(systemName: page == .finish ? "sparkles" : "arrow.right")
                    Spacer()
                }
                .font(.headline).padding(.vertical, 17)
                .background(.white, in: RoundedRectangle(cornerRadius: 17))
                .foregroundStyle(Color.black)
            }
            .accessibilityIdentifier(page == .finish ? "setup-start-exploring" : "setup-continue")
            if page != .welcome && page != .finish {
                Button("Skip for now") { advance(skipped: true) }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("setup-skip-step")
            }
        }
        .frame(maxWidth: 580)
        .padding(.horizontal, 24).padding(.top, 15).padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
}
