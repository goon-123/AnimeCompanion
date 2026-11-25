import SwiftUI
import UIKit
import AnimeCore

@MainActor
final class WebtoonReaderModel: ObservableObject {
    let title: MangaTitleReference
    let chapters: [SourceMangaChapter]
    @Published var chapter: SourceMangaChapter
    @Published var pages: [SourceMangaImage] = []
    @Published var loading = false
    @Published private(set) var advancing = false
    @Published var error: String?
    @Published var controls = true
    @Published var autoScroll = false
    @Published var currentPage = 0
    @Published var jump: WebtoonJump?
    private(set) var initial: MangaReadingPosition?
    private var confirmed: MangaReadingPosition?
    private var reading: MangaReadingStore?
    private var generation = UUID()
    var onCompleted: ((MangaTitleReference, SourceMangaChapter) -> Void)?
    private var completedReports = Set<String>()
    private var saveTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var prefetched: (url: String, pages: [SourceMangaImage])?
    private var startAtBeginning = false
    private var prefetchAttemptedURL: String?
    var chapterIndex: Int { chapters.firstIndex(of: chapter) ?? 0 }
    var hasNext: Bool { chapterIndex + 1 < chapters.count }
    var hasPrevious: Bool { chapterIndex > 0 }
    init(_ route: MangaReaderRoute) { title = route.title; chapters = route.chapters; chapter = route.chapter; startAtBeginning = route.startAtBeginning }
    func load(extensions: MangaExtensionStore, reading: MangaReadingStore) async {
        guard !loading else { return }
        self.reading = reading
        let token = UUID(); generation = token
        loading = true; error = nil
        defer { if generation == token { loading = false } }
        do {
            let list: [SourceMangaImage]
            if let saved = prefetched, saved.url == chapter.url { list = saved.pages; prefetched = nil }
            else { list = try await extensions.pages(title.source, chapter: chapter) }
            try Task.checkCancellation()
            guard generation == token else { return }
            guard !list.isEmpty else { throw WebtoonReaderError.empty }
            guard list.count <= 5000 else { throw MangaExtensionError.oversized }
            let saved = reading.record(title.id)?.position(for: chapter.url)
            initial = !startAtBeginning && saved?.completed == false ? saved?.clamped(to: list.count) : nil
            currentPage = initial?.pageIndex ?? 0; pages = list; startAtBeginning = false
        } catch is CancellationError {} catch { if generation == token { self.error = error.localizedDescription } }
    }
    func position(page: Int, fraction: Double, complete: Bool) {
        guard !pages.isEmpty, pages.indices.contains(page) else { return }
        // Fractional progress stays local to the model. Publishing the same
        // page on every scroll report redraws the entire reader unnecessarily.
        if currentPage != page { currentPage = page }
        let point = MangaReadingPosition(chapterURL: chapter.url, chapterName: chapter.name, pageIndex: page,
            pageCount: pages.count, fraction: fraction, completed: complete)
        confirmed = point
        if complete && completedReports.insert(chapter.url).inserted { onCompleted?(title, chapter) }
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            // Keep disk writes and library publications out of the scroll hot
            // path. Chapter changes, backgrounding and closing still flush.
            do { try await Task.sleep(for: .seconds(2)); try Task.checkCancellation() } catch { return }
            guard let self, let reading = self.reading, let latest = self.confirmed else { return }
            self.saveTask = nil
            await reading.progress(self.title, position: latest)
        }
    }
    func goToPage(_ index: Int) {
        guard !pages.isEmpty else { return }
        autoScroll = false
        currentPage = min(max(0, index), pages.count - 1)
        jump = WebtoonJump(page: currentPage, fraction: 0)
    }
    func flush() async {
        saveTask?.cancel(); saveTask = nil
        if let reading, let confirmed { await reading.progress(title, position: confirmed) }
    }
    func select(_ value: SourceMangaChapter, automatically: Bool = false, keepScrolling: Bool = false, canAdvance: () -> Bool = { true }) async {
        guard value != chapter else { return }
        let token = generation
        await flush()
        guard generation == token, value != chapter else { return }
        if automatically, prefetchAttemptedURL == value.url, let pending = prefetchTask {
            await pending.value
            guard generation == token, value != chapter else { return }
        }
        guard !automatically || canAdvance() else { return }
        prefetchTask?.cancel(); prefetchTask = nil
        if prefetched?.url != value.url { prefetched = nil }
        prefetchAttemptedURL = nil
        startAtBeginning = automatically
        autoScroll = automatically && keepScrolling; controls = !automatically
        pages = []; initial = nil; confirmed = nil; currentPage = 0; jump = nil; error = nil
        generation = UUID(); loading = false; chapter = value
    }
    func prefetchNext(extensions: MangaExtensionStore) {
        guard hasNext, !loading, !pages.isEmpty, currentPage >= max(0, pages.count - 3), prefetchTask == nil else { return }
        let next = chapters[chapterIndex + 1]
        guard prefetched?.url != next.url, prefetchAttemptedURL != next.url else { return }
        prefetchAttemptedURL = next.url
        let token = generation
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == token { prefetchTask = nil } }
            do {
                let values = try await extensions.pages(title.source, chapter: next)
                guard !Task.isCancelled, generation == token, !values.isEmpty, values.count <= 5000 else { return }
                prefetched = (next.url, values)
            } catch { /* The current chapter remains readable; a failed next load offers Retry. */ }
        }
    }
    func cancelPrefetch() { prefetchTask?.cancel(); prefetchTask = nil; prefetched = nil; prefetchAttemptedURL = nil }
    func advanceAutomatically(from chapterURL: String, keepScrolling: Bool, isAllowed: () -> Bool) async {
        guard chapter.url == chapterURL, hasNext, !loading, !advancing else { return }
        advancing = true
        defer { advancing = false }
        await select(chapters[chapterIndex + 1], automatically: true, keepScrolling: keepScrolling, canAdvance: isAllowed)
    }
    func move(_ offset: Int) async {
        let index = chapterIndex + offset
        guard chapters.indices.contains(index) else { return }
        await select(chapters[index])
    }
}

