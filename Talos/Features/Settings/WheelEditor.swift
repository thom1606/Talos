import AppKit
import SwiftUI
import TalosSDK

struct WheelEditor: View {
    @Bindable var model: ModuleLibraryModel
    @State private var preview = WheelModel()
    @State private var page = 0
    @State private var wheelFrame = CGRect.zero
    @State private var paletteFrame = CGRect.zero
    @State private var paletteFrames: [String: CGRect] = [:]
    @State private var draggedID: String?
    @State private var originalEntries: [WheelEntry] = []
    @State private var draggedEntry: WheelEntry?
    @State private var folderPath: [String] = []
    private let folderPaletteID = "editor.new-folder"
    @State private var draftEntries: [WheelEntry]?
    @State private var dropIndex: Int?
    @State private var dragPoint = CGPoint.zero
    @State private var cancelledDrag = false
    @FocusState private var focused: Bool

    private var entries: [WheelEntry] { WheelEntry.entries(in: model.wheelEntries, path: folderPath) }
    private var displayed: [WheelEntry] { draftEntries ?? entries }
    private var offset: Int { page * 7 }
    private var remaining: Int { max(0, displayed.count - offset) }
    private var hasMore: Bool { remaining > 8 }
    private var visible: [WheelEntry] { Array(displayed.dropFirst(offset).prefix(hasMore ? 7 : 8)) }
    private func title(_ entry: WheelEntry) -> String {
        entry.children != nil ? entry.title : model.paletteActions.first { $0.id == entry.actionID }?.title ?? "Unavailable action"
    }
    private func symbol(_ entry: WheelEntry) -> String {
        entry.children != nil ? "folder" : model.paletteActions.first { $0.id == entry.actionID }?.symbol ?? "square.dashed"
    }
    var body: some View {
        GeometryReader { _ in
            VStack(spacing: 0) {
                Text("Available Actions")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24).padding(.top, 16)
                ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    VStack(spacing: 8) {
                        Image(systemName: "folder").font(.system(size: 21)).frame(width: 26, height: 26)
                        Text("Folder").font(.caption)
                    }
                    .frame(width: 82, height: 76)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("wheelEditor")) } action: { paletteFrames[folderPaletteID] = $0 }
                    .accessibilityLabel("Folder")
                    .accessibilityHint("Use the context menu to add a folder to the wheel")
                    .accessibilityIdentifier("wheel.palette.folder")
                    .contextMenu {
                        Button("Add to wheel", systemImage: "plus.circle") {
                            Task { await model.setWheelEntries(entries + [.folder("Folder")], at: folderPath) }
                        }
                        .accessibilityIdentifier("wheel.add.folder")
                    }
                    ForEach(model.paletteActions) { item in
                        VStack(spacing: 8) {
                            Image(systemName: item.symbol ?? "square.dashed")
                                .font(.system(size: 21)).frame(width: 26, height: 26)
                            Text(item.title).font(.caption).lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 82, height: 76)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("wheelEditor")) } action: { paletteFrames[item.id] = $0 }
                        .help("Drag \(item.title) onto the wheel")
                        .accessibilityLabel(item.title)
                        .accessibilityHint("Use the context menu to add this action to the wheel")
                        .accessibilityIdentifier("wheel.palette.\(item.id)")
                        .contextMenu {
                            Button("Add to wheel", systemImage: "plus.circle") {
                                Task { await model.setWheelEntries(entries + [.action(item.id)], at: folderPath) }
                            }
                            .accessibilityIdentifier("wheel.add.\(item.id)")
                        }
                    }
                }
                .padding(24)
                }
                .frame(height: 124)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("wheelEditor")) } action: { paletteFrame = $0 }
                Text("Wheel")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                ZStack {
                RadialWheel(state: preview, tracksPointer: draggedID == nil, editingActions: true, ghostID: draggedID, removeAction: remove,
                            folderIDs: Set(visible.filter { $0.children != nil }.map(\.id)),
                            renameFolder: { id, title in model.renameFolder(id, title: title) },
                            editorBack: folderPath.isEmpty ? nil : {
                                folderPath.removeLast(); page = 0; refresh()
                            }) { action in
                    if action.id == "editor.more" { page += 1; refresh() }
                    else if entries.contains(where: { $0.id == action.id && $0.children != nil }) {
                        folderPath.append(action.id); page = 0; refresh()
                    }
                }
                .overlay {
                    if displayed.isEmpty && folderPath.isEmpty {
                        Text("Drop an action here").font(.caption).foregroundStyle(.secondary)
                            .frame(width: 220, height: 220)
                            .background(.quaternary.opacity(0.25), in: Circle())
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityIdentifier("wheel.preview")
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("wheelEditor")) } action: { wheelFrame = $0 }
                VStack {
                    Spacer()
                    HStack {
                    if page > 0 {
                        Button("Previous", systemImage: "chevron.left") { page -= 1; refresh() }
                    }
                    Spacer()
                    if hasMore {
                        Button("Next", systemImage: "chevron.right") { page += 1; refresh() }
                    }
                    }
                    .padding(.horizontal, 24).padding(.bottom, 12)
                }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .coordinateSpace(name: "wheelEditor")
        .overlay(alignment: .topLeading) {
            if let entry = draggedEntry, dropIndex == nil {
                VStack(spacing: 6) {
                    Image(systemName: symbol(entry)).font(.title2)
                    Text(title(entry)).font(.caption)
                }
                .frame(width: 76, height: 76)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                .opacity(0.5).position(dragPoint).allowsHitTesting(false)
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("wheelEditor"))
            .onChanged(updateDrag)
            .onEnded { _ in finishDrag() })
        .focusable().focused($focused).focusEffectDisabled()
        .onKeyPress(.escape) {
            guard draggedID != nil else { return .ignored }
            cancelledDrag = true
            clearDrag()
            return .handled
        }
        .onDisappear { clearDrag() }
        .disabled(model.isBusy)
        .onChange(of: model.wheelEntries, initial: true) { if draggedID == nil { refresh() } }
    }

    private func refresh() {
        while draggedID == nil && page > 0 && offset >= displayed.count { page -= 1 }
        var actions = visible.map { TalosAction(id: $0.id, title: title($0), symbol: symbol($0), destination: .window) }
        if hasMore { actions.append(TalosAction(id: "editor.more", title: "More", symbol: "ellipsis", destination: .window)) }
        if !preview.isVisible {
            // Initial layout appears immediately; only later edits animate the segments.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                preview.reset(actions: actions, files: [])
                preview.isVisible = !actions.isEmpty
            }
        } else {
            let hovered = preview.hoveredID
            preview.reset(actions: actions, files: [])
            preview.hoveredID = actions.first { $0.id == hovered }?.id
        }
    }

    private func updateDrag(_ value: DragGesture.Value) {
        guard !cancelledDrag, !model.isBusy else { return }
        if draggedID == nil {
            let start = value.startLocation
            if paletteFrame.contains(start), let item = paletteFrames.first(where: { $0.value.contains(start) }) {
                draggedEntry = item.key == folderPaletteID ? .folder("Folder") : .action(item.key)
                draggedID = draggedEntry?.id
            } else {
                let point = CGPoint(x: start.x - wheelFrame.minX, y: start.y - wheelFrame.minY)
                if let index = WheelGeometry.index(at: point, count: preview.actions.count),
                   preview.actions[index].id != "editor.more" {
                    draggedID = preview.actions[index].id
                    draggedEntry = entries.first { $0.id == draggedID }
                }
            }
            guard draggedID != nil else { return }
            originalEntries = entries
            focused = true
        }
        guard let id = draggedID else { return }
        dragPoint = value.location
        let point = CGPoint(x: value.location.x - wheelFrame.midX, y: value.location.y - wheelFrame.midY)
        let inside = hypot(point.x, point.y) <= WheelGeometry.outer
        var items = originalEntries.filter { $0.id != id }
        if inside {
            let count = min(8, max(1, originalEntries.count - offset + (originalEntries.contains { $0.id == id } ? 0 : 1)))
            let angle = atan2(point.y, point.x) + .pi / 2
            let step = 2 * Double.pi / Double(count)
            let slot = Int((angle + step / 2 + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi) / step)
            let index = min(items.count, offset + min(slot, count == 8 && items.count - offset >= 8 ? 7 : slot))
            dropIndex = index
            if let draggedEntry { items.insert(draggedEntry, at: index) }
            NSCursor.closedHand.set()
        } else {
            dropIndex = nil
            if originalEntries.contains(where: { $0.id == id }) { NSCursor.disappearingItem.set() }
            else { NSCursor.operationNotAllowed.set() }
        }
        if draftEntries != items { draftEntries = items; refresh() }
    }

    private func finishDrag() {
        defer { cancelledDrag = false }
        guard let id = draggedID else { return }
        let changed = dropIndex != nil || originalEntries.contains { $0.id == id }
        let result = draftEntries ?? originalEntries
        let path = folderPath
        draggedID = nil
        NSCursor.arrow.set()
        Task {
            if changed { await model.setWheelEntries(result, at: path) }
            clearDrag()
        }
    }

    private func clearDrag() {
        draggedID = nil
        draggedEntry = nil
        draftEntries = nil
        dropIndex = nil
        NSCursor.arrow.set()
        refresh()
    }

    private func remove(_ id: String) {
        Task { await model.setWheelEntries(entries.filter { $0.id != id }, at: folderPath) }
    }
}
