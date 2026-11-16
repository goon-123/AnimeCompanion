import SwiftUI
import Combine
import CoreFoundation
import AnimeCore

@MainActor
final class DeviceSyncStore: ObservableObject {
    private static let bookmarkKey = "deviceSync.folderBookmark.v1"
    private static let deviceKey = "deviceSync.deviceID.v1"
    private static let vendorKey = "deviceSync.vendorID.v1"
    private static let checkedKey = "deviceSync.lastChecked.v1"
    @Published private(set) var connected = UserDefaults.standard.data(forKey: DeviceSyncStore.bookmarkKey) != nil
    @Published private(set) var folderName = ""
    @Published private(set) var syncing = false
    @Published private(set) var ready = false
    @Published private(set) var lastChecked = UserDefaults.standard.object(forKey: DeviceSyncStore.checkedKey) as? Date
    @Published private(set) var message: String?
    @Published private(set) var extensionNotice: String?
    @Published var error: String?
    private let files = DeviceSyncFiles()
    private let lifetime = AppDataSession()
    private var journal: DeviceSyncJournal?
    private var folder: URL?
    private struct Session {
        let app: AppStore
        let filters: DiscoveryFilterStore
        let playback: PlaybackStore
        let navigation: AppNavigationStore
        let extensions: MangaExtensionStore
        let reading: MangaReadingStore
        let links: MangaSourceLinkStore
    }
    private var session: Session?
    private var preparation: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []
    private var stopped = false
    private var active = false
    private lazy var scheduler = DeviceSyncScheduler { [weak self] in await self?.performSync() }

