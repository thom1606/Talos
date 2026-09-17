import AppKit
import SwiftUI
import TalosSDK

@MainActor
final class DragWheelController {
    let state = WheelModel()
    private let actionsProvider: ([ModuleFile]) -> [TalosAction]
    private let inspector = FileInspector()
    private var dragFiles: [ModuleFile] = []
    private var inspection: Task<Void, Never>?
    private var typesReady = false
    private var panel: NSPanel?
    private var timer: Timer?
    private var pasteboardCount = NSPasteboard(name: .drag).changeCount
    private var dragIsActive = false
    private var suppressed = false
    private var closeTask: Task<Void, Never>?

    init(actionsProvider: @escaping ([ModuleFile]) -> [TalosAction]) {
        self.actionsProvider = actionsProvider
    }

    func start() {
        guard timer == nil else { return }
        // Poll public mouse/modifier state, without a global keyboard event tap or Accessibility access.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        inspection?.cancel()
        timer?.invalidate()
        timer = nil
        closeTask?.cancel()
        panel?.orderOut(nil)
    }

    private func tick() {
        let pasteboard = NSPasteboard(name: .drag)
        let down = NSEvent.pressedMouseButtons & 1 != 0
        if pasteboard.changeCount != pasteboardCount {
            pasteboardCount = pasteboard.changeCount
            if down {
                dragIsActive = pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
                suppressed = false
                typesReady = false
                dragFiles = []
                inspection?.cancel()
                let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
                inspection = Task { [weak self] in
                    guard let self else { return }
                    let files = await inspector.inspect(urls)
                    guard !Task.isCancelled else { return }
                    dragFiles = files
                    typesReady = true
                }
            }
        }
        guard down else {
            dragIsActive = false
            inspection?.cancel()
            typesReady = false
            suppressed = false
            if state.isVisible { dismiss() }
            return
        }
        let shift = NSEvent.modifierFlags.contains(.shift)
        guard dragIsActive, typesReady, shift, !suppressed else {
            if state.isVisible { dismiss() }
            return
        }
        if !state.isVisible { show() }
        guard let panel else { return }
        let location = NSEvent.mouseLocation
        updateHover(CGPoint(x: location.x - panel.frame.minX, y: panel.frame.maxY - location.y))
    }

    private func show() {
        closeTask?.cancel()
        let matching = actionsProvider(dragFiles)
        guard !matching.isEmpty else { return }
        state.reset(actions: matching, files: dragFiles.map(\.url))
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: WheelGeometry.size, height: WheelGeometry.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            // Give the entire destination a backing surface, including transparent glass gaps.
            panel.backgroundColor = .black.withAlphaComponent(0.01)
            panel.hasShadow = false
            panel.level = .popUpMenu
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let surface = NSView(frame: NSRect(x: 0, y: 0, width: WheelGeometry.size, height: WheelGeometry.size))
            let host = NSHostingView(rootView: RadialWheel(state: state, tracksPointer: false, select: { _ in }))
            host.frame = surface.bounds
            host.autoresizingMask = [.width, .height]
            surface.addSubview(host)

            // A separate topmost AppKit surface owns every drag event. SwiftUI text,
            // symbols, buttons and glass never participate in drag hit testing.
            let destination = WheelDropView(frame: surface.bounds)
            destination.autoresizingMask = [.width, .height]
            destination.controller = self
            surface.addSubview(destination)
            panel.contentView = surface
            self.panel = panel
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: mouse.x - 500, y: mouse.y - 500, width: 1000, height: 1000)
        let size = WheelGeometry.size
        let origin = CGPoint(x: min(max(mouse.x - size / 2, frame.minX), frame.maxX - size), y: min(max(mouse.y - size / 2, frame.minY), frame.maxY - size))
        panel?.setFrameOrigin(origin)
        panel?.orderFrontRegardless()
        state.clearHover()
        state.isVisible = true
    }

    func updateHover(_ point: CGPoint) {
        guard state.isVisible else { return }
        let previous = state.hoveredID
        state.updateHover(at: point)
        if let current = state.hoveredID, current != previous { SoundService.shared.playHover() }
        state.advanceDwell()
    }

    var canDrop: Bool {
        state.isVisible && NSEvent.modifierFlags.contains(.shift) && state.hovered.map { !$0.isSubmenu } == true
    }

    func accept(_ pasteboard: NSPasteboard) -> Bool {
        guard canDrop, let action = state.hovered,
              let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        select(action, files: urls)
        suppressed = true
        dismiss()
        return true
    }

    func select(_ action: TalosAction, files: [URL]) {
        switch action.destination {
        case .submenu(let children): state.enter(children)
        case .handler(let handler): handler(files)
        case .window: break // Editor-only placeholder; runtime actions always have a handler.
        }
    }

    private func dismiss() {
        state.isVisible = false
        state.hoveredID = nil
        state.clearHover()
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }
}

final class WheelDropView: NSView {
    weak var controller: DragWheelController?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let location = convert(sender.draggingLocation, from: nil)
        controller?.updateHover(CGPoint(x: location.x, y: isFlipped ? location.y : bounds.height - location.y))
        return controller?.canDrop == true ? .copy : []
    }
    // The native destination owns the whole panel, independent of SwiftUI tile shapes.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        draggingUpdated(sender) == .copy
    }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        // Resolve the final drop location rather than using the last polling tick.
        guard draggingUpdated(sender) == .copy else { return false }
        return controller?.accept(sender.draggingPasteboard) == true
    }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }
}
