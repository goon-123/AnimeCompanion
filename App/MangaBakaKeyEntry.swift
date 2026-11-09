import SwiftUI
import AnimeCore

/// The same single-field connection flow is used during setup and in Accounts.
struct MangaBakaKeyEntry: View {
    @EnvironmentObject private var account: MangaBakaStore
    @State private var apiKey = ""
    @FocusState private var keyFocused: Bool
    private var busy: Bool { account.connecting || !account.saving.isEmpty }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Link(destination: URL(string: "https://mangabaka.org/my/settings/api-and-apps")!) {
                Label("Create a MangaBaka API key", systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.semibold))
            }.accessibilityIdentifier("mangabaka-create-key")
            Text("Sign in on MangaBaka, choose New token under Personal access tokens, then paste your key here.")
                .font(.caption).foregroundStyle(.secondary)
            SecureField("Paste your MangaBaka API key", text: $apiKey)
                .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                .textContentType(nil).focused($keyFocused).submitLabel(.go)
                .padding(14).background(Theme.secondarySurface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("mangabaka-api-key").onSubmit { connect() }
            Button(action: connect) {
                HStack(spacing: 8) {
                    if account.connecting { ProgressView().controlSize(.small) }
                    Text(account.connecting ? "Connecting…" : "Connect MangaBaka").fontWeight(.semibold)
                }.frame(maxWidth: .infinity, minHeight: 46)
            }.buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                .accessibilityIdentifier("mangabaka-add-account")
            if let error = account.accountError { Text(error).font(.caption).foregroundStyle(.orange) }
            Label("Your key stays in this device’s Keychain.", systemImage: "lock.fill")
                .font(.caption2).foregroundStyle(.secondary)
        }.onDisappear { apiKey = "" }
    }
    private func connect() {
        guard !busy, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let value = apiKey; apiKey = ""; keyFocused = false
        Task { await account.connect(apiKey: value) }
    }
}
