import SwiftUI
import WebKit
import AnimeCore

struct ExtensionSourcePreferencesView: View {
    @EnvironmentObject private var store: UnifiedExtensionStore
    @Environment(\.dismiss) private var dismiss
    let source: UnifiedExtensionSource
    @State private var preferences: [ExtensionJSON] = []
    @State private var loading = false
    @State private var error: String?
    @State private var removing = false
    var body: some View {
        Form {
            Section(source.label) {
                Text(source.managerId.replacingOccurrences(of: "-desktop", with: "").capitalized)
                if let url = source.baseUrl.flatMap(URL.init(string:)), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    Link("Open source website", destination: url)
                }
                if source.hasUpdate == true { Button("Update extension") { Task { await store.mutate("update", source: source); await load() } }.disabled(store.busy) }
            }
            if loading { Section { ProgressView("Loading source settings…") } }
            if let error { Section { Text(error).foregroundStyle(.orange); Button("Retry") { Task { await load() } } } }
            Section("Source preferences") {
                ForEach(Array(preferences.enumerated()), id: \.offset) { _, preference in
                    ExtensionPreferenceRow(preference: preference) { value in
                        Task {
                            loading = true; error = nil
                            defer { loading = false }
                            do { preferences = try await store.request("setPreference", source: source,
                                arguments: ["key": preference["key"].foundation, "id": preference["id"].foundation, "value": value.foundation]) }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(loading)
                }
                if preferences.isEmpty && !loading { Text("This source does not expose additional settings on this device.").foregroundStyle(.secondary) }
            }
            Section { Button("Remove extension", role: .destructive) { removing = true }.disabled(store.busy) }
        }.navigationTitle("Source settings").navigationBarTitleDisplayMode(.inline).task { await load() }
            .confirmationDialog("Remove \(source.label)?", isPresented: $removing, titleVisibility: .visible) {
                Button("Remove extension", role: .destructive) { Task { await store.mutate("uninstall", source: source); if store.error == nil { dismiss() } else { error = store.error } } }
            } message: { Text("Saved titles are kept. Reinstall the source to open them again.") }
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { preferences = try await store.request("preferences", source: source) }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

private struct ExtensionPreferenceRow: View {
    let preference: ExtensionJSON
    let save: (ExtensionJSON) -> Void
    @State private var text = ""
    private var value: ExtensionJSON {
        for key in ["checkBoxPreference", "switchPreferenceCompat", "listPreference", "multiSelectListPreference", "editTextPreference"] {
            if !preference[key].object.isEmpty { return preference[key] }
        }
        return preference
    }
    private var title: String { value["title"].string ?? preference["key"].string ?? "Preference" }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !preference["checkBoxPreference"].object.isEmpty || !preference["switchPreferenceCompat"].object.isEmpty {
                Toggle(title, isOn: Binding(get: { value["value"].boolean }, set: { save(.bool($0)) }))
            } else if !preference["listPreference"].object.isEmpty {
                Picker(title, selection: Binding(get: { value["value"].string ?? "" }, set: { save(.string($0)) })) {
                    ForEach(Array(value["entries"].array.enumerated()), id: \.offset) { index, label in
                        Text(label.string ?? "Option").tag(value["entryValues"].array.indices.contains(index) ? value["entryValues"].array[index].string ?? "" : label.string ?? "")
                    }
                }
            } else if !preference["multiSelectListPreference"].object.isEmpty {
                Text(title).font(.headline)
                ForEach(Array(value["entries"].array.enumerated()), id: \.offset) { index, label in
                    let options = value["entryValues"].array
                    let option = options.indices.contains(index) ? options[index] : label
                    Toggle(label.string ?? "Option", isOn: Binding(get: { value["values"].array.contains(option) }, set: { selected in
                        var choices = value["values"].array.filter { $0 != option }; if selected { choices.append(option) }; save(.array(choices))
                    }))
                }
            } else if !preference["editTextPreference"].object.isEmpty {
                Text(title).font(.subheadline)
                SecureField("Value", text: $text).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save") { save(.string(text)) }.disabled(text == value["value"].string)
            } else { Text(title).foregroundStyle(.secondary) }
            if let summary = value["summary"].string, !summary.isEmpty { Text(summary).font(.caption).foregroundStyle(.secondary) }
        }.onAppear { text = value["value"].string ?? "" }
    }
}

struct ExtensionWebsiteSessionView: View {
    let request: ExtensionWebsiteRequest
    @State private var webView: WKWebView?
    var body: some View {
        NavigationStack {
            ExtensionSessionWebView(url: request.url, webView: $webView)
                .navigationTitle(request.url.host ?? "Source website").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { AnymeXRuntime.shared.finishWebsite() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Continue") { finish() }.disabled(webView == nil) }
                }
        }
    }
    private func finish() {
        guard let webView else { return }
        webView.evaluateJavaScript("navigator.userAgent") { userAgent, _ in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let host = request.url.host?.lowercased() ?? ""
                let selected = cookies.filter { cookie in
                    let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
                    return host == domain || host.hasSuffix("." + domain)
                }.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                Task { @MainActor in AnymeXRuntime.shared.finishWebsite(cookies: selected, userAgent: userAgent as? String ?? "", solved: true) }
            }
        }
    }
}
private struct ExtensionSessionWebView: UIViewRepresentable {
    let url: URL
    @Binding var webView: WKWebView?
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        DispatchQueue.main.async { webView = view }
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
