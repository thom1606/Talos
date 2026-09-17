import AppKit
import SwiftUI

/// Visual gaps are decorative; drag targets partition the complete ring.
nonisolated enum WheelGeometry {
    static let size: CGFloat = 336
    static let outer: CGFloat = 146
    static let inner: CGFloat = 57
    static let gap: CGFloat = 6

    static func angle(index: Int, count: Int) -> Double {
        -.pi / 2 + Double(index) * 2 * .pi / Double(count)
    }

    static func index(at point: CGPoint, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let x = point.x - size / 2, y = point.y - size / 2
        let radius = hypot(x, y)
        guard radius >= inner, radius <= outer else { return nil }
        let step = 2 * Double.pi / Double(count)
        let normalized = (atan2(y, x) + .pi / 2 + step / 2 + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
        return Int(normalized / step) % count
    }
}

nonisolated struct WheelSegment: Shape {
    var angle: Double
    var half: Double

    init(angle: Double, count: Int) {
        self.angle = angle
        half = .pi / Double(max(1, count))
    }

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(angle, half) }
        set { angle = newValue.first; half = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = WheelGeometry.outer, inner = WheelGeometry.inner
        let rounding: CGFloat = 11
        // Offset each radial boundary by half the gap in points. A constant
        // angular inset would widen with radius instead of making parallel edges.
        func boundary(_ radius: CGFloat, end: Bool) -> Double {
            let inset = asin(WheelGeometry.gap / (2 * radius))
            return angle + (end ? half - inset : -half + inset)
        }
        func point(_ radius: CGFloat, _ a: Double) -> CGPoint {
            CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
        }
        let outerStart = boundary(outer, end: false)
        let outerEnd = boundary(outer, end: true)
        let innerStart = boundary(inner, end: false)
        let innerEnd = boundary(inner, end: true)
        var p = Path()
        p.move(to: point(outer, outerStart + rounding / outer))
        p.addArc(center: center, radius: outer, startAngle: .radians(outerStart + rounding / outer), endAngle: .radians(outerEnd - rounding / outer), clockwise: false)
        p.addQuadCurve(to: point(outer - rounding, boundary(outer - rounding, end: true)), control: point(outer, outerEnd))
        p.addLine(to: point(inner + rounding, boundary(inner + rounding, end: true)))
        p.addQuadCurve(to: point(inner, innerEnd - rounding / inner), control: point(inner, innerEnd))
        p.addArc(center: center, radius: inner, startAngle: .radians(innerEnd - rounding / inner), endAngle: .radians(innerStart + rounding / inner), clockwise: true)
        p.addQuadCurve(to: point(inner + rounding, boundary(inner + rounding, end: false)), control: point(inner, innerStart))
        p.addLine(to: point(outer - rounding, boundary(outer - rounding, end: false)))
        p.addQuadCurve(to: point(outer, outerStart + rounding / outer), control: point(outer, outerStart))
        p.closeSubpath()
        return p
    }
}

/// Keep the centre glass on the same canvas as the surrounding glass segments.
nonisolated private struct WheelCentre: Shape {
    func path(in rect: CGRect) -> Path {
        Circle().path(in: CGRect(x: rect.midX - 44, y: rect.midY - 44, width: 88, height: 88))
    }
}

struct RadialWheel: View {
    @Bindable var state: WheelModel
    var tracksPointer = true
    var editingActions = false
    var ghostID: String?
    var removeAction: ((String) -> Void)?
    var folderIDs: Set<String> = []
    var renameFolder: ((String, String) -> Void)?
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
                if editingActions && folderIDs.contains(action.id) {
                    let angle = WheelGeometry.angle(index: index, count: state.actions.count)
                    WheelFolderName(title: action.title) { renameFolder?(action.id, $0) }
                        .frame(width: 82, height: 18)
                        .opacity(action.id == ghostID ? 0.5 : 1)
                        .offset(y: 15)
                        .modifier(WheelOrbit(angle: angle))
                }
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
        let tile = Button { select(action) } label: {
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
                            .opacity(editingActions && folderIDs.contains(action.id) ? 0 : 1)
                    }
                    .foregroundStyle(selected && !editingActions ? Color.white : Color.primary)
                    .opacity(action.id == ghostID ? 0.5 : 1)
                    .modifier(WheelOrbit(angle: angle))
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .accessibilityHint(action.isSubmenu ? "Opens more actions" : "Opens action")
        if editingActions && action.id != "editor.more" {
            tile
                .contextMenu {
                    Button("Remove from wheel", systemImage: "minus.circle") { removeAction?(action.id) }
                }
        } else {
            tile
        }
    }
}

extension TalosAction {
    var isSubmenu: Bool {
        if case .submenu = destination { return true }
        return false
    }
}

/// Clear Liquid Glass samples the desktop directly instead of stacking opaque materials.
private struct WheelGlass<S: Shape>: ViewModifier {
    let shape: S
    let selected: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(selected ? Color.accentColor : Color(nsColor: .windowBackgroundColor), in: shape)
        } else {
            content.glassEffect(
                .clear.tint(selected ? Color.accentColor : nil),
                in: shape
            )
        }
    }
}

