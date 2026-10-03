import AppKit
import SwiftUI

@MainActor
final class DragWheelController {
    let model = WheelModel()

    private let session: WheelDragSession
    private let selectionHandler: (WheelAction, [DraggedFile]) -> Void
    private let hoverHandler: (WheelAction) -> Void
    private var closeTask: Task<Void, Never>?
    private var panel: NSPanel?
    private var timer: Timer?

    init(
        actionsProvider: @escaping ([DraggedFile]) -> [WheelKind: [WheelAction]],
        hoverHandler: @escaping (WheelAction) -> Void = { _ in },
        selectionHandler: @escaping (WheelAction, [DraggedFile]) -> Void
    ) {
        session = WheelDragSession(actionsProvider: actionsProvider)
        self.hoverHandler = hoverHandler
        self.selectionHandler = selectionHandler
    }

    func start() {
        guard timer == nil else { return }
        AppFeedback.shared.prepare()
        preparePanel()
        panel?.contentView?.layoutSubtreeIfNeeded()

        let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        session.finish()
        closeTask?.cancel()
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
    }

    func updateHover(_ point: CGPoint, optionIsDown: Bool = NSEvent.modifierFlags.contains(.option)) {
        guard model.isVisible else { return }
        guard selectWheel(optionIsDown ? .secondary : .primary) else { return }
        session.trackDestination(point)
        let previous = model.hoveredID
        let wasHoveringBack = model.dwellTarget == WheelModel.backTarget
        model.updateHover(at: point)
        let enteredBack = model.dwellTarget == WheelModel.backTarget && !wasHoveringBack
        model.advanceDwell()
        if enteredBack { AppFeedback.shared.hoveredTargetChanged() }
        if let action = model.hoveredAction, previous != action.id {
            if action.isEnabled {
                AppFeedback.shared.hoveredTargetChanged()
                hoverHandler(action)
            }
        }
    }

    var canDrop: Bool {
        let modifiers = NSEvent.modifierFlags
        return session.target(for: model, shiftIsDown: modifiers.contains(.shift),
                              optionIsDown: modifiers.contains(.option)) != nil
    }

    func beginDestinationDrag() {
        traceDrag("destination entered")
        session.beginDestination()
    }

    func endDestinationDrag() {
        traceDrag("destination ended")
        session.endDestination()
    }

    /// Capture AppKit's accepted target before mouse-up/modifier changes can clear hover.
    func prepareDrop(at point: CGPoint, pasteboard: NSPasteboard,
                     shiftIsDown: Bool = NSEvent.modifierFlags.contains(.shift),
                     optionIsDown: Bool = NSEvent.modifierFlags.contains(.option)) -> Bool {
        traceDrag("prepare receiving=\(session.isReceiving) visible=\(model.isVisible) shift=\(shiftIsDown) point=\(point)")
        if session.isReceiving, model.isVisible, shiftIsDown {
            updateHover(point, optionIsDown: optionIsDown)
        }
        return session.prepareDrop(for: model, changeCount: pasteboard.changeCount,
                                   shiftIsDown: shiftIsDown, optionIsDown: optionIsDown)
    }

    func accept(_ pasteboard: NSPasteboard) -> Bool {
        guard let drop = session.consumeDrop(pasteboard) else { return false }
        traceDrag("dispatch files=\(drop.files.count)")
        selectionHandler(drop.action, drop.files)
        dismiss()
        return true
    }

    func tick(pasteboard: NSPasteboard = NSPasteboard(name: .drag),
              primaryMouseButtonIsDown: Bool = NSEvent.pressedMouseButtons & 1 != 0,
              now: Date = .now) {
        switch session.poll(pasteboard, mouseIsDown: primaryMouseButtonIsDown, isVisible: model.isVisible, now: now) {
        case .began:
            if model.isVisible { dismiss() }
        case .ended:
            if model.isVisible { dismiss() }
            return
        case .waiting:
            return
        case .tracking:
            break
        }

        let modifiers = NSEvent.modifierFlags
        let wheel: WheelKind = modifiers.contains(.option) ? .secondary : .primary
        guard session.content != nil, modifiers.contains(.shift) else {
            if model.isVisible { dismiss() }
            return
        }

        if !model.isVisible {
            show(wheel: wheel)
        } else if !selectWheel(wheel) {
            return
        }
        guard let panel else { return }
        // AppKit's drag location is authoritative while the cursor is over the wheel.
        if session.isReceiving {
            if let location = session.location { updateHover(location, optionIsDown: modifiers.contains(.option)) }
            return
        }
        let mouse = NSEvent.mouseLocation
        updateHover(CGPoint(x: mouse.x - panel.frame.minX, y: panel.frame.maxY - mouse.y),
                    optionIsDown: modifiers.contains(.option))
    }

    private func preparePanel() {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: WheelLayout.runtime.size,
                height: WheelLayout.runtime.size
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        // Keep the whole destination nontransparent to WindowServer hit testing,
        // including the center/gaps while the SwiftUI glass is being rendered.
        panel.backgroundColor = .black.withAlphaComponent(0.01)
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let surface = NSView(
            frame: NSRect(x: 0, y: 0, width: WheelLayout.runtime.size, height: WheelLayout.runtime.size)
        )
        let host = NSHostingView(rootView: RuntimeWheelView(model: model))
        host.frame = surface.bounds
        host.autoresizingMask = [.width, .height]
        surface.addSubview(host)

        let destination = WheelDropView(frame: surface.bounds)
        destination.autoresizingMask = [.width, .height]
        destination.controller = self
        surface.addSubview(destination)

        panel.contentView = surface
        self.panel = panel
    }

    private func traceDrag(_ message: String) {
        #if DEBUG
        guard TalosPreferences.uiTestRunID != nil,
              let path = ProcessInfo.processInfo.environment["TALOS_UI_TEST_DRAG_LOG"],
              let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\(Date()) \(message)\n".utf8))
        } catch { }
        #endif
    }

    @discardableResult
    private func selectWheel(_ wheel: WheelKind) -> Bool {
        guard session.content?.actions[wheel]?.isEmpty == false else {
            session.invalidateDrop()
            if model.isVisible { dismiss() }
            return false
        }
        guard model.activeWheel != wheel else { return true }
        model.switchWheel(to: wheel)
        session.invalidateDrop()
        traceDrag("wheel changed=\(wheel.rawValue) actions=\(model.actions.count)")
        return true
    }

    private func show(wheel: WheelKind) {
        guard let content = session.content, content.actions[wheel]?.isEmpty == false else { return }
        traceDrag("show wheel=\(wheel.rawValue)")
        closeTask?.cancel()
        model.reset(actions: content.actions[.primary] ?? [], secondaryActions: content.actions[.secondary] ?? [], wheel: wheel)
        preparePanel()
        panel?.contentView?.layoutSubtreeIfNeeded()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let availableFrame = screen?.visibleFrame ?? NSRect(
            x: mouse.x - 500,
            y: mouse.y - 500,
            width: 1_000,
            height: 1_000
        )
        let size = WheelLayout.runtime.size
        let origin = CGPoint(
            x: min(max(mouse.x - size / 2, availableFrame.minX), availableFrame.maxX - size),
            y: min(max(mouse.y - size / 2, availableFrame.minY), availableFrame.maxY - size)
        )
        panel?.setFrameOrigin(origin)
        panel?.orderFrontRegardless()
        model.isVisible = true
    }

}

private extension DragWheelController {
    func dismiss() {
        model.isVisible = false
        model.clearHover()
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(220))
            } catch {
                return
            }
            self?.panel?.orderOut(nil)
        }
    }
}
