import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AnimeCore

struct DeviceSyncSettingsView: View {
    @EnvironmentObject private var sync: DeviceSyncStore
    @State private var choosingFolder = false
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
                Text("Choose the same folder in iCloud Drive on your iPhone and iPad. Changes merge automatically while the app is open, including changes made offline.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Sync folder") {
                if sync.connected {
                    LabeledContent("Folder", value: sync.folderName.isEmpty ? "Reconnect to continue" : sync.folderName)
                    if let date = sync.lastChecked { LabeledContent("Last checked") { Text(date, style: .relative).foregroundStyle(.secondary) } }
                    Button { Task { await sync.syncNow() } } label: {
                        HStack { Label("Sync Now", systemImage: "arrow.triangle.2.circlepath"); Spacer(); if sync.syncing { ProgressView() } }
                    }.disabled(sync.syncing || !sync.ready).accessibilityIdentifier("device-sync-now")
                    Button("Choose Another Folder") { choosingFolder = true }.disabled(sync.syncing || !sync.ready)
                    Button("Disconnect This Device", role: .destructive) { confirmDisconnect = true }.disabled(sync.syncing)
                        .accessibilityIdentifier("device-sync-disconnect")
                } else {
                    Button { choosingFolder = true } label: { Label("Choose iCloud Drive Folder", systemImage: "folder.badge.plus") }
                        .disabled(!sync.ready || sync.syncing).accessibilityIdentifier("device-sync-choose-folder")
                }
                if let message = sync.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                if let error = sync.error { Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.orange).accessibilityIdentifier("device-sync-error") }
                if let notice = sync.extensionNotice { Text(notice).font(.footnote).foregroundStyle(.orange) }
            } footer: {
                Text("In Files, create a folder such as Next Sync in iCloud Drive, then select it on each device. An On My iPhone folder is local only. iCloud Drive controls when files reach your other devices; leave both apps open to sync. Disconnecting keeps your local data and the backup folder.")
            }
            Section("Included") {
                Label("Settings, theme, layouts & widgets", systemImage: "slider.horizontal.3")
                Label("Local manga library & saved sources", systemImage: "books.vertical")
                Label("Chapter progress & reader preferences", systemImage: "bookmark")
                Label("MangaBaka reading-source links", systemImage: "link")
                Label("Manga extensions & enabled status", systemImage: "puzzlepiece.extension")
                Label("Video player choice & resume positions", systemImage: "play.rectangle")
            } footer: {
                Text("Extensions download again and are verified on each device. Account sign-ins, API keys, private source settings, configured video add-ons, website sessions and offline downloads stay on this device. AniList and MangaBaka continue syncing their online libraries through their own accounts.")
            }
            Section("Portable backup") {
                Button {
                    do { backup = SyncBackupFile(data: try sync.makeBackup()); exporting = true }
                    catch { sync.error = error.localizedDescription }
                } label: { Label("Export Backup", systemImage: "square.and.arrow.up") }
                    .disabled(!sync.ready || sync.syncing).accessibilityIdentifier("device-sync-export")
                Button { importing = true } label: {
                    HStack { Label("Merge a Backup", systemImage: "square.and.arrow.down"); Spacer(); if readingBackup { ProgressView() } }
                }.disabled(!sync.ready || sync.syncing || readingBackup).accessibilityIdentifier("device-sync-import")
            } footer: {
                Text("Save a separate backup in Files or send it with AirDrop. Importing merges the included settings and titles into this device and, if connected, its sync folder. Other local titles are kept. Backups contain library titles and preferences; choose a private folder.")
            }
        }.navigationTitle("Sync & backup").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $choosingFolder) {
                SyncFolderPicker { url in choosingFolder = false; Task { await sync.connect(url) } }
            }
            .fileExporter(isPresented: $exporting, document: backup, contentType: .json,
                          defaultFilename: "Next-Backup-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
                if case .failure(let error) = result { sync.error = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
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

private struct SyncFolderPicker: UIViewControllerRepresentable {
    let picked: (URL) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(picked: picked) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false; picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let picked: (URL) -> Void
        init(picked: @escaping (URL) -> Void) { self.picked = picked }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { picked(url) }
        }
    }
}