    func start(session stores: CompanionSessionStores) async {
        guard !stopped, lifetime.isCurrent else { return }
        if let preparation { await preparation.value; return }
        let session = Session(app: stores.app, filters: stores.filters, playback: stores.playback,
            navigation: stores.navigation, extensions: stores.extensions, reading: stores.reading, links: stores.links)
        self.session = session
        // Local preparation survives transient scene changes, so a quick
        // close/reopen cannot leave sync half-initialized until the next timer.
        let task = Task { [weak self] in
            guard let self else { return }
            await self.prepare(session)
        }
        preparation = task; await task.value
    }
    private func prepare(_ session: Session) async {
        await session.reading.load(); await session.links.load()
        await session.extensions.load(refreshCatalog: false)
        guard !stopped, lifetime.isCurrent else { return }
        do {
            let defaults = UserDefaults.standard
            let vendor = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
            // A restored iOS backup on a second device gets its own writer file.
            if defaults.string(forKey: Self.vendorKey) != vendor || defaults.string(forKey: Self.deviceKey) == nil {
                defaults.set(UUID().uuidString, forKey: Self.deviceKey); defaults.set(vendor, forKey: Self.vendorKey)
            }
            let id = defaults.string(forKey: Self.deviceKey)!
            journal = try await files.loadJournal(deviceID: id)
            if let bookmark = defaults.data(forKey: Self.bookmarkKey) {
                var stale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                folder = url; folderName = url.lastPathComponent
                if stale { try rememberFolder(url) }
            }
            ready = true
        } catch { self.error = "Sync could not resume: \(error.localizedDescription) Choose the folder again to reconnect."; ready = true }
        // Changes are collected even while a folder is offline. File-provider
        // operations never gate the launch screen or the local reader.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.schedule() }.store(in: &subscriptions)
        // @Published delivers in willSet. Queue observation until the new
        // value is installed, or the change check would see the old state.
        session.reading.$state.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.schedule() }.store(in: &subscriptions)
        session.links.$state.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.schedule() }.store(in: &subscriptions)
        session.extensions.$state.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.schedule() }.store(in: &subscriptions)
        session.playback.$progress.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.schedule() }.store(in: &subscriptions)
        if active && connected { scheduler.activate() }
    }
    func setActive(_ value: Bool) {
        guard !stopped else { return }
        active = value
        if value && ready && connected { scheduler.activate() }
        else { scheduler.deactivate() }
    }
    func stop() {
        stopped = true; scheduler.stop(); preparation?.cancel(); subscriptions.removeAll(); session = nil
    }
    func pause() async {
        guard !active, connected, !syncing, let session, journal != nil, lifetime.isCurrent else { return }
        do {
            journal!.observe(try snapshot(session))
            try await files.saveJournal(journal!)
        } catch { self.error = error.localizedDescription }
    }
    private func schedule() {
        guard connected, ready, active, !stopped else { return }
        if let session, let journal, let current = try? snapshot(session), current == journal.observed { return }
        scheduler.localChange()
    }
    func connect(_ url: URL) async {
        guard !syncing, !stopped else { return }
        scheduler.deactivate()
        syncing = true
        do {
            try lifetime.check(); try rememberFolder(url)
            // A newly selected folder starts with local seed values. Existing
            // cloud settings win on first connection; unique local books merge.
            let id = UserDefaults.standard.string(forKey: Self.deviceKey) ?? UUID().uuidString
            journal = DeviceSyncJournal(deviceID: id)
            try await files.saveJournal(journal!)
            folder = url; folderName = url.lastPathComponent; connected = true; error = nil
        } catch {
            self.error = error.localizedDescription; syncing = false
            if active && connected { scheduler.activate() }
            return
        }
        syncing = false
        if active { scheduler.activate(); await scheduler.waitForCurrentSync() }
    }
    func disconnect() {
        guard !syncing else { return }
        scheduler.deactivate(); folder = nil; connected = false; folderName = ""; message = nil; error = nil
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        // Both local data and shared snapshots remain available for recovery.
    }
    private func rememberFolder(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
    }
    func syncNow() async {
        scheduler.requestNow(); await scheduler.waitForCurrentSync()
    }
    private func performSync() async {
        guard ready, connected, let folder, let session, journal != nil, !stopped, lifetime.isCurrent else { return }
        guard !syncing, !Task.isCancelled else { return }
        syncing = true; error = nil; message = "Checking sync folder…"
        defer { syncing = false }
        do {
            let before = try snapshot(session)
            journal!.observe(before)
            try await files.saveJournal(journal!)
            let remote = try await files.readFolder(folder)
            try lifetime.check(); try Task.checkCancellation()
            let baseline = try snapshot(session)
            journal!.observe(baseline)
            for document in remote { try journal!.document.merge(document) }
            journal!.finishBootstrap()
            try journal!.document.validate()
            let desired = journal!.document.values
            // Persist pending remote values before attempting local writes or
            // package downloads, so interruption leaves a retryable journal.
            try await files.saveJournal(journal!)
            try await apply(expected: baseline, desired: desired, session: session)
            try lifetime.check()
            let actual = try snapshot(session)
            journal!.acceptApplied(actual, baseline: baseline, desired: desired)
            try await files.saveJournal(journal!)
            try await files.writeFolder(folder, journal: journal!)
            try lifetime.check(); try Task.checkCancellation()
            lastChecked = Date(); UserDefaults.standard.set(lastChecked, forKey: Self.checkedKey)
            message = "Changes saved to your sync folder."
        } catch is CancellationError { message = nil }
        catch { self.error = error.localizedDescription; message = "Local changes are kept and will retry while the app is open." }
    }
    func makeBackup() throws -> Data {
        guard let session, ready else { throw ServiceError.message("Local data is still loading. Try again in a moment.") }
        let data = try DeviceSyncCoding.encode(DeviceSyncBackup(values: snapshot(session)))
        guard data.count <= DeviceSyncCoding.maximumBytes else { throw DeviceSyncError.tooLarge }
        return data
    }
    func readBackup(_ url: URL) async throws -> DeviceSyncBackup { try await files.readBackup(url) }
    func restoreBackup(_ backup: DeviceSyncBackup) async {
        guard ready, !syncing, let session, !stopped else { return }
        syncing = true; error = nil
        defer { syncing = false; if active && connected { scheduler.requestNow() } }
        do {
            try lifetime.check()
            let baseline = try snapshot(session)
            if journal == nil {
                journal = DeviceSyncJournal(deviceID: UserDefaults.standard.string(forKey: Self.deviceKey) ?? UUID().uuidString)
            }
            journal!.observe(baseline)
            try journal!.restore(backup.values)
            let desired = baseline.merging(backup.values) { _, incoming in incoming }
            try await files.saveJournal(journal!)
            try await apply(expected: baseline, desired: desired, session: session)
            try lifetime.check()
            journal!.acceptApplied(try snapshot(session), baseline: baseline, desired: desired)
            try await files.saveJournal(journal!)
            message = "Backup merged. Your other local titles are kept."
        } catch { self.error = error.localizedDescription }
    }
    private func snapshot(_ session: Session) throws -> [String: Data] {
        guard !session.reading.loading, !session.reading.unreadable, !session.links.loading, !session.links.unreadable,
              !session.extensions.loading, !session.extensions.unreadableState else {
            throw ServiceError.message("Local data could not be read yet. Reopen the app before syncing; existing files are kept.")
        }
        var payload = DeviceSyncPayload()
        payload.reading = session.reading.state; payload.links = session.links.state
        payload.repositoryAdded = session.extensions.state.repositoryAdded
        for entry in session.extensions.state.installations {
            payload.extensions[entry.id] = DeviceSyncMangaExtension(descriptor: entry.descriptor, enabled: entry.enabled)
        }
        payload.playback = session.playback.progress
        let defaults = UserDefaults.standard
        for key in DeviceSyncPreferences.keys {
            guard let value = defaults.object(forKey: key) else { continue }
            if let data = value as? Data { payload.preferences[key] = .data(data) }
            else if let string = value as? String { payload.preferences[key] = .string(string) }
            else if let number = value as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() { payload.preferences[key] = .bool(number.boolValue) }
                else if String(cString: number.objCType).contains("f") || String(cString: number.objCType).contains("d") {
                    payload.preferences[key] = .decimal(number.doubleValue)
                } else { payload.preferences[key] = .integer(number.intValue) }
            }
        }
        return try payload.encodedValues()
    }
    private func apply(expected: [String: Data], desired: [String: Data], session: Session) async throws {
        let decoded = try DeviceSyncPayload(values: desired)
        try lifetime.check()
        if expected.filter({ $0.key.hasPrefix("book.") || $0.key.hasPrefix("reader.") }) != desired.filter({ $0.key.hasPrefix("book.") || $0.key.hasPrefix("reader.") }) {
            try await session.reading.applyDeviceSync(expected: expected, desired: desired)
        }
        if expected.filter({ $0.key.hasPrefix("link.") }) != desired.filter({ $0.key.hasPrefix("link.") }) {
            try await session.links.applyDeviceSync(expected: expected, desired: desired)
        }
        try lifetime.check()
        if expected.filter({ $0.key.hasPrefix("playback.") }) != desired.filter({ $0.key.hasPrefix("playback.") }) {
            try session.playback.applyDeviceSync(expected: expected, desired: desired)
        }
        // Recheck the live defaults after actor hops, and apply only unchanged
        // fields. @AppStorage then updates all already-mounted pages.
        let current = try snapshot(session)
        let patched = DeviceSyncPayload.patch(current: current, expected: expected, desired: desired)
        let defaults = UserDefaults.standard
        var changedPreferences = false
        for key in DeviceSyncPreferences.keys where patched["preference." + key] != current["preference." + key] {
            try lifetime.check()
            changedPreferences = true
            guard let data = patched["preference." + key] else { defaults.removeObject(forKey: key); continue }
            switch try DeviceSyncCoding.decode(DeviceSyncPreference.self, data) {
            case .string(let value): defaults.set(value, forKey: key)
            case .bool(let value): defaults.set(value, forKey: key)
            case .integer(let value): defaults.set(value, forKey: key)
            case .decimal(let value): defaults.set(value, forKey: key)
            case .data(let value): defaults.set(value, forKey: key)
            }
        }
        if changedPreferences {
            session.app.includeAdult = defaults.bool(forKey: "content.includeAdult")
            session.app.mangaBakaContent = MangaBakaContentFilter(saved: defaults.string(forKey: MangaBakaContentFilter.storageKey), legacyIncludeAdult: session.app.includeAdult)
            session.app.automaticallyComplete = defaults.object(forKey: "tracking.automaticallyComplete") as? Bool ?? true
            session.app.airingProgressSource = AiringProgressSource(rawValue: defaults.string(forKey: "library.airingProgressSource") ?? "") ?? .broadcast
            session.filters.reloadSyncedPreferences(); session.playback.reloadSyncedPreferences()
            if !session.navigation.settingsPresented {
                session.navigation.applyLayoutPreference(); session.navigation.applyTabPreferences()
            }
        }
        message = "Restoring extension setup…"
        extensionNotice = await session.extensions.applyDeviceSync(expected: expected, desired: desired, payload: decoded)
    }
}
