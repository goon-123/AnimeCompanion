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
    @Published var error: String?
    @Published var controls = true
    @Published var autoScroll = false
    @Published var currentPage = 0
    @Published var jump: WebtoonJump?
    private(set) var initial: MangaReadingPosition?
    private var confirmed: MangaReadingPosition?
    private var reading: MangaReadingStore?
    private var generation = UUID()
    private var saveTask: Task<Void, Never>?
    var chapterIndex: Int { chapters.firstIndex(of: chapter) ?? 0 }
    var hasNext: Bool { chapterIndex + 1 < chapters.count }
    var hasPrevious: Bool { chapterIndex > 0 }
    init(_ route: MangaReaderRoute) { title = route.title; chapters = route.chapters; chapter = route.chapter }
    func load(extensions: MangaExtensionStore, reading: MangaReadingStore) async {
        guard !loading else { return }
        self.reading = reading
        let token = UUID(); generation = token
        loading = true; error = nil
        defer { if generation == token { loading = false } }
        do {
            let list = try await extensions.pages(title.source, chapter: chapter)
            try Task.checkCancellation()
            guard generation == token else { return }
            guard !list.isEmpty else { throw WebtoonReaderError.empty }
            guard list.count <= 5000 else { throw MangaExtensionError.oversized }
            let saved = reading.record(title.id)?.position(for: chapter.url)
            initial = saved?.completed == false ? saved?.clamped(to: list.count) : nil
            currentPage = initial?.pageIndex ?? 0; pages = list
        } catch is CancellationError {} catch { if generation == token { self.error = error.localizedDescription } }
    }
    func position(page: Int, fraction: Double, complete: Bool) {
        guard !pages.isEmpty, pages.indices.contains(page) else { return }
        currentPage = page
        let point = MangaReadingPosition(chapterURL: chapter.url, chapterName: chapter.name, pageIndex: page,
            pageCount: pages.count, fraction: fraction, completed: complete)
        confirmed = point
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)); try Task.checkCancellation() } catch { return }
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
    func select(_ value: SourceMangaChapter) async {
        guard value != chapter else { return }
        let token = generation
        await flush()
        guard generation == token, value != chapter else { return }
        autoScroll = false; controls = true
        pages = []; initial = nil; confirmed = nil; currentPage = 0; jump = nil; error = nil
        generation = UUID(); loading = false; chapter = value
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scene
    @StateObject private var model: WebtoonReaderModel
    @State private var preferences = WebtoonPreferences()
    @State private var loadedPreferences = false
    @State private var scrubbing = false
    @State private var scrubPage = 0.0
    @State private var settings = false
    @State private var holdScrolling = false
    @State private var chapters = false
    @State private var website = false
    @State private var closing = false
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
            if model.controls || model.pages.isEmpty { chrome }
            if holdScrolling {
                VStack { Spacer(); Label("\(Int(preferences.autoScrollSpeed)) pt/s · Lift to stop", systemImage: "hand.point.up.left.fill")
                    .font(.caption.monospacedDigit().bold()).padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 24)
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
        }.preferredColorScheme(.dark).tint(MangaStyle.accent).statusBarHidden(!model.controls && !model.pages.isEmpty)
            .persistentSystemOverlays(model.controls ? .visible : .hidden)
            .task(id: model.chapter.url) {
                await reading.load()
                if !loadedPreferences { preferences = reading.state.preferences; loadedPreferences = true }
                await model.load(extensions: extensions, reading: reading)
            }
            .onAppear {
                if !capturedIdleTimer { originalIdleTimer = UIApplication.shared.isIdleTimerDisabled; capturedIdleTimer = true }
                updateAwake()
                Task { await ArtworkPipeline.shared.clearMemory() }
            }
            .onChange(of: preferences.keepAwake) { _, _ in updateAwake() }
            .onChange(of: scene) { _, value in
                if value != .active {
                    model.autoScroll = false; scrubbing = false; UIApplication.shared.isIdleTimerDisabled = originalIdleTimer
                    Task { await model.flush(); await reading.preferences(preferences) }
                } else { updateAwake() }
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = originalIdleTimer
                model.autoScroll = false
                Task { await model.flush(); await reading.preferences(preferences) }
            }
            .sheet(isPresented: $settings, onDismiss: { Task { await reading.preferences(preferences) } }) {
                WebtoonSettingsView(preferences: $preferences, autoScroll: $model.autoScroll)
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $chapters) { chapterPicker }
            .sheet(isPresented: $website) {
                MangaSourceSessionView(source: model.title.source) {
                    Task { await model.load(extensions: extensions, reading: reading) }
                }
            }
    }
    private var canvas: some View {
        let store = extensions, source = model.title.source
        return WebtoonCanvas(source: source, version: extensions.imageVersion(source),
            chapterKey: model.chapter.url, pages: model.pages, initial: model.initial, jump: model.jump,
            preferences: preferences, autoScroll: model.autoScroll,
            scrollingAllowed: !settings && !chapters && !website && !scrubbing && !closing && scene == .active,
            hasNext: model.hasNext,
            loader: { try await store.imageData(source, image: $0) },
            onPosition: { model.position(page: $0, fraction: $1, complete: $2) },
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
                    }.padding(.horizontal, 16).padding(.vertical, 10).background(.ultraThinMaterial, in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("webtoon-chapters")
                Spacer(minLength: 0)
                Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }
                    .readerCircle().accessibilityLabel("Reader settings").accessibilityIdentifier("webtoon-settings")
            }.padding(.horizontal, 16).padding(.top, 8)
            if let message = reading.error {
                Text(message).font(.caption).padding(12).background(.ultraThinMaterial, in: Capsule()).padding(.top, 8)
            }
            Spacer()
            if !model.pages.isEmpty {
                scrollControls.padding(.horizontal, 24).padding(.bottom, 10)
                HStack(spacing: 12) {
                    Button { Task { await model.move(-1) } } label: { Image(systemName: "backward.end.fill") }
                        .readerCircle().disabled(!model.hasPrevious).accessibilityLabel("Previous chapter").accessibilityIdentifier("webtoon-previous-chapter")
                    VStack(spacing: 5) {
                        Text("\(controlPage + 1) / \(model.pages.count)").font(.caption.monospacedDigit().bold())
                            .accessibilityIdentifier("webtoon-page-counter")
                        Slider(value: Binding(get: { scrubbing ? scrubPage : Double(model.currentPage) }, set: {
                            scrubPage = $0
                            // Accessibility adjustments can arrive without a touch-editing session.
                            if !scrubbing { model.goToPage(Int($0.rounded())) }
                        }), in: 0...Double(max(1, model.pages.count - 1)), step: 1, onEditingChanged: { editing in
                            if editing { scrubPage = Double(model.currentPage); scrubbing = true; model.autoScroll = false }
                            else {
                                let target = Int(scrubPage.rounded()); scrubbing = false
                                model.goToPage(target)
                            }
                        })
                            .disabled(model.pages.count == 1).accessibilityLabel("Page")
                            .accessibilityValue("Page \(controlPage + 1) of \(model.pages.count)")
                            .accessibilityIdentifier("webtoon-page-scrubber")
                    }.padding(.horizontal, 16).padding(.vertical, 10).background(.ultraThinMaterial, in: Capsule())
                    Button { Task { await model.move(1) } } label: { Image(systemName: "forward.end.fill") }
                        .readerCircle().disabled(!model.hasNext).accessibilityLabel("Next chapter").accessibilityIdentifier("webtoon-next-chapter")
                }.padding(.horizontal, 16).padding(.bottom, 12)
            }
        }.foregroundStyle(.white)
    }
    private var scrollControls: some View {
        HStack(spacing: 10) {
            Button { model.autoScroll.toggle() } label: {
                Label(model.autoScroll ? "Pause" : "Auto-scroll", systemImage: model.autoScroll ? "pause.fill" : "play.fill")
                    .font(.caption.bold()).frame(minHeight: 44)
            }.accessibilityIdentifier("webtoon-auto-scroll-toggle")
                .accessibilityValue(model.autoScroll ? "Scrolling" : "Paused")
            Spacer(minLength: 0)
            Button { adjustSpeed(-15) } label: { Image(systemName: "minus").frame(width: 40, height: 44) }
                .disabled(preferences.autoScrollSpeed <= WebtoonPreferences.scrollSpeedRange.lowerBound)
                .accessibilityLabel("Scroll slower").accessibilityIdentifier("webtoon-scroll-slower")
            Text("\(Int(preferences.autoScrollSpeed)) pt/s").font(.caption.monospacedDigit().bold())
                .accessibilityLabel("Scroll speed").accessibilityIdentifier("webtoon-scroll-speed")
            Button { adjustSpeed(15) } label: { Image(systemName: "plus").frame(width: 40, height: 44) }
                .disabled(preferences.autoScrollSpeed >= WebtoonPreferences.scrollSpeedRange.upperBound)
                .accessibilityLabel("Scroll faster").accessibilityIdentifier("webtoon-scroll-faster")
        }.padding(.horizontal, 14).background(.ultraThinMaterial, in: Capsule()).buttonStyle(.plain)
    }
    private func adjustSpeed(_ delta: Double) {
        preferences.autoScrollSpeed += delta; preferences.normalize()
    }
    private var controlPage: Int { scrubbing ? Int(scrubPage.rounded()) : model.currentPage }
    private var chapterPicker: some View {
        NavigationStack {
            List(model.chapters) { chapter in
                Button {
                    chapters = false
                    Task { await model.select(chapter) }
                } label: {
                    HStack {
                        Text(chapter.name)
                        Spacer()
                        if chapter == model.chapter { Image(systemName: "book") }
                        else if reading.record(model.title.id)?.position(for: chapter.url)?.completed == true { Image(systemName: "checkmark") }
                    }.foregroundStyle(chapter == model.chapter ? MangaStyle.accent : .white)
                }.accessibilityIdentifier("webtoon-choose-chapter-\(model.chapters.firstIndex(of: chapter) ?? 0)")
            }.navigationTitle("Chapters").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { chapters = false } } }
        }.tint(MangaStyle.accent)
    }
    private func updateAwake() { UIApplication.shared.isIdleTimerDisabled = scene == .active && preferences.keepAwake ? true : originalIdleTimer }
    private func close() async { guard !closing else { return }; closing = true; model.autoScroll = false; await model.flush(); dismiss() }
}

