import SwiftUI

struct TileSettingsSheet: View {
    let model: ModuleLibraryModel
    let entry: WheelEntry
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var values: [String: String] = [:]
    @State private var ready = false
    @State private var saving = false
    @State private var error: String?

    private var fields: [ActionSetting] { model.settingsFields(for: entry) }
    private func value(_ field: ActionSetting) -> Binding<String> {
        Binding(get: { values[field.id] ?? field.defaultValue ?? "" }, set: { values[field.id] = $0 })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Action settings")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            Form {
                Section {
                    TextField("Name", text: $name)
                }
                if !fields.isEmpty {
                    Section {
                        ForEach(fields) { field in
                            switch field.type {
                            case .text: TextField(field.localizedLabel, text: value(field))
                            case .password: SecureField(field.localizedLabel, text: value(field))
                            case .number: TextField(field.localizedLabel, text: value(field))
                            case .toggle:
                                Toggle(field.localizedLabel, isOn: Binding(
                                    get: { value(field).wrappedValue == "true" },
                                    set: { value(field).wrappedValue = String($0) }))
                            case .select:
                                Picker(field.localizedLabel, selection: value(field)) {
                                    ForEach(field.choices ?? [], id: \.self) { Text($0).tag($0) }
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(!ready || saving)
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!ready || saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
        }
        .frame(width: 460, height: fields.isEmpty ? 220 : 480)
        .task {
            name = entry.children != nil ? entry.title : entry.customTitle
                ?? model.paletteActions.first(where: { $0.id == entry.actionID })?.title ?? ""
            values = entry.settings ?? [:]
            do {
                if fields.contains(where: { $0.type == .password }) {
                    values.merge(try await TileCredentials().load(entry.id)) { _, new in new }
                }
                ready = true
            } catch { self.error = error.localizedDescription }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var normal: [String: String] = [:]
        var secrets: [String: String] = [:]
        for field in fields {
            let text = value(field).wrappedValue
            if field.required == true && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                error = "\(field.localizedLabel) is required"; return
            }
            if field.type == .number && !text.isEmpty {
                guard let number = Double(text), number.isFinite,
                      field.minimum.map({ number >= $0 }) ?? true,
                      field.maximum.map({ number <= $0 }) ?? true else {
                    error = "Enter a valid value for \(field.localizedLabel)"; return
                }
            }
            if field.type == .password { secrets[field.id] = text }
            else { normal[field.id] = text }
        }
        do {
            if fields.contains(where: { $0.type == .password }) {
                try await TileCredentials().save(secrets, tile: entry.id)
            }
            var edited = entry
            if edited.children != nil { edited.title = name }
            else { edited.customTitle = name }
            edited.settings = normal
            await model.updateTile(edited)
            if let error = model.error { self.error = error }
            else { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}
