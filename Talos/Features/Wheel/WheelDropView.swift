import AppKit

final class WheelDropView: NSView {
    weak var controller: DragWheelController?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        controller?.beginDestinationDrag()
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let location = convert(sender.draggingLocation, from: nil)
        controller?.updateHover(location)
        return controller?.canDrop == true ? .copy : []
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        controller?.prepareDrop(at: convert(sender.draggingLocation, from: nil),
                                pasteboard: sender.draggingPasteboard) == true
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { controller?.endDestinationDrag() }
        return controller?.accept(sender.draggingPasteboard) == true
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        controller?.endDestinationDrag()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        controller?.endDestinationDrag()
    }

    override func wantsPeriodicDraggingUpdates() -> Bool {
        true
    }
}
