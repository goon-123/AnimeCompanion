import SwiftUI
import AnimeCore

struct ProgressControl: View {
    @EnvironmentObject private var store: AppStore
    let anime: Anime
    @State private var error: String?
    @State private var editing = false
    private var entry: LibraryEntry? { store.entry(for: anime.id) }
    private var busy: Bool { store.savingMedia.contains(anime.id) || store.loadingLibrary || store.savedAt == nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    let status = entry?.status == .completed ? LibraryStatus.watching : (entry?.status ?? .watching)
                    perform { try await store.save(anime: anime, progress: max(0, (entry?.progressValue ?? 0) - 1), status: status) }
                } label: { Image(systemName: "minus").frame(minWidth: 44, minHeight: 44) }
                    .disabled(busy || (entry?.progressValue ?? 0) == 0).accessibilityLabel("Decrease watched episodes")
                Spacer(minLength: 0)
                Button { editing = true } label: {
                    VStack(spacing: 4) {
                        Text("\(entry?.progressValue ?? 0) / \(anime.episodes.map(String.init) ?? "?")").font(.title3.bold().monospacedDigit())
                        Text("Set episode").font(.caption2)
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("tracking-set-episode")
                Spacer(minLength: 0)
                Button { perform { try await store.markNextWatched(anime: anime) } } label: {
                    Label("+1", systemImage: "checkmark").font(.headline).frame(minWidth: 44, minHeight: 44)
                }.disabled(busy || atEnd).accessibilityLabel("Increase watched episodes").accessibilityIdentifier("tracking-next")
            }.buttonStyle(.bordered)
            HStack {
                Menu {
                    ForEach(LibraryStatus.allCases) { status in
                        Button(status.label) { perform { try await store.save(anime: anime, progress: entry?.progressValue ?? 0, status: status) } }
                    }
                    if entry != nil { Button("Start rewatch from episode 1", systemImage: "arrow.counterclockwise") {
                        perform { try await store.save(anime: anime, progress: 0, status: .rewatching) }
                    } }
                } label: { Label(entry?.status?.label ?? "Add to AniList", systemImage: "checklist").frame(minHeight: 44) }.disabled(busy)
                Spacer()
                Button("Edit", systemImage: "pencil") { editing = true }.disabled(busy).accessibilityIdentifier("tracking-edit")
            }
            if let score = entry?.score, score > 0 { Text("Your rating: \(score / 10, specifier: "%.1f") / 10").font(.caption).foregroundStyle(.secondary) }
            if store.savingMedia.contains(anime.id) { ProgressView("Saving to AniList…").font(.caption) }
            TrackingFeedback(anime: anime)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.sheet(isPresented: $editing) { TrackingEditorView(anime: anime, entry: entry) }
    }
    private var atEnd: Bool { anime.episodes.map { $0 > 0 && (entry?.progressValue ?? 0) >= $0 } ?? false }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        error = nil
        Task { do { try await action() } catch { self.error = error.localizedDescription } }
    }
}

struct TrackingFeedback: View {
    @EnvironmentObject private var store: AppStore
    let anime: Anime
    @State private var error: String?
    var body: some View {
        if let message = store.trackingMessages[anime.id] {
            HStack {
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.mint)
                Spacer()
                if store.canUndo(anime.id) {
                    Button("Undo") { Task { do { try await store.undo(anime: anime) } catch { self.error = error.localizedDescription } } }
                        .disabled(store.savingMedia.contains(anime.id) || store.loadingLibrary).accessibilityIdentifier("tracking-undo")
                }
            }.font(.caption).accessibilityIdentifier("tracking-feedback")
        }
        if let error { Text(error).font(.caption).foregroundStyle(.red) }
    }
}

