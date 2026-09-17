import AppKit
import Observation
import SwiftUI

nonisolated struct TaskPillPresentation: Equatable {
    enum Phase: Equatable {
        case running
        case completed
        case failed
    }

    let id: UUID
    let title: String
    var message: String
    var progress: Double
    var phase: Phase
}

@MainActor
@Observable
final class TaskPillModel {
    private(set) var presentation: TaskPillPresentation?
    @ObservationIgnored private var active: [UUID: TaskPillPresentation] = [:]
    @ObservationIgnored private var order: [UUID] = []
    @ObservationIgnored private var dismissal: Task<Void, Never>?
    @ObservationIgnored private let completionDelay: Duration

    init(completionDelay: Duration = .seconds(1.25)) {
        self.completionDelay = completionDelay
    }

    func start(id: UUID, title: String) {
        dismissal?.cancel()
        let item = TaskPillPresentation(
            id: id,
            title: title,
            message: title,
            progress: 0,
            phase: .running
        )
        active[id] = item
        order.removeAll { $0 == id }
        order.append(id)
        presentation = item
    }

    func update(id: UUID, message: String, progress: Double?) {
        guard var item = active[id] else { return }
        if !message.isEmpty { item.message = message }
        if let progress { item.progress = min(1, max(0, progress)) }
        active[id] = item
        if presentation?.id == id, presentation?.phase == .running {
            presentation = item
        }
    }

    func finish(id: UUID, message: String, failed: Bool) {
        guard var item = active.removeValue(forKey: id) else { return }
        order.removeAll { $0 == id }
        guard presentation?.id == id else { return }

        dismissal?.cancel()
        if !message.isEmpty { item.message = message }
        item.progress = failed ? item.progress : 1
        item.phase = failed ? .failed : .completed
        presentation = item
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: self?.completionDelay ?? .seconds(1.25)) }
            catch { return }
            self?.showLatest()
        }
    }

    func stop() {
        dismissal?.cancel()
        active.removeAll()
        order.removeAll()
        presentation = nil
    }

    private func showLatest() {
        dismissal = nil
        presentation = order.last.flatMap { active[$0] }
    }
}

@MainActor
final class TaskPillController {
    private let model: TaskPillModel
    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?

    init(model: TaskPillModel) {
        self.model = model
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 84),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isExcludedFromWindowsMenu = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: TaskPillView(model: model) { [weak self] visible in
            self?.setVisible(visible)
        })
    }

    func start() {
        setVisible(model.presentation != nil)
    }

    func stop() {
        hideTask?.cancel()
        model.stop()
        panel.orderOut(nil)
    }

    private func setVisible(_ visible: Bool) {
        hideTask?.cancel()
        if visible {
            positionPanel()
            panel.orderFrontRegardless()
        } else {
            hideTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(240)) }
                catch { return }
                self?.panel.orderOut(nil)
            }
        }
    }

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(CGPoint(
            x: frame.midX - panel.frame.width / 2,
            y: frame.minY + 18
        ))
    }
}

private struct TaskPillView: View {
    @Bindable var model: TaskPillModel
    let visibilityChanged: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let presentation = model.presentation {
                TaskPillContent(presentation: presentation)
                    .id(presentation.id)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .offset(y: 14).combined(with: .scale(scale: 0.82)).combined(with: .opacity),
                        removal: .offset(y: 8).combined(with: .scale(scale: 0.92)).combined(with: .opacity)
                    ))
            }
        }
        .frame(width: 460, height: 84)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.4, dampingFraction: 0.78),
                   value: model.presentation?.id)
        .onChange(of: model.presentation != nil, initial: true) { _, visible in
            visibilityChanged(visible)
        }
    }
}

private struct TaskPillContent: View {
    let presentation: TaskPillPresentation
    @State private var revealsText = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: revealsText ? 10 : 0) {
            icon
                .frame(width: 20, height: 20)
                .contentTransition(.symbolEffect(.replace))

            if revealsText {
                Text(presentation.message)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(height: 46)
        .fixedSize(horizontal: true, vertical: false)
        .background {
            if reduceTransparency {
                Capsule().fill(.regularMaterial)
            }
        }
        .glassEffect(reduceTransparency ? .identity : .regular, in: Capsule())
        .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.28), value: revealsText)
        .animation(.easeInOut(duration: 0.18), value: presentation.phase)
        .task {
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(170))
            }
            withAnimation { revealsText = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var icon: some View {
        switch presentation.phase {
        case .running:
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.red)
        }
    }

    private var accessibilityLabel: String {
        switch presentation.phase {
        case .running: "\(presentation.title), \(presentation.message), \(Int(presentation.progress * 100)) percent"
        case .completed: "\(presentation.title) completed"
        case .failed: "\(presentation.title) failed: \(presentation.message)"
        }
    }
}
