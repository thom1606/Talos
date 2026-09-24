import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DragWheelController {
    let model = WheelModel()

    private let actionsProvider: ([DraggedFile]) -> [WheelAction]
    private let selectionHandler: (WheelAction, [DraggedFile]) -> Void
    private let hoverHandler: (WheelAction) -> Void
    private let inspector = DraggedFileInspector()
    private var draggedFiles: [DraggedFile] = []
    private var preparedActions: [WheelAction] = []
    private var inspectionTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var panel: NSPanel?
    private var timer: Timer?
    private var pasteboardChangeCount = NSPasteboard(name: .drag).changeCount
    private var dragIsActive = false
    private var fileTypesAreReady = false
    private var isSuppressedUntilNextDrag = false
    private var isReceivingDrag = false
    private var preparedDrop: (action: WheelAction, changeCount: Int)?

    init(
        actionsProvider: @escaping ([DraggedFile]) -> [WheelAction],
        hoverHandler: @escaping (WheelAction) -> Void = { _ in },
        selectionHandler: @escaping (WheelAction, [DraggedFile]) -> Void
    ) {
        self.actionsProvider = actionsProvider
        self.hoverHandler = hoverHandler
        self.selectionHandler = selectionHandler
    }

    func start() {
        guard timer == nil else { return }
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
        endDestinationDrag()
        inspectionTask?.cancel()
        closeTask?.cancel()
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
    }

    func updateHover(_ point: CGPoint) {
        guard model.isVisible else { return }
        let previous = model.hoveredID
        let wasHoveringBack = model.dwellTarget == WheelModel.backTarget
        model.updateHover(at: point)
        let enteredBack = model.dwellTarget == WheelModel.backTarget && !wasHoveringBack
        model.advanceDwell()
        if enteredBack { AppFeedback.shared.hoveredTargetChanged() }
        if let action = model.hoveredAction, previous != action.id {
            AppFeedback.shared.hoveredTargetChanged()
            hoverHandler(action)
        }
    }

    var canDrop: Bool {
        guard
            model.isVisible,
            NSEvent.modifierFlags.contains(.shift),
            let hoveredAction = model.hoveredAction
        else {
            return false
        }

        if case .folder = hoveredAction.destination { return false }
        return true
    }

    func beginDestinationDrag() {
        isReceivingDrag = true
        preparedDrop = nil
    }

    func endDestinationDrag() {
        isReceivingDrag = false
        preparedDrop = nil
    }

    /// Capture AppKit's accepted target before mouse-up/modifier changes can clear hover.
    func prepareDrop(at point: CGPoint, pasteboard: NSPasteboard,
                     shiftIsDown: Bool = NSEvent.modifierFlags.contains(.shift)) -> Bool {
        preparedDrop = nil
        guard isReceivingDrag, model.isVisible, shiftIsDown else { return false }
        updateHover(point)
        guard let action = model.hoveredAction, !action.isFolder else { return false }
        preparedDrop = (action, pasteboard.changeCount)
        return true
    }

    func accept(_ pasteboard: NSPasteboard) -> Bool {
        guard let preparedDrop, preparedDrop.changeCount == pasteboard.changeCount else { return false }
        // Consume once: subsequent callbacks must never dispatch the action twice.
        self.preparedDrop = nil
        let action = preparedDrop.action
        guard pasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) else {
            return false
        }

        // Read the actual drop here so AppKit delivers access to the selected files.
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return false }
        let types = Dictionary(draggedFiles.map { ($0.url, $0.contentType) }, uniquingKeysWith: { first, _ in first })
        let files = urls.map { DraggedFile(url: $0, contentType: types[$0] ?? .data) }
        selectionHandler(action, files)
        isSuppressedUntilNextDrag = true
        dismiss()
        return true
    }

    func tick(pasteboard: NSPasteboard = NSPasteboard(name: .drag),
              primaryMouseButtonIsDown: Bool = NSEvent.pressedMouseButtons & 1 != 0) {
        if pasteboard.changeCount != pasteboardChangeCount {
            pasteboardChangeCount = pasteboard.changeCount
            if primaryMouseButtonIsDown {
                beginDrag(using: pasteboard)
            }
        }

        guard primaryMouseButtonIsDown else {
            // AppKit owns completion while the pointer is over our destination.
            // Mouse-up can be observed before prepare/performDragOperation run.
            guard !isReceivingDrag else { return }
            finishCurrentDrag()
            return
        }

        let shouldShow = dragIsActive
            && fileTypesAreReady
            && NSEvent.modifierFlags.contains(.shift)
            && !isSuppressedUntilNextDrag

        guard shouldShow else {
            if model.isVisible { dismiss() }
            return
        }

        if !model.isVisible {
            show()
        }
        guard let panel else { return }
        // AppKit's drag location is authoritative while the cursor is over the wheel.
        // Alternating it with the polled mouse position can briefly clear and re-enter a tile.
        guard !isReceivingDrag else { return }

        let mouse = NSEvent.mouseLocation
        updateHover(
            CGPoint(
                x: mouse.x - panel.frame.minX,
                y: panel.frame.maxY - mouse.y
            )
        )
    }

    private func beginDrag(using pasteboard: NSPasteboard) {
        endDestinationDrag()
        dragIsActive = pasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        isSuppressedUntilNextDrag = false
        fileTypesAreReady = false
        preparedActions = []
        draggedFiles = []
        inspectionTask?.cancel()
        if model.isVisible { dismiss() }

        guard dragIsActive else { return }
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []

        inspectionTask = Task { [weak self] in
            guard let self else { return }
            let files = await inspector.inspect(urls)
            guard !Task.isCancelled else { return }

            draggedFiles = files
            preparedActions = actionsProvider(files)
            fileTypesAreReady = true
            panel?.contentView?.layoutSubtreeIfNeeded()
        }
    }

    private func finishCurrentDrag() {
        guard dragIsActive || model.isVisible else { return }
        dragIsActive = false
        fileTypesAreReady = false
        isSuppressedUntilNextDrag = false
        inspectionTask?.cancel()
        if model.isVisible { dismiss() }
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
        panel.backgroundColor = .black.withAlphaComponent(0.001)
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

    private func show() {
        guard !preparedActions.isEmpty else { return }
        closeTask?.cancel()
        model.reset(actions: preparedActions)
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

    private func dismiss() {
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