struct TrackingEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let anime: Anime
    let original: LibraryEntry?
    @State private var progress: String
    @State private var status: LibraryStatus
    @State private var score: Double
    @State private var notes: String
    @State private var repeats: Int
    @State private var error: String?
    @State private var removing = false
    @State private var saving = false
    init(anime: Anime, entry: LibraryEntry?) {
        self.anime = anime; original = entry
        _progress = State(initialValue: String(entry?.progressValue ?? 0))
        _status = State(initialValue: entry?.status ?? .planning)
        _score = State(initialValue: (entry?.score ?? 0) / 10)
        _notes = State(initialValue: entry?.notes ?? "")
        _repeats = State(initialValue: entry?.repeatCount ?? 0)
    }
    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Text(anime.displayTitle).font(.headline)
                    Picker("Status", selection: $status) { ForEach(LibraryStatus.allCases) { Text($0.label).tag($0) } }.accessibilityIdentifier("tracking-status")
                    HStack {
                        Text("Episodes watched")
                        TextField("0", text: $progress).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("tracking-episode-input")
                    }
                    if let total = anime.episodes, total > 0 {
                        Text("AniList total: \(total) episodes. Completed fills this total.").font(.caption).foregroundStyle(.secondary)
                    } else { Text("Episode total is unknown. Enter your progress directly.").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Your rating") {
                    Stepper(value: $score, in: 0...10, step: 0.5) {
                        Text(score == 0 ? "Not rated" : String(format: "%.1f / 10", score))
                    }.accessibilityIdentifier("tracking-score")
                    Text("Displayed out of 10; AniList converts this to your account’s score format.").font(.caption).foregroundStyle(.secondary)
                    if score > 0 { Button("Clear rating") { score = 0 } }
                }
                Section("Rewatches") {
                    Stepper("Completed rewatches: \(repeats)", value: $repeats, in: 0...10_000)
                    if status == .rewatching { Button("Reset watched episodes to zero") { progress = "0" } }
                }
                Section("Notes") {
                    TextEditor(text: $notes).frame(minHeight: 100).accessibilityIdentifier("tracking-notes")
                    Text("\(notes.count) / 6,000 characters").font(.caption).foregroundStyle(notes.count > 6000 ? Color.red : Color.secondary)
                }
                if original != nil {
                    Section { Button("Remove from AniList", role: .destructive) { removing = true }.disabled(saving) }
                }
            }.navigationTitle("Edit AniList tracking").navigationBarTitleDisplayMode(.inline)
                .disabled(saving)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        if saving { ProgressView() }
                        else { Button("Save") { save() }.disabled(Int(progress) == nil || notes.count > 6000).accessibilityIdentifier("tracking-save") }
                    }
                }
                .confirmationDialog("Remove this anime from AniList?", isPresented: $removing, titleVisibility: .visible) {
                    Button("Remove from AniList", role: .destructive) {
                        saving = true
                        Task { do { try await store.remove(anime: anime); dismiss() } catch { self.error = error.localizedDescription; saving = false } }
                    }
                } message: { Text("This removes its saved progress, rating, and notes from your AniList account.") }
                .interactiveDismissDisabled(saving)
        }
    }
    private func save() {
        guard let progress = Int(progress) else { return }
        error = nil; saving = true
        let scoreRaw = Int((score * 10).rounded())
        let edit = TrackingEdit(progress: progress, status: status,
            scoreRaw: scoreRaw == Int((original?.score ?? 0).rounded()) ? nil : scoreRaw,
            notes: notes == (original?.notes ?? "") ? nil : notes,
            repeatCount: repeats == (original?.repeatCount ?? 0) ? nil : repeats)
        Task { do { try await store.save(anime: anime, edit: edit); dismiss() } catch { self.error = error.localizedDescription; saving = false } }
    }
}

struct CompactTrackingBar: View {
    @EnvironmentObject private var store: AppStore
    let anime: Anime
    @State private var editing = false
    @State private var settings = false
    @State private var playback = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(anime.displayTitle).font(.caption.bold()).lineLimit(1)
                    Text("AniList · \(store.entry(for: anime.id)?.status?.label ?? "Not tracked") · \(store.entry(for: anime.id)?.progressValue ?? 0)/\(anime.episodes.map(String.init) ?? "?")")
                        .font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if store.isSignedIn {
                    Button { Task { do { try await store.markNextWatched(anime: anime) } catch { self.error = error.localizedDescription } } } label: {
                        Label("+1", systemImage: "checkmark").frame(minHeight: 44)
                    }.buttonStyle(.bordered).disabled(busy || atEnd).accessibilityIdentifier("livechart-track-next")
                    Button { editing = true } label: { Image(systemName: "pencil").frame(width: 44, height: 44) }
                        .disabled(busy).accessibilityLabel("Edit AniList tracking").accessibilityIdentifier("livechart-track-edit")
                } else { Button("Connect") { settings = true } }
                Button { playback = true } label: { Image(systemName: "play.rectangle").frame(width: 44, height: 44) }
                    .disabled(anime.status == "NOT_YET_RELEASED").accessibilityLabel("Watch in VidHub")
            }
            Text("Tracking uses AniList’s episode numbering.").font(.caption2).foregroundStyle(.secondary)
            TrackingFeedback(anime: anime)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(12).background(.ultraThinMaterial)
            .sheet(isPresented: $editing) { TrackingEditorView(anime: anime, entry: store.entry(for: anime.id)) }
            .sheet(isPresented: $settings) { SettingsView() }
            .sheet(isPresented: $playback) { WatchAnimeView(anime: anime) }
    }
    private var busy: Bool { store.loadingLibrary || store.savedAt == nil || store.savingMedia.contains(anime.id) }
    private var atEnd: Bool { anime.episodes.map { $0 > 0 && (store.entry(for: anime.id)?.progressValue ?? 0) >= $0 } ?? false }
}
