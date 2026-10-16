import SwiftUI
import AnimeCore

struct TorBoxSettingsView: View {
    @EnvironmentObject private var seanime: SeanimeStore
    @State private var key = ""
    @State private var busy = false
    @State private var notice: String?
    @State private var failed = false
    @State private var files = false
    @State private var removeConfirmed = false
    @State private var work: Task<Void, Never>?
    @FocusState private var editing: Bool
    var body: some View {
        Form {
            Section {
                Label(seanime.hasTorBoxKey ? "API key saved" : "Not connected", systemImage: seanime.hasTorBoxKey ? "checkmark.circle.fill" : "cloud")
                    .foregroundStyle(seanime.hasTorBoxKey ? Color.mint : .secondary)
                Button { editing = false; files = true } label: { Label("Browse TorBox files", systemImage: "folder") }
                    .accessibilityIdentifier("torbox-webdav-browse")
                Button("Verify connection") {
                    editing = false; busy = true; notice = nil; failed = false
                    work = Task { defer { busy = false }
                        do { try await seanime.torBox().verify(); try Task.checkCancellation(); notice = "TorBox connected. No torrents were added." }
                        catch is CancellationError {} catch { failed = true; notice = error.localizedDescription }
                    }
                }.disabled(!seanime.hasTorBoxKey || busy).accessibilityIdentifier("torbox-verify")
                if busy { ProgressView("Checking connection…") }
                if let notice { Text(notice).font(.subheadline).foregroundStyle(failed ? Color.orange : .secondary).accessibilityIdentifier("seanime-notice") }
                if let error = seanime.error { Text(error).foregroundStyle(.orange) }
            }
            Section {
                SecureField(seanime.hasTorBoxKey ? "Paste replacement API key" : "TorBox API key", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($editing)
                    .submitLabel(.done).onSubmit { editing = false }.accessibilityIdentifier("torbox-api-key")
                Button(seanime.hasTorBoxKey ? "Update TorBox key" : "Save TorBox key") {
                    if seanime.saveKey(key) { key = ""; editing = false; failed = false; notice = "TorBox key saved." }
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy).accessibilityIdentifier("torbox-save-key")
                Link("Find your API key", destination: URL(string: "https://torbox.app/settings")!)
            } header: { Text("Connection") } footer: { Text("Stored securely on this device. Seanime extensions never receive your key. Changing it clears local torrent references, not cloud files.") }
            Section("Help & account") {
                Link("Open TorBox dashboard", destination: URL(string: "https://torbox.app")!)
                Link("WebDAV help", destination: URL(string: "https://support.torbox.app/en/articles/14662867-torbox-webdav")!)
                if seanime.hasTorBoxKey {
                    Button("Disconnect TorBox", role: .destructive) { removeConfirmed = true }.disabled(busy)
                }
            }
        }.navigationTitle("TorBox").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $files) { TorBoxFilesView() }
            .confirmationDialog("Disconnect TorBox on this device?", isPresented: $removeConfirmed, titleVisibility: .visible) {
                Button("Disconnect TorBox", role: .destructive) { if seanime.saveKey("") { key = ""; notice = "TorBox disconnected. Cloud files were not deleted." } }
            } message: { Text("Removes your saved key and local torrent references. Your TorBox cloud files stay in your account.") }
            .onDisappear { work?.cancel(); key = "" }
    }
}
