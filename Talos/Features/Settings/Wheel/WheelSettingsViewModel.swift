import CoreGraphics
import Foundation
import Observation

enum WheelDragCursor: Equatable {
    case arrow
    case closedHand
    case disappearingItem
}

enum WheelDragSource: Equatable {
    case entry(WheelItem.ID)
    case tile(String)
    case folder
}

/// Pointer movement only invalidates the floating preview, not the editor.
@MainActor
@Observable
final class WheelDragPosition {
    var point = CGPoint.zero
}

/// Keeps edits provisional until a drag finishes. Cancellation never persists
/// the draft, and hidden entries retain their order when a filtered tile moves.
@MainActor
@Observable
final class WheelSettingsViewModel {
    var selectedPreviewContext = WheelPreviewContext.image {
        didSet {
            if oldValue != selectedPreviewContext { resetInteractions() }
        }
    }
    var editingEntry: WheelItem?

    let dragPosition = WheelDragPosition()
    private(set) var draggedEntry: WheelItem?
    private(set) var dragIsInsideWheel = false
    private(set) var pressedFolderID: WheelItem.ID?
    private(set) var folderPressStartedAt: Date?
    private(set) var cursor = WheelDragCursor.arrow

    private let configuration: WheelConfigurationModel
    private var extensionTiles: [WheelTilePresentation]
    private var folderPath: [WheelItem.ID] = []
    private var draftEntries: [WheelItem]?

    // These are input bookkeeping, not render dependencies.
    @ObservationIgnored private var wheelFrame = CGRect.zero
    @ObservationIgnored private var dragSource: WheelDragSource?
    @ObservationIgnored private var originalEntries: [WheelItem] = []
    @ObservationIgnored private var entriesWithoutDragged: [WheelItem] = []
    @ObservationIgnored private var insertionOffsets: [Int] = []
    @ObservationIgnored private var lastDestination: DragDestination?

    private enum DragDestination: Equatable {
        case outside
        case slot(Int)
    }

    init(tiles: [WheelTilePresentation], configuration: WheelConfigurationModel) {
        extensionTiles = tiles
        self.configuration = configuration
    }

    var availableTiles: [WheelTilePresentation] {
        [.systemSettings] + extensionTiles
    }

    var visibleEntries: [WheelItem] {
        (draftEntries ?? currentEntries).filter {
            $0.supports(selectedPreviewContext, using: availableTiles)
        }
    }

    var ghostEntryID: WheelItem.ID? { draggedEntry?.id }
    var canNavigateBack: Bool { !folderPath.isEmpty }
    var showsFloatingPreview: Bool {
        draggedEntry != nil && !dragIsInsideWheel
    }

    func updateTiles(_ tiles: [WheelTilePresentation]) {
        guard tiles != extensionTiles else { return }
        resetInteractions()
        extensionTiles = tiles
    }

    func updateWheelFrame(_ frame: CGRect) {
        wheelFrame = frame
    }

    func addFolder() {
        addToWheel(.folder(String(localized: "Folder")))
    }

    func addTile(_ tile: WheelTilePresentation) {
        selectSupportedContext(for: tile)
        addToWheel(.action(tile.id))
    }

    func setFolderPress(_ id: WheelItem.ID, isPressed: Bool) {
        if isPressed {
            guard dragSource == nil, pressedFolderID != id else { return }
            pressedFolderID = id
            folderPressStartedAt = .now
        } else if pressedFolderID == id {
            endPress()
        }
    }

    func updateDrag(source: WheelDragSource, location: CGPoint) {
        endPress()
        if dragSource == nil { beginDrag(source) }
        guard dragSource == source, let draggedEntry else { return }

        dragPosition.point = location
        let localPoint = CGPoint(x: location.x - wheelFrame.minX, y: location.y - wheelFrame.minY)
        let isInside = WheelLayout.editor.contains(localPoint)
        let destination: DragDestination = isInside
            ? .slot(WheelLayout.editor.insertionIndex(at: localPoint, count: insertionOffsets.count))
            : .outside

        // Filtering and building a new draft only happen when the slot changes.
        guard destination != lastDestination else { return }
        lastDestination = destination
        dragIsInsideWheel = isInside
        switch destination {
        case let .slot(index):
            var entries = entriesWithoutDragged
            entries.insert(draggedEntry, at: insertionOffsets[index])
            draftEntries = entries
            cursor = .closedHand
        case .outside:
            // Keep the source view alive until mouse-up/cancellation, even when
            // the tile is being dragged out for removal.
            draftEntries = originalEntries
            cursor = .disappearingItem
        }
    }

