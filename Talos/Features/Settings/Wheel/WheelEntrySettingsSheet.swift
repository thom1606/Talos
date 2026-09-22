import SwiftUI

struct WheelEntrySettingsSheet: View {
    let entry: WheelItem
    let tile: WheelTilePresentation?
    let onSave: (WheelItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(
        entry: WheelItem,
        tile: WheelTilePresentation?,
        onSave: @escaping (WheelItem) -> Void
    ) {
        self.entry = entry
        self.tile = tile
        self.onSave = onSave
        // A sheet edits a draft; changes reach the configuration only on Save.
        _name = State(initialValue: entry.customTitle ?? tile?.title ?? "Folder")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("wheel.entry.name")

                if let tile {
                    LabeledContent("Extension", value: tile.extensionName)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(entry.isFolder ? "Edit Folder" : "Edit Action")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updatedEntry = entry
                        updatedEntry.customTitle = trimmedName
                        onSave(updatedEntry)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 200)
    }
}
