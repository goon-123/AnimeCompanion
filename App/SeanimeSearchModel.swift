import SwiftUI
import AnimeCore

@MainActor
final class SeanimeSearchModel: ObservableObject {
    struct Choice: Identifiable {
        let provider: SeanimeInstallation
        let torrent: SeanimeTorrent
        let audio: StreamAudioInfo
        var id: String { "\(provider.id)-\(torrent.id)" }
        init(provider: SeanimeInstallation, torrent: SeanimeTorrent) {
            self.provider = provider; self.torrent = torrent
            audio = StreamAudioInfo(texts: [torrent.name])
        }
    }
    enum ProviderState: Equatable {
        case queued, searching, complete(Int), failed(String), paused, cancelled
        var label: String {
            switch self {
            case .queued: return "Waiting"
            case .searching: return "Searching…"
            case .complete(let count): return "\(count) \(count == 1 ? "release" : "releases")"
            case .failed: return "Search failed"
            case .paused: return "Paused · resumes on return"
            case .cancelled: return "Cancelled"
            }
        }
        var symbol: String {
            switch self {
            case .queued: return "clock"
            case .searching: return "magnifyingglass"
            case .complete: return "checkmark.circle"
            case .failed: return "exclamationmark.triangle"
            case .paused, .cancelled: return "pause.circle"
            }
        }
        var failed: Bool { if case .failed = self { return true }; return false }
    }
    @Published var query = ""
    @Published var selected: String?
    @Published private(set) var providerID: UUID?
    @Published private(set) var providers: [SeanimeInstallation] = []
    @Published private(set) var results: [Choice] = []
    @Published private(set) var states: [UUID: ProviderState] = [:]
    @Published private(set) var warnings: [UUID: String] = [:]
    @Published private(set) var remaining = 0
    @Published private(set) var searched = false
    var loading: Bool { remaining > 0 }
    var errors: [String] {
        providers.compactMap { provider in
            if case .failed(let message)? = states[provider.id] { return "\(provider.manifest.name): \(message)" }
            return warnings[provider.id].map { "\(provider.manifest.name): \($0)" }
        }
    }
    private var client = SeanimeClient()
    private var anime: Anime?
    private var allowAdult = false
    private var pending: [SeanimeInstallation] = []
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var runners: [UUID: SeanimeRunner] = [:]
    private var lookupID = UUID()
    private var interrupted: Set<UUID> = []
    private var interruptedQuery: String?

    func configure(store: SeanimeStore, anime: Anime?, allowAdult: Bool) {
        stop(); results = []; states = [:]; warnings = [:]; selected = nil; searched = false
        if self.anime?.id != anime?.id || query.isEmpty { query = anime?.title?.romaji ?? anime?.displayTitle ?? "" }
        self.anime = anime; self.allowAdult = allowAdult; client = store.client
        providers = store.installations.filter { $0.enabled && (allowAdult || !$0.adult) }
        if !providers.contains(where: { $0.id == providerID }) { providerID = nil }
    }
    func selectProvider(_ id: UUID?) { providerID = id; search() }
    func stop() {
        for (id, state) in states where state == .queued || state == .searching || state == .paused { states[id] = .cancelled }
        interrupted = []; interruptedQuery = nil; cancelWork()
    }
    /// Background suspension can interrupt WebKit. Keep completed providers and
    /// restart only unfinished providers when this visible screen becomes active.
    func pause() {
        guard loading else { return }
        interrupted = Set(tasks.keys).union(pending.map(\.id))
        interruptedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        for id in interrupted { states[id] = .paused }
        cancelWork()
    }
    func resumeIfNeeded() {
        guard !interrupted.isEmpty else { return }
        guard interruptedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines) else { stop(); return }
        pending = providers.filter { interrupted.contains($0.id) }
        interrupted = []; interruptedQuery = nil
        for provider in pending { states[provider.id] = .queued }
        remaining = pending.count
        startNext(query: query.trimmingCharacters(in: .whitespacesAndNewlines), expected: lookupID)
    }
    private func cancelWork() {
        lookupID = UUID(); pending = []
        tasks.values.forEach { $0.cancel() }; runners.values.forEach { $0.cancel() }
        tasks = [:]; runners = [:]; remaining = 0
    }
    func search() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        stop(); states = [:]; warnings = [:]; results = []; selected = nil; searched = true
        pending = providers.filter { providerID == nil || $0.id == providerID }
        for provider in pending { states[provider.id] = .queued }
        remaining = pending.count
        startNext(query: value, expected: lookupID)
    }
    private func startNext(query: String, expected: UUID) {
        guard lookupID == expected else { return }
        while tasks.count < 2, !pending.isEmpty {
            let provider = pending.removeFirst()
            let engine = SeanimeRunner(client: client); runners[provider.id] = engine
            states[provider.id] = .searching
            tasks[provider.id] = Task {
                defer {
                    if lookupID == expected {
                        tasks[provider.id] = nil; runners[provider.id] = nil
                        remaining = tasks.count + pending.count
                        startNext(query: query, expected: expected)
                    }
                }
                do {
                    let values = try await engine.search(provider, query: query, anime: anime, allowAdult: allowAdult)
                    try Task.checkCancellation(); guard lookupID == expected else { return }
                    var seen = Set<String>()
                    let choices = values.map { Choice(provider: provider, torrent: $0) }.filter { seen.insert($0.id).inserted }
                    results.removeAll { $0.provider.id == provider.id }; results += choices
                    states[provider.id] = .complete(choices.count)
                    if let warning = engine.warning { warnings[provider.id] = warning }
                } catch is CancellationError {} catch {
                    if lookupID == expected { states[provider.id] = .failed(error.localizedDescription) }
                }
            }
        }
    }
}