/// A detached arc follows the tile's outer edge; the centre uses an inset ring.
nonisolated struct WheelProgressArc: Shape {
    var angle: Double = -.pi / 2
    var count: Int? = nil

    func path(in rect: CGRect) -> Path {
        let radius = count == nil ? min(rect.width, rect.height) / 2 - 5 : WheelGeometry.outer + 9
        let half = count.map { Double.pi / Double($0) - 0.06 } ?? Double.pi
        let start = count == nil ? angle : angle - half
        let end = count == nil ? angle + 2 * .pi : angle + half
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                    startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        return path
    }
}

/// The same deadline drives the progress stroke and submenu/back navigation.
private struct DwellProgress<S: Shape>: View {
    let state: WheelModel
    let target: String
    let shape: S
    var color: Color = .white
    var lineWidth: CGFloat = 3

    var body: some View {
        TimelineView(.animation(paused: state.dwellTarget != target)) { context in
            let active = state.dwellTarget == target
            let progress = active ? state.dwellProgress(at: context.date) : 0
            ZStack {
                shape.stroke(color.opacity(0.25), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                shape.trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
            .opacity(active ? 1 : 0)
            .transaction { $0.animation = nil }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Separate from the tile button so clicking the name edits it instead of opening the folder.
private struct WheelFolderName: NSViewRepresentable {
    let title: String
    let commit: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(commit: commit) }

    func makeNSView(context: Context) -> FolderNameEditor {
        let editor = FolderNameEditor(frame: NSRect(x: 0, y: 0, width: 82, height: 18))
        editor.isRichText = false
        editor.isEditable = true
        editor.isSelectable = true
        editor.drawsBackground = false
        editor.focusRingType = .none
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = false
        editor.textContainerInset = NSSize(width: 0, height: 2)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.maximumNumberOfLines = 1
        editor.textContainer?.lineBreakMode = .byClipping
        editor.textContainer?.lineFragmentPadding = 2
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.font = .systemFont(ofSize: 9, weight: .semibold)
        editor.defaultParagraphStyle = FolderNameFormat.attributes[.paragraphStyle] as? NSParagraphStyle
        editor.typingAttributes = FolderNameFormat.attributes
        editor.setAccessibilityLabel("Folder name")
        editor.setAccessibilityHelp("Type a name for this action folder")
        editor.delegate = context.coordinator
        return editor
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FolderNameEditor, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 82, height: 18)
    }

    func updateNSView(_ editor: FolderNameEditor, context: Context) {
        context.coordinator.commit = commit
        guard editor.window?.firstResponder !== editor else { return }
        editor.textStorage?.setAttributedString(NSAttributedString(
            string: FolderNameFormat.fitted(title).uppercased(), attributes: FolderNameFormat.attributes))
        editor.typingAttributes = FolderNameFormat.attributes
        editor.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var commit: (String) -> Void
        init(commit: @escaping (String) -> Void) { self.commit = commit }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            commit(editor.string.uppercased())
            editor.needsDisplay = true
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            let value = FolderNameFormat.fitted(editor.string.trimmingCharacters(in: .whitespacesAndNewlines)).uppercased()
            commit(value)
            editor.textStorage?.setAttributedString(NSAttributedString(string: value, attributes: FolderNameFormat.attributes))
            editor.typingAttributes = FolderNameFormat.attributes
            editor.needsDisplay = true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            textView.window?.makeFirstResponder(nil)
            return true
        }
    }
}

private enum FolderNameFormat {
    static var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.minimumLineHeight = 12
        paragraph.maximumLineHeight = 12
        return [.font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                .kern: 0.2, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }

    static func fits(_ text: String) -> Bool {
        text.uppercased().count <= 16 &&
        (text.uppercased() as NSString).size(withAttributes: attributes).width <= 78
    }

    static func fitted(_ text: String) -> String {
        var value = text.components(separatedBy: .newlines).joined(separator: " ")
        while !fits(value) { value.removeLast() }
        return value
    }
}

/// Limit the incoming insertion, leaving existing text and its cursor position intact.
private final class FolderNameEditor: NSTextView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 18) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        var attributes = FolderNameFormat.attributes
        attributes[.foregroundColor] = NSColor.placeholderTextColor
        let placeholder = NSAttributedString(string: "FOLDER", attributes: attributes)
        placeholder.draw(in: NSRect(x: 2, y: textContainerOrigin.y, width: bounds.width - 4, height: 14))
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard let incoming = (insertString as? String) ?? (insertString as? NSAttributedString)?.string else { return }
        let range = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        guard let selection = Range(range, in: string) else { return }
        let before = String(string[..<selection.lowerBound])
        let after = String(string[selection.upperBound...])
        var insertion = incoming.components(separatedBy: .newlines).joined(separator: " ")
        while !insertion.isEmpty && !FolderNameFormat.fits(before + insertion + after) { insertion.removeLast() }
        guard !insertion.isEmpty || incoming.isEmpty else { return }
        super.insertText(insertion, replacementRange: range)
    }
}

/// Labels follow the same interpolated angle as the segment, along the circle.
private struct WheelOrbit: AnimatableModifier {
    var angle: Double
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content.offset(x: cos(angle) * 103, y: sin(angle) * 103)
    }
}
