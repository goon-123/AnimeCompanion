import Foundation
import AnimeCore

/// File coordination runs off the UI actor. Only our dedicated subfolder and
/// this installation's snapshot are written; other devices' files are read-only.
actor DeviceSyncFiles {
    private let lifetime = AppDataSession()
    private let journalURL: URL
    init() {
        journalURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeviceSync", isDirectory: true).appendingPathComponent("journal.json")
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
    func readFolder(_ folder: URL) throws -> [DeviceSyncDocument] {
        try lifetime.check(); try Task.checkCancellation()
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let root = folder.appendingPathComponent("AnimeCompanion Sync", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
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
    func writeFolder(_ folder: URL, journal: DeviceSyncJournal) throws {
        try lifetime.check(); try Task.checkCancellation()
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let data = try DeviceSyncCoding.encode(journal.document)
        guard data.count <= DeviceSyncCoding.maximumBytes else { throw DeviceSyncError.tooLarge }
        let root = folder.appendingPathComponent("AnimeCompanion Sync", isDirectory: true)
        try coordinated(folder, writing: true) { _ in
            try lifetime.perform { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        }
        let file = root.appendingPathComponent(journal.deviceID + ".nextsync")
        try coordinated(file, writing: true) { target in try lifetime.write(data, to: target) }
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
    case access, downloading
    var errorDescription: String? {
        switch self {
        case .access: return "The sync folder is unavailable. Check Files or choose the folder again. Your local data is kept."
        case .downloading: return "iCloud Drive is downloading your sync files. The app will try again while open."
        }
    }
}
