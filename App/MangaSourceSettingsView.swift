import SwiftUI
import AnimeCore

struct MangaSourceSettingsView: View {
    @EnvironmentObject private var extensions: MangaExtensionStore
    @Environment(\.dismiss) private var dismiss
    let source: MangaSourceReference
    let didSave: () -> Void
    @State private var schema: MangaSourceSettingsSchema?
    @State private var original = MangaSourceSettings()
    @State private var draft = MangaSourceSettings()
    @State private var version = ""
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView("Loading source settings…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let schema {
                    settingsForm(schema)
                } else {
                    ContentUnavailableView {
                        Label("Settings unavailable", systemImage: "slider.horizontal.3")
                    } description: { Text(error ?? "Try opening source settings again.") }
                    actions: { Button("Try again") { Task { await load() } } }
                }
            }
            .background(Color.black).navigationTitle("Source settings").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving).accessibilityIdentifier("source-settings-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(loading || saving || schema == nil)
                        .accessibilityIdentifier("source-settings-save")
                }
            }
            .interactiveDismissDisabled(saving)
            .task { await load() }
        }.tint(MangaStyle.accent)
    }

    private func settingsForm(_ schema: MangaSourceSettingsSchema) -> some View {
        Form {
            Section {
                Label(source.name, systemImage: "puzzlepiece.extension").font(.headline)
            } footer: {
                Text("Options are provided by this source. Saved values stay on this device and are available whenever the source runs.")
            }
            if schema.settings.isEmpty {
                Section { Text("This source has no configurable options.").foregroundStyle(.secondary) }
            }
            ForEach(groups(schema)) { group in
                Section(group.title) {
                    ForEach(group.items) { setting in
                        settingRow(setting)
                    }
                }
            }
            if !schema.settings.isEmpty || !draft.values.isEmpty {
                Section {
                    Button("Restore defaults", role: .destructive) { draft = MangaSourceSettings(); error = nil }
                        .disabled(saving).accessibilityIdentifier("source-settings-reset")
                } footer: { Text("Changes take effect when you save. Restoring defaults also clears saved source credentials.") }
            }
            if saving { Section { ProgressView("Saving…") } }
            if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("source-settings-error") } }
        }.scrollContentBackground(.hidden).disabled(saving)
    }

    @ViewBuilder private func settingRow(_ setting: MangaSourceSetting) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch setting.control {
            case .toggle:
                Toggle(setting.title, isOn: Binding(get: { value(setting)?.boolean ?? false }, set: { draft.values[setting.key] = .boolean($0) }))
                    .accessibilityIdentifier("source-setting-\(setting.key)")
            case .choice, .multiChoice:
                NavigationLink {
                    MangaSourceChoiceView(setting: setting, value: Binding(get: { value(setting) }, set: { draft.values[setting.key] = $0 }))
                } label: {
                    HStack {
                        Text(setting.title)
                        Spacer(minLength: 12)
                        Text(choiceLabel(setting)).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    }
                }.accessibilityIdentifier("source-setting-\(setting.key)")
            case .text:
                MangaSourceTextSetting(setting: setting, text: Binding(get: { value(setting)?.text ?? "" }, set: { draft.values[setting.key] = .string($0) }))
            case .unsupported:
                Label(setting.title, systemImage: "exclamationmark.circle")
                Text("This option needs a runtime update.").font(.caption).foregroundStyle(.secondary)
            }
            if !setting.summary.isEmpty { Text(setting.summary).font(.caption).foregroundStyle(.secondary) }
            if let saved = draft.values[setting.key], setting.control != .unsupported, !setting.accepts(saved) {
                Text("The saved value is no longer supported. Choose a new value or restore defaults.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }.padding(.vertical, 3).disabled(!setting.enabled || setting.control == .unsupported)
    }

    private func value(_ setting: MangaSourceSetting) -> MangaSourceSettingValue? { draft.values[setting.key] ?? setting.defaultValue }
    private func choiceLabel(_ setting: MangaSourceSetting) -> String {
        if setting.control == .multiChoice {
            let selected = Set(value(setting)?.strings ?? [])
            return selected.isEmpty ? "None" : "\(selected.count) selected"
        }
        return setting.choices.first { $0.value == value(setting)?.text }?.label ?? "Choose"
    }
    private struct SettingGroup: Identifiable {
        let id: Int
        let title: String
        var items: [MangaSourceSetting]
    }
    private func groups(_ schema: MangaSourceSettingsSchema) -> [SettingGroup] {
        var result: [SettingGroup] = []
        for setting in schema.settings {
            let title = setting.section ?? "Source options"
            if result.last?.title == title { result[result.count - 1].items.append(setting) }
            else { result.append(SettingGroup(id: result.count, title: title, items: [setting])) }
        }
        return result
    }
    @MainActor private func load() async {
        loading = true; error = nil; schema = nil
        defer { loading = false }
        do {
            guard let version = extensions.installed(source.extensionID)?.descriptor.sha256 else { throw MangaExtensionError.sourceUnavailable }
            let configuration = try await extensions.sourceConfiguration(source)
            let definitions = try await extensions.sourceSettings(source)
            try Task.checkCancellation()
            guard extensions.installed(source.extensionID)?.descriptor.sha256 == version else { throw MangaExtensionError.sourceUnavailable }
            self.version = version; original = configuration; draft = configuration; schema = definitions
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    @MainActor private func save() async {
        guard let schema, !saving else { return }
        saving = true; error = nil
        defer { saving = false }
        do {
            for setting in schema.settings {
                if let changed = draft.values[setting.key], changed != original.values[setting.key], !setting.accepts(changed) {
                    throw MangaExtensionError.invalidSourceSettings
                }
            }
            try await extensions.saveSourceSettings(draft, source: source, expectedVersion: version)
            didSave(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct MangaSourceTextSetting: View {
    let setting: MangaSourceSetting
    @Binding var text: String
    @State private var revealed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(setting.title)
            HStack {
                Group {
                    if setting.isSecret && !revealed { SecureField("Enter value", text: $text) }
                    else { TextField("Enter value", text: $text) }
                }.textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel(setting.title).accessibilityIdentifier("source-setting-\(setting.key)")
                if setting.isSecret {
                    Button { revealed.toggle() } label: { Image(systemName: revealed ? "eye.slash" : "eye") }
                        .buttonStyle(.borderless).accessibilityLabel(revealed ? "Hide value" : "Show value")
                }
            }
        }
    }
}

private struct MangaSourceChoiceView: View {
    @Environment(\.dismiss) private var dismiss
    let setting: MangaSourceSetting
    @Binding var value: MangaSourceSettingValue?
    var body: some View {
        List(setting.choices) { choice in
            Button {
                if setting.control == .multiChoice {
                    var selected = Set(value?.strings ?? [])
                    if !selected.insert(choice.value).inserted { selected.remove(choice.value) }
                    value = .stringSet(selected.sorted())
                } else { value = .string(choice.value); dismiss() }
            } label: {
                HStack {
                    Text(choice.label).foregroundStyle(.primary)
                    Spacer()
                    if selected(choice) { Image(systemName: "checkmark").foregroundStyle(MangaStyle.accent) }
                }.contentShape(Rectangle())
            }.accessibilityIdentifier("source-choice-\(choice.value)")
                .accessibilityValue(selected(choice) ? "Selected" : "Not selected")
        }.navigationTitle(setting.title).navigationBarTitleDisplayMode(.inline)
    }
    private func selected(_ choice: MangaSourceSetting.Choice) -> Bool {
        setting.control == .multiChoice ? (value?.strings ?? []).contains(choice.value) : value?.text == choice.value
    }
}
