import SwiftUI
import UniformTypeIdentifiers
import AnimeCore

struct DeviceSyncSettingsView: View {
    @EnvironmentObject private var sync: DeviceSyncStore
    private enum ImportChoice { case folder, backup }
    @State private var importChoice = ImportChoice.folder
    @State private var exporting = false
    @State private var importing = false
    @State private var readingBackup = false
    @State private var confirmRestore = false
    @State private var confirmDisconnect = false
    @State private var backup = SyncBackupFile()
    @State private var incoming: DeviceSyncBackup?
    var body: some View {
        Form {
            Section {
                Label("Your setup, on every device", systemImage: "icloud")
                    .font(.headline)
                Text("Automatic iCloud creates and reconnects your sync folder for you. If your copy needs Files permission, choose a folder once and the app creates its sync folder inside it.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Automatic sync", value: "On launch & return")
                Button { Task { await sync.connectAutomatically() } } label: {
                    Label(sync.location == .automatic ? "Reconnect Automatic iCloud" : "Enable Automatic iCloud", systemImage: "icloud")
                }.disabled(!sync.ready || sync.syncing).accessibilityIdentifier("device-sync-automatic")
                Button { importChoice = .folder; importing = true } label: {
                    Label(sync.connected ? "Choose a Files Folder Instead" : "Use a Files Folder", systemImage: "folder.badge.plus")
                }.disabled(!sync.ready || sync.syncing).accessibilityIdentifier("device-sync-choose-folder")
                if sync.connected {
                    LabeledContent("Folder", value: sync.folderName.isEmpty ? "Reconnect to continue" : sync.folderName)
                    if let date = sync.lastChecked { LabeledContent("Last checked") { Text(date, style: .relative).foregroundStyle(.secondary) } }
                    Button { Task { await sync.syncNow() } } label: {
                        HStack { Label("Sync Now", systemImage: "arrow.triangle.2.circlepath"); Spacer(); if sync.syncing { ProgressView() } }
                    }.disabled(sync.syncing || !sync.ready).accessibilityIdentifier("device-sync-now")
                    Button("Disconnect This Device", role: .destructive) { confirmDisconnect = true }.disabled(sync.syncing)
                        .accessibilityIdentifier("device-sync-disconnect")
                }
                if let message = sync.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                if let error = sync.setupError { Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.orange).accessibilityIdentifier("device-sync-setup-error") }
                if let error = sync.error { Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.orange).accessibilityIdentifier("device-sync-error") }
                if let notice = sync.extensionNotice { Text(notice).font(.footnote).foregroundStyle(.orange) }
            } header: { Text("Sync connection") } footer: {
                Text("Use Automatic iCloud on both devices with the same iCloud account. Some sideloaded copies need a one-time Files folder permission instead: select the same writable folder in iCloud Drive on both devices. An On My iPhone folder is local only. Disconnecting keeps your local data and cloud files.")
            }
            Section {
                Label("Settings, theme, layouts & widgets", systemImage: "slider.horizontal.3")
                Label("Local manga library & saved sources", systemImage: "books.vertical")
                Label("Chapter progress & reader preferences", systemImage: "bookmark")
                Label("MangaBaka reading-source links", systemImage: "link")
                Label("Manga extensions & enabled status", systemImage: "puzzlepiece.extension")
                Label("Video player choice & resume positions", systemImage: "play.rectangle")
            } header: { Text("Included") } footer: {
                Text("Extensions download again and are verified on each device. Account sign-ins, API keys, private source settings, configured video add-ons, website sessions and offline downloads stay on this device. AniList and MangaBaka continue syncing their online libraries through their own accounts.")
            }
            Section {
                Button {
                    do { backup = SyncBackupFile(data: try sync.makeBackup()); exporting = true }
                    catch { sync.error = error.localizedDescription }
                } label: { Label("Export Backup", systemImage: "square.and.arrow.up") }
                    .disabled(!sync.ready || sync.syncing).accessibilityIdentifier("device-sync-export")
                Button { importChoice = .backup; importing = true } label: {
                    HStack { Label("Merge a Backup", systemImage: "square.and.arrow.down"); Spacer(); if readingBackup { ProgressView() } }
                }.disabled(!sync.ready || sync.syncing || readingBackup).accessibilityIdentifier("device-sync-import")
            } header: { Text("Portable backup") } footer: {
                Text("Save a separate backup in Files or send it with AirDrop. Importing merges the included settings and titles into this device and, if connected, its sync folder. Other local titles are kept. Backups contain library titles and preferences; choose a private folder.")
            }
        }.navigationTitle("Sync & backup").navigationBarTitleDisplayMode(.inline)
            .fileExporter(isPresented: $exporting, document: backup, contentType: .json,
                          defaultFilename: "Next-Backup-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
                if case .failure(let error) = result { sync.error = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: importChoice == .folder ? [.folder] : [.json], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    if importChoice == .folder {
                        do {
                            let bookmark = try DeviceSyncFiles.bookmarkSelection(url)
                            Task { await sync.connect(bookmark: bookmark) }
                        } catch { sync.setupError = error.localizedDescription }
                        return
                    }
                    readingBackup = true
                    Task {
                        defer { readingBackup = false }
                        do { incoming = try await sync.readBackup(url); confirmRestore = true }
                        catch { sync.error = error.localizedDescription }
                    }
                case .failure(let error): sync.error = error.localizedDescription
                }
            }
            .confirmationDialog("Merge this backup?", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("Merge Backup") { if let incoming { Task { await sync.restoreBackup(incoming) } }; incoming = nil }
                Button("Cancel", role: .cancel) { incoming = nil }
            } message: {
                if let incoming, let payload = try? DeviceSyncPayload(values: incoming.values) {
                    Text("Backup from \(incoming.createdAt.formatted(date: .abbreviated, time: .shortened)): \(payload.reading.records.count) manga titles, \(payload.extensions.count) extensions and \(payload.preferences.count) preferences. Its included values replace matching local values and can sync to your other devices.")
                }
            }
            .confirmationDialog("Disconnect this device?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { sync.disconnect() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Local data and the files in your sync folder are kept. Other devices can continue syncing.") }
    }
}
private struct SyncBackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data = Data()
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
