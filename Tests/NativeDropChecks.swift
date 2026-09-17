import AppKit
import SwiftUI

@main
struct NativeDropChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let state = WheelModel()
        state.reset(actions: WheelFixtures.actions, files: [])
        state.isVisible = true
        let bounds = NSRect(x: 0, y: 0, width: WheelGeometry.size, height: WheelGeometry.size)
        let surface = NSView(frame: bounds)
        let host = NSHostingView(rootView: RadialWheel(state: state, tracksPointer: false, select: { _ in }))
        host.frame = bounds
        surface.addSubview(host)
        let destination = WheelDropView(frame: bounds)
        surface.addSubview(destination)
        surface.layoutSubtreeIfNeeded()

        // Exercise the real AppKit hierarchy above SwiftUI, across labels, icons,
        // gaps and the centre. No point may resolve to a hosting-view descendant.
        for x in stride(from: 1, to: 336, by: 3) {
            for y in stride(from: 1, to: 336, by: 3) {
                precondition(surface.hitTest(NSPoint(x: x, y: y)) === destination,
                             "Drag hit escaped native overlay at \(x), \(y)")
            }
        }
        precondition(surface.hitTest(NSPoint(x: -1, y: -1)) == nil)
        precondition(destination.registeredDraggedTypes.contains(.fileURL))
        print("Passed: native drag overlay owns labels, icons, gaps and centre")
    }
}
