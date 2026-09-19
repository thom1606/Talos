import AppKit
import Observation
import SwiftUI

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
