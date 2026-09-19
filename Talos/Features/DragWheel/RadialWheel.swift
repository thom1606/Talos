import AppKit
import SwiftUI

struct RadialWheel: View {
    @Bindable var state: WheelModel
    var tracksPointer = true
    var editingActions = false
    var ghostID: String?
    var removeAction: ((String) -> Void)?
    var folderIDs: Set<String> = []
    var editAction: ((String) -> Void)?
    var openFolder: ((String) -> Void)?
    var editorBack: (() -> Void)?
    var select: (TalosAction) -> Void
    @State private var centreHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if editingActions {
                ForEach(Array(state.actions.enumerated()), id: \.element.id) { index, action in
                    WheelSegment(angle: WheelGeometry.angle(index: index, count: state.actions.count), count: state.actions.count)
                        .fill(state.hoveredID == action.id && folderIDs.contains(action.id)
                              ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
                        .opacity(action.id == ghostID ? 0.5 : 1)
                }
                WheelCentre().fill(centreHovered && editorBack != nil
                                   ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
            } else {
            GlassEffectContainer(spacing: 0) {
                ZStack {
                    ForEach(Array(state.actions.enumerated()), id: \.element.id) { index, action in
                        let shape = WheelSegment(angle: WheelGeometry.angle(index: index, count: state.actions.count), count: state.actions.count)
                        shape.fill(.clear)
                            .modifier(WheelGlass(shape: shape, selected: state.hoveredID == action.id))
                    }
                    WheelCentre().fill(.clear)
                        .modifier(WheelGlass(shape: WheelCentre(), selected: state.dwellTarget == WheelModel.backTarget))
                }
            }
            // A menu change replaces its glass immediately; interpolating old and new
            // contours makes Liquid Glass briefly fuse the separate tiles.
            .id(state.actions.map(\.id))
            .transition(.identity)
            .transaction { $0.animation = nil }
            .allowsHitTesting(false)
            }

            ForEach(Array(state.actions.enumerated()), id: \.element.id) { index, action in
                segment(action, index: index)
            }

            DwellProgress(state: state, target: WheelModel.backTarget, shape: WheelProgressArc())
                .frame(width: 88, height: 88)
                .allowsHitTesting(false)

            Button {
                if let editorBack {
                    SoundService.shared.playWheelCompletion()
                    editorBack()
                } else {
                    state.back()
                }
            } label: {
                VStack(spacing: 5) {
                    if editingActions && editorBack != nil {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 22, weight: .light)).frame(width: 24, height: 24)
                        Text("BACK").font(.system(size: 9, weight: .medium)).tracking(1.5)
                    } else if let hovered = state.hovered {
                        if let symbol = hovered.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 24, height: 24)
                        }
                        let title = folderIDs.contains(hovered.id)
                            && hovered.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "FOLDER" : hovered.title.uppercased()
                        Text(title).font(.system(size: 10, weight: .semibold))
                            .lineLimit(2).multilineTextAlignment(.center)
                    } else if !state.parents.isEmpty {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 22, weight: .light))
                            .frame(width: 24, height: 24)
                        Text("BACK")
                            .font(.system(size: 9, weight: .medium)).tracking(1.5)
                    }
                }
                .frame(width: 88, height: 88)
                .contentShape(Circle())
                .foregroundStyle(state.dwellTarget == WheelModel.backTarget ? Color.white : Color.primary)
                .contentTransition(.opacity)
            }
            .buttonStyle(.plain)
            .onHover { centreHovered = $0 }
            .disabled(state.parents.isEmpty && editorBack == nil)
            .accessibilityLabel(state.parents.isEmpty && editorBack == nil ? "Talos actions" : "Back to previous actions")
        }
        .frame(width: WheelGeometry.size, height: WheelGeometry.size)
        .onContinuousHover { phase in
            guard tracksPointer else { return }
            switch phase {
            case .active(let point): state.updateHover(at: point)
            case .ended: state.clearHover()
            }
        }
        .task(id: state.dwellStarted) {
            guard let started = state.dwellStarted else { return }
            let remaining = max(0, WheelModel.dwellDuration - Date.now.timeIntervalSince(started))
            do { try await Task.sleep(for: .seconds(remaining)) }
            catch { return }
            state.advanceDwell()
        }
        .scaleEffect(editingActions || state.isVisible ? 1 : (reduceMotion ? 1 : 0.76))
        .opacity(editingActions || state.isVisible ? 1 : 0)
        .animation(editingActions ? nil : (reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.78)), value: state.isVisible)
        .animation(.easeInOut(duration: 0.14), value: state.hoveredID)
        .animation(.easeInOut(duration: 0.14), value: centreHovered)
        .animation(editingActions && !reduceMotion ? .smooth(duration: 0.24) : nil, value: state.actions.map(\.id))
    }

    @ViewBuilder private func segment(_ action: TalosAction, index: Int) -> some View {
        let angle = WheelGeometry.angle(index: index, count: state.actions.count)
        let shape = WheelSegment(angle: angle, count: state.actions.count)
        let selected = state.hoveredID == action.id
        let tile = Button { activate(action) } label: {
            shape
                .fill(.clear)
                .overlay {
                    if action.isSubmenu {
                        DwellProgress(state: state, target: action.id,
                                      shape: WheelProgressArc(angle: angle, count: state.actions.count),
                                      color: .accentColor, lineWidth: 2)
                    }
                }
                .overlay {
                    VStack(spacing: 7) {
                        if let symbol = action.symbol {
                            Image(systemName: symbol)
                                .font(.system(size: 19, weight: .regular))
                                .frame(width: 24, height: 24)
                        }
                        Text(action.title.uppercased())
                            .font(.system(size: action.symbol == nil ? 12 : 9, weight: .semibold))
                            .tracking(0.2)
                            .lineLimit(1)
                            .frame(height: 14)
                    }
                    .foregroundStyle(selected && !editingActions ? Color.white : Color.primary)
                    .opacity(action.id == ghostID ? 0.5 : 1)
                    .modifier(WheelOrbit(angle: angle))
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .accessibilityHint(editingActions && action.id != "editor.more"
                           ? (folderIDs.contains(action.id) ? "Opens name and settings. Press and hold to open this folder." : "Opens name and settings")
                           : (action.isSubmenu ? "Opens more actions" : "Opens action"))
        if editingActions && action.id != "editor.more" {
            if folderIDs.contains(action.id) {
                tile
                    .highPriorityGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in openFolder?(action.id) })
                    .accessibilityAction(named: "Open folder") { openFolder?(action.id) }
                    .contextMenu {
                        Button("Remove from wheel", systemImage: "minus.circle") { removeAction?(action.id) }
                    }
            } else {
                tile
                    .contextMenu {
                        Button("Remove from wheel", systemImage: "minus.circle") { removeAction?(action.id) }
                    }
            }
        } else {
            tile
        }
    }

    private func activate(_ action: TalosAction) {
        if editingActions && action.id != "editor.more" {
            editAction?(action.id)
        } else {
            select(action)
        }
    }
}

extension TalosAction {
    var isSubmenu: Bool {
        if case .submenu = destination { return true }
        return false
    }
}
