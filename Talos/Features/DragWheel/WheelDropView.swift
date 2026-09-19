import AppKit

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