private extension View {
    func readerCircle() -> some View {
        font(.system(size: 17, weight: .semibold)).frame(width: 46, height: 46)
            .background(.ultraThinMaterial, in: Circle()).buttonStyle(.plain)
    }
}

private struct WebtoonSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var preferences: WebtoonPreferences
    @Binding var autoScroll: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Reading mode", value: "Continuous vertical")
                    Text("Hold the page to scroll and lift your finger to stop. Tap for controls; pinch or double-tap to zoom.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Appearance") {
                    Picker("Background", selection: $preferences.background) {
                        Text("Black").tag(WebtoonPreferences.Background.black)
                        Text("Charcoal").tag(WebtoonPreferences.Background.charcoal)
                        Text("Paper").tag(WebtoonPreferences.Background.paper)
                    }
                    VStack(alignment: .leading) {
                        LabeledContent("Side padding", value: "\(Int(preferences.sidePadding * 100))%")
                        Slider(value: $preferences.sidePadding, in: 0...0.12, step: 0.01).accessibilityIdentifier("webtoon-side-padding")
                    }
                }
                Section {
                    Toggle("Hold to scroll", isOn: $preferences.holdToScroll).accessibilityIdentifier("webtoon-hold-to-scroll")
                    Toggle("Auto-scroll", isOn: $autoScroll).accessibilityIdentifier("webtoon-auto-scroll")
                    VStack(alignment: .leading) {
                        LabeledContent("Scroll speed", value: "\(Int(preferences.autoScrollSpeed)) pt/s")
                        Slider(value: $preferences.autoScrollSpeed, in: WebtoonPreferences.scrollSpeedRange, step: 5)
                            .accessibilityLabel("Scroll speed").accessibilityIdentifier("webtoon-scroll-speed-slider")
                    }
                    Toggle("Keep screen awake", isOn: $preferences.keepAwake)
                } header: { Text("Reading") }
                footer: { Text("Hold to scroll stops when you lift your finger. Auto-scroll keeps moving until paused. Both stop for a drag, chapter change, app switch or chapter end.") }
            }.navigationTitle("Webtoon reader").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.preferredColorScheme(.dark).tint(MangaStyle.accent)
    }
}
