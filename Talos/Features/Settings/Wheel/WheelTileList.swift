import SwiftUI

/// A palette has no row selection: each row is a local drag source, using the
/// same gesture lifecycle as wheel tiles. Keeping it in a ScrollView also keeps
/// AppKit's List row dragging from taking ownership of the pointer session.
struct WheelTileList: View {
    let tiles: [WheelTilePresentation]
    let model: WheelSettingsViewModel
    let onAddFolder: () -> Void
    let onAddTile: (WheelTilePresentation) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("Tiles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                WheelPaletteRow(
                    title: "Folder",
                    subtitle: "Talos",
                    symbolName: "folder"
                )
                .accessibilityIdentifier("wheel.palette.folder")
                .modifier(WheelEditorInteraction(source: .folder, model: model))
                .contextMenu {
                    Button("Add to wheel", systemImage: "plus.circle", action: onAddFolder)
                }
                .accessibilityAction(named: "Add to wheel", onAddFolder)

                ForEach(tiles) { tile in
                    WheelPaletteRow(
                        title: tile.title,
                        subtitle: tile.extensionName,
                        symbolName: tile.resolvedSymbolName
                    )
                    .accessibilityIdentifier("wheel.palette.\(tile.id)")
                    .modifier(WheelEditorInteraction(source: .tile(tile.id), model: model))
                    .contextMenu {
                        Button("Add to wheel", systemImage: "plus.circle") {
                            onAddTile(tile)
                        }
                    }
                    .accessibilityAction(named: "Add to wheel") {
                        onAddTile(tile)
                    }
                }
            }
        }
        .accessibilityLabel("Wheel tiles")
    }
}

private struct WheelPaletteRow: View {
    let title: String
    let subtitle: String
    let symbolName: String
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 30, height: 30)
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.primary.opacity(isHovered ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Drag onto the wheel")
    }
}
