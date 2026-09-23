import SwiftUI

struct WheelEntrySettingsSheet: View {
    let entry: WheelItem
    let tile: WheelTilePresentation?
    let onSave: (WheelItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var values: [String: TileConfigValue]
    @State private var textDraft: [String: String]
    @State private var numberDraft: [String: String]
    @State private var passwordDraft: [String: String] = [:]
    @State private var storedPasswords: Set<String> = []
    @State private var didLoadPasswords = false
    @State private var errorMessage = ""
    @State private var showsError = false

    init(entry: WheelItem, tile: WheelTilePresentation?, onSave: @escaping (WheelItem) -> Void) {
        self.entry = entry
        self.tile = tile
        self.onSave = onSave
        _name = State(initialValue: entry.customTitle ?? tile?.title ?? String(localized: "Folder"))

        var values = entry.config
        var textDraft: [String: String] = [:]
        var numberDraft: [String: String] = [:]
        for setting in tile?.settings ?? [] where setting.type != .password {
            let value = values[setting.name] ?? setting.defaultValue
                ?? (setting.type == .select ? setting.options?.first.map(TileConfigValue.string) : nil)
            if let value { values[setting.name] = value }
            switch value {
            case let .string(text): textDraft[setting.name] = text
            case let .number(number): numberDraft[setting.name] = String(number)
            default: break
            }
        }
        _values = State(initialValue: values)
        _textDraft = State(initialValue: textDraft)
        _numberDraft = State(initialValue: numberDraft)
    }

    private var settings: [ExtensionSetting] { tile?.settings ?? [] }

    private struct SettingSection: Identifiable {
        let id: Int
        let title: String
        var settings: [ExtensionSetting]
    }

    private var settingSections: [SettingSection] {
        var sections: [SettingSection] = []
        for setting in settings {
            let title = setting.section ?? String(localized: "Configuration")
            if let index = sections.indices.last, sections[index].title == title {
                sections[index].settings.append(setting)
            } else {
                sections.append(.init(id: sections.count, title: title, settings: [setting]))
            }
        }
        return sections
    }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("wheel.entry.name")
                    if let tile {
                        LabeledContent("Extension", value: tile.extensionName)
                    }
                }

                ForEach(settingSections) { group in
                    Section {
                        ForEach(group.settings) { setting in
                            settingRow(setting)
                        }
                    } header: {
                        Text(group.title)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(entry.isFolder ? "Edit Folder" : "Edit Action")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(trimmedName.isEmpty || (!didLoadPasswords && settings.contains { $0.type == .password }))
                }
            }
        }
        .frame(width: 470, height: settings.isEmpty ? 265 : (settingSections.count > 1 ? 460 : 390))
        .onAppear(perform: loadPasswords)
        .alert("Couldn't save action", isPresented: $showsError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    @ViewBuilder
    private func settingRow(_ setting: ExtensionSetting) -> some View {
        switch setting.type {
        case .text:
            TextField(setting.displayName, text: textBinding(for: setting.name),
                      prompt: setting.placeholder.map { Text($0) })
                .accessibilityIdentifier("wheel.entry.setting.\(setting.name)")
        case .password:
            SecureField(setting.displayName, text: passwordBinding(for: setting.name),
                        prompt: setting.placeholder.map { Text($0) })
                .help(storedPasswords.contains(setting.name)
                    ? String(localized: "Saved in Keychain. Leave empty to keep it.") : "")
                .accessibilityIdentifier("wheel.entry.setting.\(setting.name)")
        case .number:
            TextField(setting.displayName, text: numberBinding(for: setting.name),
                      prompt: setting.placeholder.map { Text($0) })
                .accessibilityIdentifier("wheel.entry.setting.\(setting.name)")
        case .boolean:
            Toggle(setting.displayName, isOn: booleanBinding(for: setting.name))
                .accessibilityIdentifier("wheel.entry.setting.\(setting.name)")
        case .select:
            Picker(setting.displayName, selection: textBinding(for: setting.name)) {
                ForEach(setting.options ?? [], id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .accessibilityIdentifier("wheel.entry.setting.\(setting.name)")
        }
    }

    private func textBinding(for name: String) -> Binding<String> {
        Binding(get: { textDraft[name] ?? "" }, set: { textDraft[name] = $0 })
    }

    private func numberBinding(for name: String) -> Binding<String> {
        Binding(get: { numberDraft[name] ?? "" }, set: { numberDraft[name] = $0 })
    }

    private func passwordBinding(for name: String) -> Binding<String> {
        Binding(get: { passwordDraft[name] ?? "" }, set: { passwordDraft[name] = $0 })
    }

    private func booleanBinding(for name: String) -> Binding<Bool> {
        Binding(
            get: { if case let .boolean(value) = values[name] { value } else { false } },
            set: { values[name] = .boolean($0) }
        )
    }

    private func loadPasswords() {
        guard !didLoadPasswords else { return }
        do {
            storedPasswords = Set(try ActionSettingSecretStore().passwords(for: entry.id).keys)
            didLoadPasswords = true
        } catch {
            present(error)
        }
    }

    private func save() {
        do {
            var config = values
            for setting in settings {
                switch setting.type {
                case .text, .select:
                    let text = textDraft[setting.name] ?? ""
                    if setting.required == true && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        throw ActionSettingValidationError.missing(setting.displayName)
                    }
                    config[setting.name] = .string(text)
                case .number:
                    let text = numberDraft[setting.name] ?? ""
                    if !text.isEmpty {
                        guard let number = Double(text), number.isFinite else {
                            throw ActionSettingValidationError.invalidNumber(setting.displayName)
                        }
                        config[setting.name] = .number(number)
                    } else if setting.required == true {
                        throw ActionSettingValidationError.missing(setting.displayName)
                    } else {
                        config.removeValue(forKey: setting.name)
                    }
                case .boolean:
                    if config[setting.name] == nil { config[setting.name] = .boolean(false) }
                case .password:
                    config.removeValue(forKey: setting.name)
                    if setting.required == true && (passwordDraft[setting.name] ?? "").isEmpty && !storedPasswords.contains(setting.name) {
                        throw ActionSettingValidationError.missing(setting.displayName)
                    }
                }
            }
            let newPasswords = passwordDraft.filter { !$0.value.isEmpty }
            if !newPasswords.isEmpty {
                var passwords = try ActionSettingSecretStore().passwords(for: entry.id)
                passwords.merge(newPasswords) { _, new in new }
                try ActionSettingSecretStore().save(passwords, for: entry.id)
            }
            var updatedEntry = entry
            updatedEntry.customTitle = trimmedName
            updatedEntry.config = config
            onSave(updatedEntry)
            dismiss()
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showsError = true
    }
}

private enum ActionSettingValidationError: LocalizedError {
    case missing(String)
    case invalidNumber(String)

    var errorDescription: String? {
        switch self {
        case let .missing(name): "Enter \(name)."
        case let .invalidNumber(name): "Enter a valid number for \(name)."
        }
    }
}
