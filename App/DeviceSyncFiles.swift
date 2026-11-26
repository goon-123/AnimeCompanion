import Foundation
import AnimeCore

/// File coordination runs off the UI actor. Only our dedicated subfolder and
/// this installation's snapshot are written; other devices' files are read-only.
actor DeviceSyncFiles {
    private let lifetime = AppDataSession()
    private let journalURL: URL
    init(journalDirectory: URL? = nil) {
        let directory = journalDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeviceSync", isDirectory: true)
        journalURL = directory.appendingPathComponent("journal.json")
    }
    struct CloudFolder: Sendable { let url: URL; let identity: Data }
    /// The default container is selected from the entitlements of the actual
    /// installed signature. This API returns nil when iCloud access is absent.
    /// Never guess an iCloud path or fall back to this app's local Documents.
    func automaticFolder(matching previousIdentity: Data? = nil) throws -> CloudFolder {
        try lifetime.check()
        let manager = FileManager.default
        guard let token = manager.ubiquityIdentityToken,
              let container = manager.url(forUbiquityContainerIdentifier: nil) else {
            throw SyncFileError.automaticUnavailable
        }
        if let previousIdentity { try checkCloudIdentity(previousIdentity) }
        let identity = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
        let documents = try coordinated(container, writing: true) { root in
            let documents = root.appendingPathComponent("Documents", isDirectory: true)
            try lifetime.perform { try manager.createDirectory(at: documents, withIntermediateDirectories: true) }
            return documents
        }
        return CloudFolder(url: documents, identity: previousIdentity ?? identity)
    }
    nonisolated static func bookmarkSelection(_ url: URL) throws -> Data {
        // Capture the grant in the importer callback, before its presentation
        // disappears. Later work resolves this persisted security-scoped URL.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw SyncFileError.notFolder }
        return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    func resolveBookmark(_ data: Data) throws -> (url: URL, refreshed: Data) {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale ? try Self.bookmarkSelection(url) : data)
    }
    func validateFolder(_ folder: URL, identity: Data? = nil) throws {
        try lifetime.check(); try checkCloudIdentity(identity)
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        try coordinated(folder, writing: true) { parent in
            guard try parent.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw SyncFileError.notFolder }
            // Enumerating first distinguishes a missing child from denied
            // access. fileExists alone silently treats both as an empty cloud.
            _ = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
            let root = parent.appendingPathComponent("AnimeCompanion Sync", isDirectory: true)
            try lifetime.perform { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
            let probe = root.appendingPathComponent(".access-" + UUID().uuidString)
            try checkCloudIdentity(identity)
            do {
                try lifetime.write(Data("sync".utf8), to: probe)
                try FileManager.default.removeItem(at: probe)
            } catch { throw SyncFileError.notWritable }
        }
    }
    func loadJournal(deviceID: String) throws -> DeviceSyncJournal {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return DeviceSyncJournal(deviceID: deviceID) }
        let data = try Data(contentsOf: journalURL)
        guard data.count <= DeviceSyncCoding.maximumBytes * 3 else { throw DeviceSyncError.tooLarge }
        let saved = try JSONDecoder().decode(DeviceSyncJournal.self, from: data)
        guard saved.deviceID == deviceID else { return DeviceSyncJournal(deviceID: deviceID) }
        try saved.document.validate(); _ = try DeviceSyncPayload(values: saved.observed)
        return saved
    }
    func saveJournal(_ journal: DeviceSyncJournal) throws {
        try lifetime.perform {
            let data = try DeviceSyncCoding.encode(journal)
            guard data.count <= DeviceSyncCoding.maximumBytes * 3 else { throw DeviceSyncError.tooLarge }
            try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try lifetime.write(data, to: journalURL)
        }
    }
    func removeJournal() throws {
        try lifetime.perform {
            if FileManager.default.fileExists(atPath: journalURL.path) { try FileManager.default.removeItem(at: journalURL) }
        }
    }
    func readFolder(_ folder: URL, identity: Data? = nil) throws -> [DeviceSyncDocument] {
        try lifetime.check(); try Task.checkCancellation()
        try checkCloudIdentity(identity)
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let children = try coordinated(folder, writing: false) { parent in
            try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey])
        }
        guard let root = children.first(where: { $0.lastPathComponent == "AnimeCompanion Sync" }) else {
            if children.contains(where: { $0.lastPathComponent == ".AnimeCompanion Sync.icloud" }) { throw SyncFileError.downloading }
            return []
        }
        let urls = try coordinated(root, writing: false) { url -> [URL] in
            try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        }
        // Some iCloud providers enumerate evicted files as hidden .icloud
        // placeholders. Request them, and defer the whole pass until readable.
        for url in urls where url.lastPathComponent.hasSuffix(".nextsync.icloud") {
            let name = String(url.lastPathComponent.dropFirst().dropLast(7))
            try? FileManager.default.startDownloadingUbiquitousItem(at: root.appendingPathComponent(name))
            throw SyncFileError.downloading
        }
        let snapshots = urls.filter { $0.pathExtension == "nextsync" }
        guard snapshots.count <= 64 else { throw DeviceSyncError.tooLarge }
        var documents: [DeviceSyncDocument] = []
        for url in snapshots {
            try Task.checkCancellation(); try lifetime.check()
            documents.append(try DeviceSyncDocument.read(read(url)))
            for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] {
                documents.append(try DeviceSyncDocument.read(read(version.url)))
            }
        }
        return documents
    }
    func writeFolder(_ folder: URL, journal: DeviceSyncJournal, identity: Data? = nil) throws {
        try lifetime.check(); try Task.checkCancellation()
        try checkCloudIdentity(identity)
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let data = try DeviceSyncCoding.encode(journal.document)
        guard data.count <= DeviceSyncCoding.maximumBytes else { throw DeviceSyncError.tooLarge }
        let root = try coordinated(folder, writing: true) { parent in
            try checkCloudIdentity(identity)
            let root = parent.appendingPathComponent("AnimeCompanion Sync", isDirectory: true)
            try lifetime.perform { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
            return root
        }
        let file = root.appendingPathComponent(journal.deviceID + ".nextsync")
        try coordinated(file, writing: true) { target in
            try checkCloudIdentity(identity)
            try lifetime.write(data, to: target)
        }
    }
    func readBackup(_ url: URL) throws -> DeviceSyncBackup {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try DeviceSyncBackup.read(read(url))
    }
    private func read(_ url: URL) throws -> Data {
        try coordinated(url, writing: false) { item in
            let resource = try item.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard resource.isRegularFile == true, resource.isSymbolicLink != true else { throw DeviceSyncError.invalid }
            guard (resource.fileSize ?? 0) <= DeviceSyncCoding.maximumBytes else { throw DeviceSyncError.tooLarge }
            return try Data(contentsOf: item)
        }
    }
    private func checkCloudIdentity(_ expected: Data?) throws {
        guard let expected else { return }
        guard let token = FileManager.default.ubiquityIdentityToken else { throw SyncFileError.automaticUnavailable }
        let saved = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(expected)
        guard let saved, token.isEqual(saved) else { throw SyncFileError.accountChanged }
    }
    private func coordinated<T>(_ url: URL, writing: Bool, _ body: (URL) throws -> T) throws -> T {
        var error: NSError?
        var result: Result<T, Error>?
        let coordinator = NSFileCoordinator()
        if writing {
            coordinator.coordinate(writingItemAt: url, options: [], error: &error) { item in result = Result { try body(item) } }
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &error) { item in result = Result { try body(item) } }
        }
        if let error { throw error }
        guard let result else { throw SyncFileError.access }
        return try result.get()
    }
}

enum SyncFileError: LocalizedError {
    case access, downloading, automaticUnavailable, accountChanged, notFolder, notWritable
    var errorDescription: String? {
        switch self {
        case .access: return "The sync folder is unavailable. Check Files or choose the folder again. Your local data is kept."
        case .downloading: return "iCloud Drive is downloading your sync files. The app will try again while open."
        case .automaticUnavailable: return "Automatic iCloud is unavailable in this copy of the app. Turn on iCloud Drive in iPhone Settings. If it is already on, the app needs signing with iCloud enabled. You can use a Files folder instead."
        case .accountChanged: return "The iCloud account changed. Sync is paused. Tap Enable Automatic iCloud again to connect this account; your local data is kept."
        case .notFolder: return "Choose a folder in Files, rather than a file. The app will create its sync folder inside it."
        case .notWritable: return "This folder does not allow writing. Choose a writable folder in iCloud Drive. Your previous sync connection is kept."
        }
    }
}
