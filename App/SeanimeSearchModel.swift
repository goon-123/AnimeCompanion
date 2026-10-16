import SwiftUI
import AnimeCore

@MainActor
final class SeanimeSearchModel: ObservableObject {
    struct Choice: Identifiable {
        let provider: SeanimeInstallation
        let torrent: SeanimeTorrent
        var id: String { "\(provider.id)-\(torrent.id)" }
    }
    @Published var query = ""
    @Published var selected: String?
    @Published private(set) var providerID: UUID?
    @Published private(set) var providers: [SeanimeInstallation] = []
    @Published private(set) var results: [Choice] = []
    @Published private(set) var errors: [String] = []
    @Published private(set) var remaining = 0
    @Published private(set) var searched = false
    var loading: Bool { remaining > 0 }
    private var client = SeanimeClient()
    private var anime: Anime?
    private var allowAdult = false
    private var pending: [SeanimeInstallation] = []
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var runners: [UUID: SeanimeRunner] = [:]
    private var lookupID = UUID()

    func configure(store: SeanimeStore, anime: Anime?, allowAdult: Bool) {
        stop(); results = []; errors = []; selected = nil; searched = false
        if self.anime?.id != anime?.id || query.isEmpty { query = anime?.title?.romaji ?? anime?.displayTitle ?? "" }
        self.anime = anime; self.allowAdult = allowAdult; client = store.client
        providers = store.installations.filter { $0.enabled && (allowAdult || !$0.adult) }
        if !providers.contains(where: { $0.id == providerID }) { providerID = nil }
    }
    func selectProvider(_ id: UUID?) { providerID = id; search() }
    func stop() {
        lookupID = UUID(); pending = []
        tasks.values.forEach { $0.cancel() }; runners.values.forEach { $0.cancel() }
        tasks = [:]; runners = [:]; remaining = 0
    }
    func search() {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        stop(); errors = []; results = []; selected = nil; searched = true
        pending = providers.filter { providerID == nil || $0.id == providerID }; remaining = pending.count
        startNext(query: value, expected: lookupID)
    }
    private func startNext(query: String, expected: UUID) {
        guard lookupID == expected else { return }
        while tasks.count < 2, !pending.isEmpty {
            let provider = pending.removeFirst()
            let engine = SeanimeRunner(client: client); runners[provider.id] = engine
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
                    results += values.map { Choice(provider: provider, torrent: $0) }
                    if let warning = engine.warning { errors.append("\(provider.manifest.name): \(warning)") }
                } catch is CancellationError {} catch {
                    if lookupID == expected { errors.append("\(provider.manifest.name): \(error.localizedDescription)") }
                }
            }
        }
    }
}