    func endDrag(source: WheelDragSource, location: CGPoint) {
        updateDrag(source: source, location: location)
        guard dragSource == source else { return }
        defer { resetInteractions() }
        if dragIsInsideWheel {
            setCurrentEntries(draftEntries ?? originalEntries)
        } else if case .entry = source {
            setCurrentEntries(entriesWithoutDragged)
        }
    }

    func cancelDrag(source: WheelDragSource) {
        guard dragSource == source else { return }
        resetInteractions()
    }

    func editEntry(_ id: WheelItem.ID) {
        guard dragSource == nil else { return }
        editingEntry = currentEntries.first(where: { $0.id == id })
    }

    func saveEntry(_ updatedEntry: WheelItem) {
        resetInteractions()
        configuration.replaceItems(with: WheelItem.updating(updatedEntry, in: configuration.items))
    }

    func openFolder(_ id: WheelItem.ID) {
        guard dragSource == nil,
              currentEntries.contains(where: { $0.id == id && $0.isFolder }) else { return }
        endPress()
        folderPath.append(id)
    }

    func navigateBack() {
        guard !folderPath.isEmpty else { return }
        resetInteractions()
        folderPath.removeLast()
    }

    func removeEntry(_ id: WheelItem.ID) {
        resetInteractions()
        setCurrentEntries(currentEntries.filter { $0.id != id })
    }

    func resetInteractions() {
        dragSource = nil
        draggedEntry = nil
        originalEntries = []
        entriesWithoutDragged = []
        insertionOffsets = []
        lastDestination = nil
        draftEntries = nil
        dragIsInsideWheel = false
        cursor = .arrow
        endPress()
    }

    private var currentEntries: [WheelItem] {
        WheelItem.items(in: configuration.items, at: folderPath)
    }

    private func endPress() {
        pressedFolderID = nil
        folderPressStartedAt = nil
    }

    private func beginDrag(_ source: WheelDragSource) {
        let entry: WheelItem
        switch source {
        case .folder:
            entry = .folder(String(localized: "Folder"))
        case let .tile(id):
            guard let tile = availableTiles.first(where: { $0.id == id }) else { return }
            selectSupportedContext(for: tile)
            entry = .action(id)
        case let .entry(id):
            guard let existing = currentEntries.first(where: { $0.id == id }) else { return }
            entry = existing
        }

        originalEntries = currentEntries
        entriesWithoutDragged = originalEntries.filter { $0.id != entry.id }
        let tiles = availableTiles
        let visibleOffsets = entriesWithoutDragged.indices.filter {
            entriesWithoutDragged[$0].supports(selectedPreviewContext, using: tiles)
        }
        insertionOffsets = visibleOffsets + [visibleOffsets.last.map { $0 + 1 } ?? entriesWithoutDragged.count]
        draggedEntry = entry
        dragSource = source
    }

    private func addToWheel(_ entry: WheelItem) {
        resetInteractions()
        setCurrentEntries(currentEntries + [entry])
    }

    private func setCurrentEntries(_ entries: [WheelItem]) {
        configuration.replaceItems(with: WheelItem.replacingItems(
            in: configuration.items, at: folderPath, with: entries
        ))
    }

    private func selectSupportedContext(for tile: WheelTilePresentation) {
        guard !tile.supportedContexts.contains(selectedPreviewContext) else { return }
        if let context = WheelPreviewContext.allCases.first(where: { tile.supportedContexts.contains($0) }) {
            selectedPreviewContext = context
        }
    }
}
