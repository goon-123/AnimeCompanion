import SwiftUI
import AnimeCore

@MainActor
final class MangaProgressSyncModel: ObservableObject {
    private struct Attempt {
        let link: MangaSourceLink
        let chapter: Double
        let connection: UUID
    }
    @Published private(set) var message: String?
    @Published private(set) var failed = false
    private var pending: Attempt?
    private var retryAttempt: Attempt?
    private var task: Task<Void, Never>?
    func completed(_ title: MangaTitleReference, chapter: SourceMangaChapter, account: MangaBakaStore, links: MangaSourceLinkStore) {
        let all = Array(links.state.links.values)
        let enabled = Set(all.filter { UserDefaults.standard.bool(forKey: MangaProgressPolicy.consentKey(for: $0)) }.map(MangaProgressPolicy.consentKey))
        guard let link = MangaProgressPolicy.automaticLink(for: title.id, accountID: account.profile?.id, links: all, enabledKeys: enabled) else { return }
        guard let number = MangaProgressPolicy.automaticChapter(chapter) else {
            message = "Update this chapter manually in MangaBaka progress."; failed = false; return
        }
        let attempt = Attempt(link: link, chapter: number, connection: account.connectionID)
        if let pending, pending.link == link, pending.connection == attempt.connection, pending.chapter >= number { return }
        pending = attempt
        start(account: account, links: links)
    }
    func retry(account: MangaBakaStore, links: MangaSourceLinkStore) {
        guard let retryAttempt else { return }
        pending = retryAttempt; start(account: account, links: links)
    }
    private func start(account: MangaBakaStore, links: MangaSourceLinkStore) {
        guard task == nil else { return }
        task = Task { [self] in
            defer { task = nil }
            while let attempt = pending {
                pending = nil; failed = false; message = "Updating MangaBaka progress…"
                do {
                    let value = try await account.advanceChapterProgress(for: attempt.link, chapter: attempt.chapter, expectedConnection: attempt.connection) {
                        links.link(for: attempt.link.library) == attempt.link &&
                        UserDefaults.standard.bool(forKey: MangaProgressPolicy.consentKey(for: attempt.link))
                    }
                    message = "MangaBaka · Chapter " + String(format: "%g", value); retryAttempt = nil
                } catch is CancellationError { message = nil; retryAttempt = nil }
                catch { message = "MangaBaka: " + error.localizedDescription; failed = true; retryAttempt = attempt }
            }
        }
    }
}