private enum WebtoonReaderError: LocalizedError {
    case empty
    var errorDescription: String? { "This source returned no pages for the chapter. Try refreshing it." }
}

struct WebtoonReaderView: View {
    @EnvironmentObject private var extensions: MangaExtensionStore
    @EnvironmentObject private var reading: MangaReadingStore
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var links: MangaSourceLinkStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scene
    @StateObject private var model: WebtoonReaderModel
    @StateObject private var progressSync = MangaProgressSyncModel()
    @State private var progressSettings = false
    @State private var preferences = WebtoonPreferences()
    @State private var loadedPreferences = false
    @State private var scrubbing = false
    @State private var scrubPage = 0.0
    @State private var settings = false
    @State private var holdScrolling = false
    @State private var chapters = false
    @State private var website = false
    @State private var closing = false
    @State private var pageJump = false
    @State private var pageNumber = ""
    @State private var restarting = false
    @State private var finishingChapter = false
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var originalIdleTimer = false
    @State private var capturedIdleTimer = false
    init(route: MangaReaderRoute) { _model = StateObject(wrappedValue: WebtoonReaderModel(route)) }
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !model.pages.isEmpty { canvas.ignoresSafeArea() }
            else if model.loading { ProgressView("Loading chapter…").foregroundStyle(.white) }
            else if let error = model.error {
                ContentUnavailableView {
                    Label("Chapter unavailable", systemImage: "exclamationmark.circle")
                } description: {
                    VStack(spacing: 8) {
                        Text(model.title.source.name).font(.subheadline.bold())
                            .accessibilityIdentifier("webtoon-error-source")
                        Text(error).accessibilityIdentifier("webtoon-error-description")
                    }
                } actions: {
                    Button("Try again") { Task { await model.load(extensions: extensions, reading: reading) } }.buttonStyle(.bordered)
                    Button("Open source website", systemImage: "globe") { website = true }
                        .accessibilityIdentifier("webtoon-source-website")
                }.foregroundStyle(.white)
            }
            if model.controls || model.pages.isEmpty { chrome.transition(.opacity) }
            if model.advancing {
                VStack { Spacer(); ProgressView("Loading next chapter…").padding(16).readerControlSurface(in: Capsule()).padding(.bottom, 28) }
                    .allowsHitTesting(false)
            }
            if holdScrolling {
                VStack { Spacer(); Label("\(Int(preferences.autoScrollSpeed)) pt/s · Lift to stop", systemImage: "hand.point.up.left.fill")
                    .font(.caption.monospacedDigit().bold()).padding(.horizontal, 16).padding(.vertical, 10)
                    .readerControlSurface(in: Capsule()).padding(.bottom, 24)
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
        }.preferredColorScheme(.dark).tint(MangaStyle.accent).statusBarHidden(!model.controls && !model.pages.isEmpty)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.controls)
            .backSwipe(enabled: !closing && !settings && !chapters && !website && !pageJump && !restarting && !progressSettings) { Task { await close() } }
            .persistentSystemOverlays(model.controls ? .visible : .hidden)
            .task(id: model.chapter.url) {
                await reading.load()
                await links.load()
                let tracker = progressSync, accountStore = account, linkStore = links
                model.onCompleted = { title, chapter in
                    guard UIApplication.shared.applicationState == .active else { return }
                    tracker.completed(title: title, chapter: chapter, account: accountStore, links: linkStore)
                }
                if !loadedPreferences { preferences = reading.state.preferences; loadedPreferences = true }
                await model.load(extensions: extensions, reading: reading)
            }
            .onAppear {
                if !capturedIdleTimer { originalIdleTimer = UIApplication.shared.isIdleTimerDisabled; capturedIdleTimer = true }
                updateAwake()
                Task { await ArtworkPipeline.shared.clearMemory() }
            }
            .onChange(of: preferences.autoLoadNextChapter) { _, enabled in
                if !enabled { model.cancelPrefetch() }
            }
            .onChange(of: preferences.keepAwake) { _, _ in updateAwake() }
            .onChange(of: scene) { _, value in
                if value != .active {
                    model.autoScroll = false; model.cancelPrefetch(); scrubbing = false; UIApplication.shared.isIdleTimerDisabled = originalIdleTimer
                    Task { await model.flush(); await reading.preferences(preferences) }
                } else { updateAwake() }
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = originalIdleTimer
                model.autoScroll = false; model.cancelPrefetch()
                Task { await model.flush(); await reading.preferences(preferences) }
            }
            .onChange(of: settings || chapters || website || pageJump || restarting || progressSettings) { _, presented in
                if presented { model.autoScroll = false; holdScrolling = false; scrubbing = false }
            }
            .alert("Go to page", isPresented: $pageJump) {
                TextField("Page number", text: $pageNumber).keyboardType(.numberPad)
                Button("Go") { if let page = Int(pageNumber) { model.goToPage(page - 1) } }
                    .disabled(Int(pageNumber).map { !(1...max(1, model.pages.count)).contains($0) } ?? true)
                Button("Cancel", role: .cancel) {}
            } message: { Text("Enter a page from 1 to \(model.pages.count).") }
            .confirmationDialog("Read this chapter from the beginning?", isPresented: $restarting, titleVisibility: .visible) {
                Button("Start at page 1") { model.goToPage(0) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Your position in this chapter will resume from page 1.") }
            .sheet(isPresented: $settings, onDismiss: { Task { await reading.preferences(preferences) } }) {
                WebtoonSettingsView(preferences: $preferences, autoScroll: $model.autoScroll)
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $progressSettings) {
                if let activeProgressLink { MangaProgressSettingsView(link: activeProgressLink, chapters: model.chapters).id(MangaProgressPolicy.consentKey(for: activeProgressLink)) }
                else { Text("Link this source to your MangaBaka library to update progress.").padding() }
            }
            .sheet(isPresented: $chapters) { chapterPicker }
            .sheet(isPresented: $website) {
                MangaSourceSessionView(source: model.title.source) {
                    Task { await model.load(extensions: extensions, reading: reading) }
                }
            }
    }
    private var canvas: some View {
        let store = extensions, source = model.title.source, chapterURL = model.chapter.url
        return WebtoonCanvas(source: source, version: extensions.imageVersion(source),
            chapterKey: model.chapter.url, pages: model.pages, initial: model.initial, jump: model.jump,
            preferences: preferences, autoScroll: model.autoScroll,
            scrollingAllowed: readerInteractionAllowed && !scrubbing,
            hasNext: model.hasNext,
            loader: { try await store.imageData(source, image: $0) },
            onPosition: {
                guard model.chapter.url == chapterURL else { return }
                model.position(page: $0, fraction: $1, complete: $2)
                if preferences.autoLoadNextChapter && readerInteractionAllowed { model.prefetchNext(extensions: extensions) }
            },
            onChapterEnd: { chapter, scrolling in
                guard preferences.autoLoadNextChapter, readerInteractionAllowed else { return }
                Task {
                    await model.advanceAutomatically(from: chapter, keepScrolling: scrolling) {
                        preferences.autoLoadNextChapter && readerInteractionAllowed
                    }
                    if scene != .active || closing { model.autoScroll = false }
                }
            },
            onTap: { model.controls.toggle() },
            onDrag: { model.controls = false; model.autoScroll = false },
            onHoldChanged: { active in
                holdScrolling = active
                if active { model.autoScroll = false; model.controls = false }
            },
            onAutoStop: { model.autoScroll = false; model.controls = true },
            onNext: { Task { if model.hasNext { await model.select(model.chapters[model.chapterIndex + 1]) } else { await close() } } })
    }
    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { Task { await close() } } label: { Image(systemName: "chevron.left") }
                    .readerCircle().disabled(closing).accessibilityLabel("Back to chapters").accessibilityIdentifier("webtoon-close")
                Spacer(minLength: 0)
                Button { chapters = true } label: {
                    HStack(spacing: 9) {
                        VStack(spacing: 3) {
                            Text(model.chapter.name).font(.subheadline.bold()).lineLimit(1)
                            Text(model.title.manga.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Image(systemName: "chevron.down").font(.caption)
                    }.padding(.horizontal, 16).padding(.vertical, 10).readerControlSurface(in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("webtoon-chapters")
                Spacer(minLength: 0)
                Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }
                    .readerCircle().accessibilityLabel("Reader settings").accessibilityIdentifier("webtoon-settings")
            }.padding(.horizontal, 16).padding(.top, 8)
            if let message = reading.error {
                Text(message).font(.caption).padding(12).readerControlSurface(in: Capsule()).padding(.top, 8)
            }
            if let message = progressSync.message {
                HStack {
                    Text(message).font(.caption)
                    if progressSync.failed { Button("Retry") { progressSync.retry(account: account, links: links) }.font(.caption.bold()) }
                }.padding(12).readerControlSurface(in: Capsule()).padding(.horizontal, 16).padding(.top, 8)
            }
            Spacer()
            if !model.pages.isEmpty {
                readingPanel.padding(.horizontal, 16).padding(.bottom, 12)
            }
        }.foregroundStyle(.white).environment(\.colorScheme, .dark)
    }
    private var activeProgressLink: MangaSourceLink? {
        let all = Array(links.state.links.values)
        let enabled = Set(all.filter { UserDefaults.standard.bool(forKey: MangaProgressPolicy.consentKey(for: $0)) }.map(MangaProgressPolicy.consentKey))
        return MangaProgressPolicy.automaticLink(for: model.title.id, accountID: account.profile?.id, links: all, enabledKeys: enabled)
            ?? MangaProgressPolicy.link(for: model.title.id, accountID: account.profile?.id, links: all)
    }
    private var readerInteractionAllowed: Bool { !settings && !chapters && !website && !pageJump && !restarting && !progressSettings && !closing && scene == .active }
    private var readingPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Button { Task { await model.move(-1) } } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }
                    .disabled(!model.hasPrevious).accessibilityLabel("Previous chapter").accessibilityIdentifier("webtoon-previous-chapter")
                Spacer(minLength: 0)
                Button { pageNumber = String(model.currentPage + 1); pageJump = true } label: {
                    VStack(spacing: 3) {
                        Text("\(controlPage + 1) / \(model.pages.count)").font(.subheadline.monospacedDigit().bold())
                            .accessibilityIdentifier("webtoon-page-counter")
                        Text("Go to page").font(.caption2).foregroundStyle(.secondary)
                    }.frame(minHeight: 44)
                }.accessibilityLabel("Go to page").accessibilityValue("\(controlPage + 1) / \(model.pages.count)").accessibilityIdentifier("webtoon-go-to-page")
                Spacer(minLength: 0)
                Button { Task { await model.move(1) } } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }
                    .disabled(!model.hasNext).accessibilityLabel("Next chapter").accessibilityIdentifier("webtoon-next-chapter")
                readerOptions
            }
            Slider(value: Binding(get: { scrubbing ? scrubPage : Double(model.currentPage) }, set: {
                scrubPage = $0
                if !scrubbing { model.goToPage(Int($0.rounded())) }
            }), in: 0...Double(max(1, model.pages.count - 1)), step: 1, onEditingChanged: { editing in
                if editing { scrubPage = Double(model.currentPage); scrubbing = true; model.autoScroll = false }
                else { let target = Int(scrubPage.rounded()); scrubbing = false; model.goToPage(target) }
            }).disabled(model.pages.count == 1).accessibilityLabel("Page")
                .accessibilityValue("Page \(controlPage + 1) of \(model.pages.count)").accessibilityIdentifier("webtoon-page-scrubber")
            Divider().overlay(.white.opacity(0.08))
            scrollControls
        }.padding(.horizontal, 16).padding(.vertical, 10).frame(maxWidth: 620)
            .readerControlSurface(in: RoundedRectangle(cornerRadius: 24)).buttonStyle(.plain)
    }
    private var readerOptions: some View {
        Menu {
            Button("Read from beginning", systemImage: "backward.end") { restarting = true }
            Button(model.hasNext ? "Mark read & next chapter" : "Mark chapter as read", systemImage: "checkmark.circle") {
                guard !finishingChapter else { return }
                let chapter = model.chapter
                finishingChapter = true; model.autoScroll = false
                Task {
                    await model.flush()
                    await reading.mark(model.title, chapter: chapter, read: true)
                    if reading.record(model.title.id)?.position(for: chapter.url)?.completed == true {
                        progressSync.completed(title: model.title, chapter: chapter, account: account, links: links)
                    }
                    if model.chapter.url == chapter.url, reading.record(model.title.id)?.position(for: chapter.url)?.completed == true, model.hasNext {
                        await model.move(1)
                    }
                    finishingChapter = false
                }
            }.disabled(finishingChapter || reading.loading || reading.unreadable)
            if activeProgressLink != nil {
                Button("MangaBaka progress", systemImage: "checkmark.circle") { progressSettings = true }
            }
            Button("Open source website", systemImage: "globe") { website = true }
            if let url = model.title.source.webURL(for: model.chapter.url) {
                ShareLink(item: url) { Label("Share chapter", systemImage: "square.and.arrow.up") }
            }
            Button("Hide controls", systemImage: "eye.slash") { model.controls = false }
        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
            .accessibilityLabel("Reader actions").accessibilityIdentifier("webtoon-actions")
    }
    @ViewBuilder private var scrollControls: some View {
        if textSize.isAccessibilitySize {
            VStack(spacing: 6) { scrollToggle; speedControls }
        } else {
            HStack(spacing: 10) { scrollToggle; Spacer(minLength: 0); speedControls }
        }
    }
    private var scrollToggle: some View {
        Button { model.autoScroll.toggle() } label: {
            Label(model.autoScroll ? "Pause" : "Auto-scroll", systemImage: model.autoScroll ? "pause.fill" : "play.fill")
                .font(.caption.bold()).frame(minHeight: 44)
        }.accessibilityIdentifier("webtoon-auto-scroll-toggle")
            .accessibilityValue(model.autoScroll ? "Scrolling" : "Paused")
    }
    private var speedControls: some View {
        HStack(spacing: 6) {
            Button { adjustSpeed(-15) } label: { Image(systemName: "minus").frame(width: 40, height: 44) }
                .disabled(preferences.autoScrollSpeed <= WebtoonPreferences.scrollSpeedRange.lowerBound)
                .accessibilityLabel("Scroll slower").accessibilityIdentifier("webtoon-scroll-slower")
            WebtoonSpeedMenu(speed: $preferences.autoScrollSpeed)
            Button { adjustSpeed(15) } label: { Image(systemName: "plus").frame(width: 40, height: 44) }
                .disabled(preferences.autoScrollSpeed >= WebtoonPreferences.scrollSpeedRange.upperBound)
                .accessibilityLabel("Scroll faster").accessibilityIdentifier("webtoon-scroll-faster")
        }.buttonStyle(.plain)
    }
    private func adjustSpeed(_ delta: Double) {
        preferences.autoScrollSpeed += delta; preferences.normalize()
    }
    private var controlPage: Int { scrubbing ? Int(scrubPage.rounded()) : model.currentPage }
    private var chapterPicker: some View {
        MangaReaderChapterPicker(title: model.title.manga.title, chapters: model.chapters, current: model.chapter,
            record: reading.record(model.title.id), onSelect: { chapter in
                chapters = false; Task { await model.select(chapter) }
            }, onDone: { chapters = false })
    }
    private func updateAwake() { UIApplication.shared.isIdleTimerDisabled = scene == .active && preferences.keepAwake ? true : originalIdleTimer }
    private func close() async {
        guard !closing else { return }
        closing = true; model.autoScroll = false; holdScrolling = false; model.cancelPrefetch()
        await model.flush(); await reading.preferences(preferences)
        dismiss()
    }
}

