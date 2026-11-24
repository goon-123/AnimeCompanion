import SwiftUI
import UIKit
import AnimeCore

/// Keep the draft in one form. Editing and pasting never submit or dismiss it.
struct ExtensionAddRepositorySheet: View {
    @EnvironmentObject private var store: UnifiedExtensionStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editingURL: Bool
    @State private var managerID = ""
    @State private var kind: ExtensionContentKind = .anime
    @State private var url = ""
    @State private var validation: String?
    @State private var saving = false
    @State private var savedOwner: String?
    @State private var savedContent: ExtensionContentKind?
    @State private var started = false
    let initialKind: ExtensionContentKind
    let added: (String, ExtensionContentKind) -> Void

    private var selected: UnifiedExtensionManager? { store.snapshot.managers.first { $0.id == managerID } }
    private var systems: [UnifiedExtensionManager] {
        store.snapshot.managers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            Form {
                if let savedOwner, let savedContent {
                    Section {
                        Label("Repository added", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).accessibilityIdentifier("extensions-repository-saved")
                        Text("Your repository is saved. Open Browse to install a source.")
                        ForEach(store.snapshot.available.filter { $0.managerId == savedOwner && $0.kind == savedContent }.prefix(5)) { source in
                            Text(source.label).font(.subheadline)
                        }
                        Button("Browse sources") { added(savedOwner, savedContent); dismiss() }
                            .accessibilityIdentifier("extensions-repository-browse")
                    }
                }
                Section {
                    TextField("Paste repository link", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL).submitLabel(.done).focused($editingURL)
                        .onSubmit { editingURL = false }
                        .accessibilityIdentifier("extensions-repository-url")
                    Button {
                        // Read the clipboard only after this explicit user action.
                        if let value = UIPasteboard.general.string ?? UIPasteboard.general.url?.absoluteString {
                            acceptPaste(value)
                        } else { validation = "Copy a repository link, then tap Paste." }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.borderless).accessibilityIdentifier("extensions-paste-repository")
                } header: { Text("Repository link") }
                footer: { Text("Paste the HTTPS link from the repository's maintainer, then tap Add repository.") }
                .disabled(saving || savedOwner != nil)

                Section {
                    Picker("System", selection: $managerID) {
                        Text("Choose a system").tag("")
                        ForEach(systems) { Text($0.name).tag($0.id) }
                    }.accessibilityIdentifier("extensions-repository-system")
                    if let selected {
                        if selected.types.count > 1 {
                            Picker("Content", selection: $kind) {
                                ForEach(selected.types) { Text($0.label).tag($0) }
                            }
                        } else { LabeledContent("Content", value: kind.label) }
                    }
                }.disabled(saving || store.busy || savedOwner != nil)

                if let validation { Section { Text(validation).foregroundStyle(.orange).accessibilityIdentifier("extensions-repository-error") } }
                if let error = store.error { Section { Text(error).foregroundStyle(.orange).accessibilityIdentifier("extensions-repository-error") } }
                if store.busy { Section { ProgressView(store.status) } }
                if systems.isEmpty && !store.busy {
                    Section { Button("Reload source systems") { Task { await store.load() } } }
                }
                Section {
                    Button("Add repository") { add() }
                        .disabled(saving || store.busy || savedOwner != nil || selected == nil || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("extensions-save-repository")
                } footer: { Text("After adding a repository, choose a source in Browse and tap Install.") }
            }
            .navigationTitle("Add repository").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(savedOwner == nil ? "Cancel" : "Done") { dismiss() }.disabled(saving)
                }
            }
            .navigationBarBackButtonHidden(saving)
            .scrollDismissesKeyboard(.interactively)
            .onAppear { if !started { kind = initialKind; started = true } }
            .onChange(of: url) { _, _ in
                validation = nil
                suggestSystem()
            }
            .onChange(of: store.snapshot.managers.map(\.id)) { _, _ in suggestSystem() }
            .onChange(of: managerID) { _, _ in
                validation = nil
                if let selected, !selected.types.contains(kind) { kind = selected.types.first ?? initialKind }
            }
        }
        .interactiveDismissDisabled()
        .accessibilityIdentifier("extensions-repository-editor")
    }

    private func acceptPaste(_ value: String) {
        url = value.trimmingCharacters(in: .whitespacesAndNewlines)
        editingURL = false
    }

    private func suggestSystem() {
        // Only use an explicit ecosystem component, not a guessed host.
        if managerID.isEmpty,
           URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines))?.pathComponents.contains(where: { $0.lowercased() == "sora" }) == true,
           systems.contains(where: { $0.id == "sora" }) { managerID = "sora" }
    }

    private func add() {
        guard !saving, !store.busy, selected != nil else { return }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: trimmed), parts.scheme?.lowercased() == "https",
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil else {
            validation = "Enter a complete HTTPS repository link."
            return
        }
        let owner = managerID, content = kind
        // Stremio stores its canonical manifest URL even when a user supplies
        // the add-on's base URL. Other systems retain the supplied link.
        var canonical = parts
        canonical.fragment = nil
        if owner == "stremio" {
            var path = canonical.path
            while path.hasSuffix("/") { path.removeLast() }
            if !path.lowercased().hasSuffix("/manifest.json") { path += "/manifest.json" }
            canonical.path = path
        }
        let acceptedURL = owner == "stremio" ? canonical.string : trimmed
        validation = nil; saving = true; editingURL = false
        Task {
            defer { saving = false }
            let succeeded = await store.update("addRepo", ["manager": owner, "type": content.rawValue, "url": trimmed])
            guard succeeded else {
                if store.error == nil { validation = "The repository wasn't added. Please try again." }
                return
            }
            guard store.snapshot.managers.first(where: { $0.id == owner })?.repositories.contains(where: {
                $0.type == content && ($0.url == trimmed || $0.url == acceptedURL)
            }) == true else {
                validation = "The repository wasn't saved. Check the system and link, then try again."
                return
            }
            // Keep the editor and the stored result visible. Only an explicit
            // Done/Browse action leaves this page, never a request callback.
            savedOwner = owner
            savedContent = content
        }
    }
}