struct MangaProgressSettingsView: View {
    @EnvironmentObject private var account: MangaBakaStore
    @EnvironmentObject private var links: MangaSourceLinkStore
    @EnvironmentObject private var reading: MangaReadingStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage private var automatic: Bool
    let link: MangaSourceLink
    let chapters: [SourceMangaChapter]
    @State private var chapterText = ""
    @State private var remoteChapter: Double?
    @State private var loaded = false
    @State private var loading = false
    @State private var loadToken = UUID()
    @State private var saving = false
    @State private var error: String?
    @State private var notice: String?
    init(link: MangaSourceLink, chapters: [SourceMangaChapter]) {
        self.link = link; self.chapters = chapters
        _automatic = AppStorage(wrappedValue: false, MangaProgressPolicy.consentKey(for: link))
    }
    private var linked: Bool { links.link(for: link.library) == link }
    private var correctAccount: Bool { account.connected && account.profile?.id == link.library.accountID }
    private var chapter: Double? {
        Double(chapterText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
            .flatMap { (try? MangaBakaProgressUpdate(chapter: $0))?.chapter }
    }
    var body: some View {
        AppNavigationStack {
            Form {
                Section {
                    Text(link.library.title).font(.headline)
                    LabeledContent("Source", value: link.title.source.name)
                    if let name = account.profile?.name { LabeledContent("Account", value: name) }
                    if loading { ProgressView("Loading MangaBaka progress…") }
                    else if loaded { LabeledContent("MangaBaka chapter", value: remoteChapter.map { String(format: "%g", $0) } ?? "Not set") }
                    if !linked { Text("This source link has changed. Reopen progress from the linked series.").foregroundStyle(.orange) }
                    if !correctAccount { Text("Connect the MangaBaka account linked to this series.").foregroundStyle(.orange) }
                }
                Section {
                    Toggle("Update after finishing a chapter", isOn: $automatic)
                        .disabled(!loaded || !linked || !correctAccount || saving)
                        .accessibilityIdentifier("manga-progress-automatic")
                        .onChange(of: automatic) { _, enabled in
                            guard enabled, linked, correctAccount else { return }
                            for other in links.state.links.values where other.library.accountID == link.library.accountID && other.title.id == link.title.id && other.id != link.id {
                                UserDefaults.standard.set(false, forKey: MangaProgressPolicy.consentKey(for: other))
                            }
                        }
                } header: { Text("Automatic updates on this device") }
                footer: { Text("Off by default. Enabling this selects this library entry for automatic updates from this source on this device. Completed, clearly numbered whole chapters update automatically; extras and ambiguous numbers use manual updates.") }
                Section {
                    TextField("Completed chapter number", text: $chapterText).keyboardType(.decimalPad)
                        .accessibilityIdentifier("manga-progress-chapter")
                    Button(saving ? "Updating…" : "Update MangaBaka") { update() }
                        .disabled(saving || loading || !loaded || !linked || !correctAccount || chapter.map { !MangaProgressPolicy.shouldAdvance(current: remoteChapter, proposed: $0) } ?? true)
                        .accessibilityIdentifier("manga-progress-update")
                    if let notice { Text(notice).foregroundStyle(.secondary) }
                    if let error { Text(error).foregroundStyle(.orange) }
                    Button("Refresh MangaBaka progress") { Task { await load() } }.disabled(loading || saving || !correctAccount || !linked)
                } header: { Text("Manual update") }
                footer: { Text("Checks your current MangaBaka chapter and updates it only when the new value is higher. Only chapter progress changes; status, ratings, notes, volumes and lists stay as set. Local reading progress is kept if an update fails.") }
            }.navigationTitle("MangaBaka progress").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(saving) } }
                .task(id: account.connectionID) { await load() }
        }.tint(MangaStyle.accent).interactiveDismissDisabled(saving)
    }
    private func load() async {
        let token = UUID(); loadToken = token
        loading = true; loaded = false; error = nil
        defer { if loadToken == token { loading = false } }
        guard correctAccount, linked else { return }
        let connection = account.connectionID
        do {
            await reading.load()
            let entry = try await account.progressEntry(for: link, expectedConnection: connection)
            guard linked, connection == account.connectionID, loadToken == token else { return }
            remoteChapter = entry.chapter; loaded = true
            if chapterText.isEmpty {
                let record = reading.record(link.title.id)
                let completed = Set((record?.positions ?? []).filter(\.completed).map(\.chapterURL))
                let known = chapters.filter { completed.contains($0.url) }.compactMap(MangaProgressPolicy.automaticChapter)
                let stored = (record?.positions ?? []).filter(\.completed).compactMap {
                    MangaProgressPolicy.automaticChapter(.init(url: $0.chapterURL, name: $0.chapterName))
                }
                let suggested = max(entry.chapter ?? 0, (known + stored).max() ?? 0)
                chapterText = suggested > 0 ? String(format: "%g", suggested) : ""
            }
        } catch is CancellationError {} catch { if loadToken == token { error = error.localizedDescription } }
    }
    private func update() {
        guard let chapter, linked, correctAccount, !saving else { return }
        let connection = account.connectionID
        saving = true; error = nil; notice = nil
        Task {
            defer { saving = false }
            do {
                let value = try await account.advanceChapterProgress(for: link, chapter: chapter, expectedConnection: connection) { linked }
                guard linked, connection == account.connectionID else { return }
                remoteChapter = value; chapterText = String(format: "%g", value)
                notice = "MangaBaka progress is up to date."
            } catch is CancellationError {} catch { error = error.localizedDescription }
        }
    }
}
