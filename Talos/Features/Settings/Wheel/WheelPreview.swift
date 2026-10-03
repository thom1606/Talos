import SwiftUI

struct WheelPreview: View {
    let entries: [WheelItem]
    let tiles: [WheelTilePresentation]
    let ghostEntryID: WheelItem.ID?
    let pressedFolderID: WheelItem.ID?
    let folderPressStartedAt: Date?
    let canNavigateBack: Bool
    let onEdit: (WheelItem.ID) -> Void
    let onOpenFolder: (WheelItem.ID) -> Void
    let onRemove: (WheelItem.ID) -> Void
    let onNavigateBack: () -> Void
    let interactionModel: WheelSettingsViewModel

    @State private var hoveredEntryID: WheelItem.ID?
    @State private var isHoveringBack = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var entryCount: Int {
        max(entries.count, 1)
    }

    var body: some View {
        ZStack {
            ForEach(entries.enumerated(), id: \.element.id) { index, entry in
                let angle = WheelLayout.editor.angle(index: index, count: entryCount, reservesBack: canNavigateBack)
                let shape = WheelSegment(angle: angle, count: entryCount, reservesBack: canNavigateBack, layout: .editor)

                shape
                    .fill(
                        hoveredEntryID == entry.id
                            ? TalosAppearance.accent.opacity(0.18)
                            : Color.primary.opacity(0.05)
                    )
                    .overlay {
                        shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
                    .opacity(entry.id == ghostEntryID ? 0.5 : 1)
            }

            Circle()
                .fill(Color.primary.opacity(0.05))
                .overlay {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
                .frame(width: WheelLayout.editor.centerRadius * 2,
                       height: WheelLayout.editor.centerRadius * 2)

            ForEach(entries.enumerated(), id: \.element.id) { index, entry in
                WheelPreviewTile(
                    entry: entry,
                    title: entry.title(using: tiles),
                    symbolName: entry.symbolName(using: tiles),
                    angle: WheelLayout.editor.angle(index: index, count: entryCount, reservesBack: canNavigateBack),
                    entryCount: entryCount,
                    reservesBack: canNavigateBack,
                    isGhost: entry.id == ghostEntryID,
                    isPressingFolder: entry.id == pressedFolderID,
                    folderPressStartedAt: folderPressStartedAt,
                    onEdit: {
                        onEdit(entry.id)
                    },
                    onOpenFolder: {
                        onOpenFolder(entry.id)
                    },
                    onRemove: {
                        onRemove(entry.id)
                    }
                )
                .contentShape(WheelSegment(
                    angle: WheelLayout.editor.angle(index: index, count: entryCount, reservesBack: canNavigateBack),
                    count: entryCount,
                    reservesBack: canNavigateBack,
                    layout: .editor
                ))
                .modifier(WheelEditorInteraction(
                    source: .entry(entry.id),
                    model: interactionModel,
                    folderID: entry.isFolder ? entry.id : nil
                ))
            }

            if let entry = entries.first(where: { $0.id == hoveredEntryID }),
               WheelLayout.editor.contentWidth(count: entryCount, maximum: 58, reservesBack: canNavigateBack) < 48 {
                Text(entry.title(using: tiles))
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(width: 68)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            if canNavigateBack {
                backButton
            }
        }
        .frame(width: WheelLayout.editor.size, height: WheelLayout.editor.size)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wheel.preview")
        .onContinuousHover { phase in
            switch phase {
            case let .active(point):
                hoveredEntryID = WheelLayout.editor.index(at: point, count: entryCount, reservesBack: canNavigateBack)
                    .flatMap { index in
                        entries.indices.contains(index) ? entries[index].id : nil
                    }
                isHoveringBack = canNavigateBack && WheelLayout.editor.isBack(at: point)
            case .ended:
                hoveredEntryID = nil
                isHoveringBack = false
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: hoveredEntryID)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: isHoveringBack)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: entries.map(\.id))
        .onChange(of: entries.map(\.id)) {
            if !entries.contains(where: { $0.id == hoveredEntryID }) { hoveredEntryID = nil }
            isHoveringBack = false
        }
    }

    private var backButton: some View {
        let shape = WheelSegment(angle: WheelLayout.editor.backAngle, span: WheelLayout.editor.backSpan, layout: .editor)

        return Button(action: onNavigateBack) {
            shape
                .fill(isHoveringBack ? TalosAppearance.accent.opacity(0.18) : Color.primary.opacity(0.05))
                .overlay {
                    shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
                .overlay {
                    WheelTileLabel(
                        title: String(localized: "Back"),
                        symbolName: "arrow.uturn.backward",
                        layout: .editor,
                        count: 4,
                        isEditor: true
                    )
                    .foregroundStyle(Color.primary)
                    .offset(y: WheelLayout.editor.contentRadius)
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to parent folder")
    }
}

private struct WheelPreviewTile: View {
    let entry: WheelItem
    let title: String
    let symbolName: String
    let angle: Double
    let entryCount: Int
    let reservesBack: Bool
    let isGhost: Bool
    let isPressingFolder: Bool
    let folderPressStartedAt: Date?
    let onEdit: () -> Void
    let onOpenFolder: () -> Void
    let onRemove: () -> Void

    private static let folderProgressDelay: TimeInterval = 0.2

    var body: some View {
        if entry.isFolder {
            tile
                .accessibilityAction(named: "Open folder", onOpenFolder)
        } else {
            tile
        }
    }

    private var tile: some View {
        let shape = WheelSegment(angle: angle, count: entryCount, reservesBack: reservesBack, layout: .editor)

        return Button(action: onEdit) {
            shape
                .fill(.clear)
                .overlay {
                    if entry.isFolder {
                        FolderOpenProgress(
                            isActive: isPressingFolder,
                            startedAt: folderPressStartedAt,
                            delay: Self.folderProgressDelay,
                            duration: WheelEditorInteraction.folderOpenDuration,
                            shape: WheelProgressArc(
                                angle: angle,
                                span: WheelLayout.editor.span(count: entryCount, reservesBack: reservesBack),
                                layout: .editor
                            )
                        )
                    }
                }
                .overlay {
                    WheelTileLabel(
                        title: title,
                        symbolName: symbolName,
                        layout: .editor,
                        count: entryCount,
                        isEditor: true,
                        reservesBack: reservesBack
                    )
                    .foregroundStyle(Color.primary)
                    .opacity(isGhost ? 0.5 : 1)
                    .offset(
                        x: cos(angle) * WheelLayout.editor.contentRadius,
                        y: sin(angle) * WheelLayout.editor.contentRadius
                    )
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(
            entry.isFolder
                ? String(localized: "Press to edit. Press and hold to open.")
                : String(localized: "Press to edit settings.")
        )
        .contextMenu {
            Button("Remove from wheel", systemImage: "minus.circle", action: onRemove)
        }
    }

}

private struct FolderOpenProgress<S: Shape>: View {
    let isActive: Bool
    let startedAt: Date?
    let delay: TimeInterval
    let duration: TimeInterval
    let shape: S

    var body: some View {
        TimelineView(.animation(paused: !isActive)) { context in
            let elapsed = startedAt.map {
                context.date.timeIntervalSince($0)
            } ?? 0
            let progressDuration = max(duration - delay, .leastNonzeroMagnitude)
            let progress = min(1, max(0, (elapsed - delay) / progressDuration))
            let isVisible = isActive && elapsed >= delay

            ZStack {
                shape.stroke(
                    TalosAppearance.accent.opacity(0.25),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                shape.trim(from: 0, to: progress)
                    .stroke(
                        TalosAppearance.accent,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
            }
            .opacity(isVisible ? 1 : 0)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