private extension View {
    func readerCircle() -> some View {
        font(.system(size: 17, weight: .semibold)).frame(width: 46, height: 46)
            .readerControlSurface(in: Circle()).buttonStyle(.plain)
    }
}

private struct WebtoonSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var preferences: WebtoonPreferences
    @Binding var autoScroll: Bool
    var body: some View {
        AppNavigationStack {
            Form {
                Section("Display") {
                    Picker("Background", selection: $preferences.background) {
                        Text("Black").tag(WebtoonPreferences.Background.black)
                        Text("Charcoal").tag(WebtoonPreferences.Background.charcoal)
                        Text("Paper").tag(WebtoonPreferences.Background.paper)
                    }.pickerStyle(.segmented)
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Side padding", value: "\(Int(preferences.sidePadding * 100))%")
                        Slider(value: $preferences.sidePadding, in: 0...0.12, step: 0.01).accessibilityIdentifier("webtoon-side-padding")
                    }
                }
                Section {
                    Toggle("Automatically load next chapter", isOn: $preferences.autoLoadNextChapter)
                        .accessibilityIdentifier("webtoon-auto-next")
                } header: { Text("Chapter flow") }
                footer: { Text("Continue into the next chapter after reaching the end. Missing images pause automatic chapter loading.") }
                Section {
                    Toggle("Hold to scroll", isOn: $preferences.holdToScroll).accessibilityIdentifier("webtoon-hold-to-scroll")
                    Toggle("Auto-scroll", isOn: $autoScroll).accessibilityIdentifier("webtoon-auto-scroll")
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("Scroll speed") { WebtoonSpeedMenu(speed: $preferences.autoScrollSpeed) }
                        Slider(value: $preferences.autoScrollSpeed, in: WebtoonPreferences.scrollSpeedRange, step: 5)
                            .accessibilityLabel("Scroll speed").accessibilityIdentifier("webtoon-scroll-speed-slider")
                    }
                } header: { Text("Scrolling") }
                footer: { Text("Hold to scroll stops when you lift your finger. Auto-scroll continues until paused. Dragging, opening a reader sheet, changing chapters or leaving the app pauses it.") }
                Section {
                    Toggle("Keep screen awake", isOn: $preferences.keepAwake)
                    Label("Tap to show or hide controls", systemImage: "hand.tap")
                    Label("Pinch or double-tap to zoom", systemImage: "arrow.up.left.and.arrow.down.right")
                } header: { Text("Comfort & gestures") }
            }.navigationTitle("Webtoon reader").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark).tint(MangaStyle.accent)
    }
}

private struct WebtoonSpeedMenu: View {
    @Binding var speed: Double
    var body: some View {
        Menu {
            ForEach([45, 120, 240, 480, 720, 1200], id: \.self) { value in
                Button("\(value) pt/s") { speed = Double(value) }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(Int(speed)) pt/s").monospacedDigit()
                Image(systemName: "chevron.down").font(.caption2)
            }.font(.caption.bold()).frame(minHeight: 44)
        }.accessibilityLabel("Scroll speed").accessibilityValue("\(Int(speed)) points per second")
            .accessibilityIdentifier("webtoon-scroll-speed")
    }
}
