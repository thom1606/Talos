import AppKit
import UniformTypeIdentifiers

/// Owns inspection, late mouse-up callbacks and one-time consumption for one drag.
@MainActor
final class WheelDragSession {
    struct Content {
        let files: [DraggedFile]
        let actions: [WheelKind: [WheelAction]]
    }

    enum PollResult { case began, tracking, waiting, ended }
    private enum State { case idle, inspecting, ready(Content), consumed }

    private let actionsProvider: ([DraggedFile]) -> [WheelKind: [WheelAction]]
    private let inspector = DraggedFileInspector()
    private var state: State = .idle
    private var inspectionTask: Task<Void, Never>?
    private var changeCount = NSPasteboard(name: .drag).changeCount
    private var mouseReleasedAt: Date?
    private var preparedDrop: (action: WheelAction, changeCount: Int)?
    private(set) var isReceiving = false
    private(set) var location: CGPoint?

    var content: Content? {
        if case let .ready(content) = state { return content }
        return nil
    }

    init(actionsProvider: @escaping ([DraggedFile]) -> [WheelKind: [WheelAction]]) {
        self.actionsProvider = actionsProvider
    }

    func poll(_ pasteboard: NSPasteboard, mouseIsDown: Bool, isVisible: Bool, now: Date) -> PollResult {
        var began = false
        if pasteboard.changeCount != changeCount {
            changeCount = pasteboard.changeCount
            if mouseIsDown {
                begin(pasteboard)
                began = true
            }
        }
        if mouseIsDown {
            mouseReleasedAt = nil
            return began ? .began : .tracking
        }
        // AppKit can enter and complete the destination after global mouse-up.
        guard !isReceiving else { return .waiting }
        if isVisible {
            mouseReleasedAt = mouseReleasedAt ?? now
            if now.timeIntervalSince(mouseReleasedAt ?? now) < 0.25 { return .waiting }
        }
        finish()
        return .ended
    }

    func target(for model: WheelModel, shiftIsDown: Bool, optionIsDown: Bool) -> WheelAction? {
        guard model.isVisible, shiftIsDown,
              model.activeWheel == (optionIsDown ? .secondary : .primary),
              let action = model.hoveredAction, action.isEnabled, !action.isFolder else { return nil }
        return action
    }

    func beginDestination() {
        isReceiving = true
        preparedDrop = nil
    }

    func endDestination() {
        isReceiving = false
        preparedDrop = nil
        location = nil
    }

    func trackDestination(_ point: CGPoint) {
        if isReceiving { location = point }
    }

    func invalidateDrop() { preparedDrop = nil }

    func prepareDrop(for model: WheelModel, changeCount: Int, shiftIsDown: Bool, optionIsDown: Bool) -> Bool {
        preparedDrop = nil
        guard isReceiving,
              let action = target(for: model, shiftIsDown: shiftIsDown, optionIsDown: optionIsDown) else { return false }
        preparedDrop = (action, changeCount)
        return true
    }

    func consumeDrop(_ pasteboard: NSPasteboard) -> (action: WheelAction, files: [DraggedFile])? {
        guard let drop = preparedDrop, drop.changeCount == pasteboard.changeCount else { return nil }
        preparedDrop = nil
        // Read the real drop here so AppKit delivers access to the selected files.
        guard let content, let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return nil }
        let types = Dictionary(content.files.map { ($0.url, $0.contentType) }, uniquingKeysWith: { first, _ in first })
        let files = urls.map { DraggedFile(url: $0, contentType: types[$0] ?? .data) }
        state = .consumed
        return (drop.action, files)
    }

    func finish() {
        inspectionTask?.cancel()
        inspectionTask = nil
        state = .idle
        mouseReleasedAt = nil
        endDestination()
    }

    private func begin(_ pasteboard: NSPasteboard) {
        finish()
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return }
        state = .inspecting
        let inspectedChangeCount = changeCount
        inspectionTask = Task { @concurrent [weak self, inspector] in
            let files = await inspector.inspect(urls)
            guard !Task.isCancelled else { return }
            await self?.completeInspection(files, changeCount: inspectedChangeCount)
        }
    }

    private func completeInspection(_ files: [DraggedFile], changeCount: Int) {
        guard case .inspecting = state, self.changeCount == changeCount else { return }
        state = .ready(Content(files: files, actions: actionsProvider(files)))
        inspectionTask = nil
    }
}
