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
            defaults.removeObject(forKey: SetupStage.storageKey)
            defaults.set(false, forKey: "content.includeAdult")
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

struct FirstRunSetupView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var mangaBaka: MangaBakaStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    let revisiting: Bool
    let onFinish: () -> Void
    @State private var stage: SetupStage
    private var busy: Bool { store.connecting || mangaBaka.connecting }

    init(revisiting: Bool = false, onFinish: @escaping () -> Void) {
        self.revisiting = revisiting; self.onFinish = onFinish
        let defaults = UserDefaults.standard
        _stage = State(initialValue: revisiting ? .welcome : SetupStage.restoring(
            savedStep: defaults.object(forKey: SetupStage.storageKey) as? Int,
            legacyStep: defaults.integer(forKey: FirstRunSetupState.stepKey)))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    progress
                    VStack(alignment: .leading, spacing: 10) {
                        Text(stage.title).font(.largeTitle.bold()).tracking(-0.8)
                        Text(stage.subtitle).font(.body).foregroundStyle(.secondary)
                    }.fixedSize(horizontal: false, vertical: true)
                    pageContent
                }.padding(24).frame(maxWidth: 660, alignment: .leading).frame(maxWidth: .infinity)
            }.background(Theme.background.ignoresSafeArea()).scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) { footer }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if stage != .welcome { Button("Back", systemImage: "chevron.left") { move(-1) }.disabled(busy) }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if stage != .ready { Button("Set up later", action: finish).disabled(busy).accessibilityIdentifier("setup-skip-all") }
                    }
                }
        }.interactiveDismissDisabled(!revisiting)
    }
    private var progress: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ANIME COMPANION").font(.caption.bold()).tracking(2).foregroundStyle(Theme.accent)
                Spacer()
                Text("\(stage.rawValue + 1) of \(SetupStage.allCases.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(SetupStage.allCases, id: \.rawValue) { item in
                    Capsule().fill(item.rawValue <= stage.rawValue ? Theme.accent : Theme.secondarySurface).frame(height: 3)
                }
            }.accessibilityLabel("Setup step \(stage.rawValue + 1) of \(SetupStage.allCases.count)")
        }
    }
    @ViewBuilder private var pageContent: some View {
        switch stage {
        case .welcome:
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "sparkles.rectangle.stack.fill").font(.system(size: 72, weight: .light))
                    .foregroundStyle(Theme.accent).padding(.vertical, 16).accessibilityHidden(true)
                feature("Find your next favorite", detail: "Anime, manga and novels in one place.", symbol: "sparkles")
                feature("Keep your place", detail: "Connect your own libraries and continue reading.", symbol: "bookmark.fill")
                feature("Start with what you need", detail: "Browse right away. Add sources and playback later.", symbol: "slider.horizontal.3")
                Label("No account is required to explore.", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
            }
        case .libraries:
            VStack(alignment: .leading, spacing: 20) {
                aniListCard
                VStack(alignment: .leading, spacing: 16) {
                    connectionHeading("MangaBaka", symbol: "books.vertical", connected: mangaBaka.connected)
                    if mangaBaka.connected {
                        Text(mangaBaka.profile?.name ?? "Your reading library is connected.")
                            .font(.subheadline).foregroundStyle(.secondary).privacySensitive()
                        NavigationLink("Manage saved accounts") { MangaBakaAccountView() }
                    } else { MangaBakaKeyEntry() }
                }.companionPanel(padding: 18).accessibilityIdentifier("setup-mangabaka-connect")
                Text("Each person connects their own account. Keys are entered here and stored in this device’s Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .preferences:
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Appearance", systemImage: "circle.lefthalf.filled").font(.headline)
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { value in Text(value.label).tag(value.rawValue) }
                    }.pickerStyle(.segmented)
                }.companionPanel(padding: 18)
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Show adult titles (18+)", isOn: $store.includeAdult)
                        .accessibilityIdentifier("setup-explicit-content")
                    Text("Off by default. Your online lists are kept; this controls what appears while browsing.")
                        .font(.caption).foregroundStyle(.secondary)
                }.companionPanel(padding: 18)
                VStack(alignment: .leading, spacing: 12) {
                    Label("Playback", systemImage: "play.rectangle").font(.headline)
                    VideoPlayerSelection()
                }.companionPanel(padding: 18).accessibilityIdentifier("setup-video-player")
                feature("Your layout, your choice", detail: "Hide, add and rearrange Home and Explore widgets whenever you like.", symbol: "rectangle.3.group")
            }
        case .ready:
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    connectionHeading("AniList", symbol: "play.rectangle", connected: store.isSignedIn)
                    connectionHeading("MangaBaka", symbol: "books.vertical", connected: mangaBaka.connected)
                }.companionPanel(padding: 18).accessibilityIdentifier("setup-summary")
                NavigationLink { SourcesSettingsView() } label: {
                    feature("Reading & playback", detail: "Optional: add reading sources, TorBox or streaming add-ons.", symbol: "play.rectangle.on.rectangle")
                        .padding(18).background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).accessibilityIdentifier("setup-optional-playback")
                Label("Everything here can be changed later in Settings.", systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var aniListCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            connectionHeading("AniList", symbol: "play.rectangle", connected: store.isSignedIn)
            if store.isSignedIn {
                Text(store.viewer?.name ?? "Your anime library is connected.").font(.subheadline).foregroundStyle(.secondary).privacySensitive()
            } else if AppConfiguration.clientID != nil {
                Text("Sync your watchlist, ratings and episode progress.").font(.subheadline).foregroundStyle(.secondary)
                Button("Connect AniList") { Task { await store.connect() } }
                    .buttonStyle(.borderedProminent).disabled(store.connecting).accessibilityIdentifier("setup-anilist-connect")
                if store.connecting { ProgressView("Opening AniList…") }
                if let error = store.accountError { Text(error).font(.caption).foregroundStyle(.orange) }
            } else {
                Text("Anime browsing works right away. AniList syncing can be configured in Settings.")
                    .font(.subheadline).foregroundStyle(.secondary)
                NavigationLink("AniList connection settings") { AniListSettingsView() }
                    .accessibilityIdentifier("setup-anilist-connect")
            }
        }.companionPanel(padding: 18)
    }
    private func feature(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent).frame(width: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.foregroundStyle(.primary)
    }
    private func connectionHeading(_ name: String, symbol: String, connected: Bool) -> some View {
        HStack(spacing: 10) {
            Label(name, systemImage: symbol).font(.headline)
            Spacer()
            Text(connected ? "Connected" : "Optional").font(.caption.weight(.semibold)).foregroundStyle(connected ? Color.mint : .secondary)
        }
    }
    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                if stage == .ready { finish() } else { move(1) }
            } label: {
                Text(stage == .ready ? "Start exploring" : stage == .welcome ? "Get started" : "Continue")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
            }
                .buttonStyle(.borderedProminent).disabled(busy)
                .accessibilityIdentifier(stage == .ready ? "setup-start-exploring" : "setup-continue")
            if stage == .libraries { Text("You can continue without connecting an account.").font(.caption2).foregroundStyle(.secondary) }
        }.padding(.horizontal, 24).padding(.vertical, 12).frame(maxWidth: 660).frame(maxWidth: .infinity)
            .background(Theme.background)
    }
    private func move(_ direction: Int) {
        guard let next = SetupStage(rawValue: stage.rawValue + direction), !busy else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { stage = next }
        if !revisiting { UserDefaults.standard.set(next.rawValue, forKey: SetupStage.storageKey) }
    }
    private func finish() {
        guard !busy else { return }
        if !revisiting { UserDefaults.standard.set(SetupStage.ready.rawValue, forKey: SetupStage.storageKey) }
        onFinish()
    }
}
