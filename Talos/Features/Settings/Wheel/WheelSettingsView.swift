import AppKit
import SwiftUI

struct WheelSettingsView: View {
    let tiles: [WheelTilePresentation]

    @State private var viewModel: WheelSettingsViewModel

    init(
        tiles: [WheelTilePresentation],
        configuration: WheelConfigurationModel
    ) {
        self.tiles = tiles
        viewModel = WheelSettingsViewModel(
            tiles: tiles,
            configuration: configuration
        )
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        HStack(spacing: 0) {
            WheelTileList(
                tiles: viewModel.availableTiles,
                model: viewModel,
                onAddFolder: viewModel.addFolder,
                onAddTile: viewModel.addTile
            )
            .frame(width: 200)
            .background(.primary.opacity(0.04), ignoresSafeAreaEdges: [])

            VStack(spacing: 0) {
                Text("Drag tiles onto the wheel to add them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top)

                Spacer(minLength: 12)

                WheelPreview(
                    entries: viewModel.visibleEntries,
                    tiles: viewModel.availableTiles,
                    context: viewModel.selectedPreviewContext,
                    ghostEntryID: viewModel.ghostEntryID,
                    pressedFolderID: viewModel.pressedFolderID,
                    folderPressStartedAt: viewModel.folderPressStartedAt,
                    canNavigateBack: viewModel.canNavigateBack,
                    onEdit: viewModel.editEntry,
                    onOpenFolder: viewModel.openFolder,
                    onRemove: viewModel.removeEntry,
                    onNavigateBack: viewModel.navigateBack,
                    interactionModel: viewModel
                )
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named("wheelEditor"))
                } action: { frame in
                    viewModel.updateWheelFrame(frame)
                }

                Spacer(minLength: 12)

                Picker("Preview context", selection: $viewModel.selectedPreviewContext) {
                    ForEach(WheelPreviewContext.allCases) { context in
                        Text(context.title)
                            .tag(context)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 390)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .top) {
            Divider().allowsHitTesting(false)
        }
        .coordinateSpace(.named("wheelEditor"))
        .overlay(alignment: .topLeading) {
            if let draggedEntry = viewModel.draggedEntry,
               viewModel.showsFloatingPreview {
                PositionedWheelDragPreview(
                    title: draggedEntry.title(using: viewModel.availableTiles),
                    symbolName: draggedEntry.symbolName(using: viewModel.availableTiles),
                    position: viewModel.dragPosition
                )
                .allowsHitTesting(false)
            }
        }
        .sheet(item: $viewModel.editingEntry) { entry in
            WheelEntrySettingsSheet(
                entry: entry,
                tile: viewModel.availableTiles.first(where: { $0.id == entry.actionID }),
                onSave: viewModel.saveEntry
            )
        }
        .onAppear {
            viewModel.updateTiles(tiles)
        }
        .onChange(of: tiles) { _, updatedTiles in
            viewModel.updateTiles(updatedTiles)
        }
        .onChange(of: viewModel.cursor) { _, cursor in
            apply(cursor)
        }
        .onDisappear {
            viewModel.resetInteractions()
            NSCursor.arrow.set()
        }
    }

    private func apply(_ cursor: WheelDragCursor) {
        switch cursor {
        case .arrow:
            NSCursor.arrow.set()
        case .closedHand:
            NSCursor.closedHand.set()
        case .disappearingItem:
            NSCursor.disappearingItem.set()
        }
    }
}
