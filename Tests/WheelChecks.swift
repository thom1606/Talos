import SwiftUI

@main
struct WheelChecks {
    @MainActor static func main() {
        for count in [6, 7, 8] {
            for index in 0..<count {
                let angle = WheelGeometry.angle(index: index, count: count)
                let point = CGPoint(x: 168 + cos(angle) * 103, y: 168 + sin(angle) * 103)
                precondition(WheelGeometry.index(at: point, count: count) == index, "Wrong sector for \(count) actions")
                let shape = WheelSegment(angle: angle, count: count).path(in: CGRect(x: 0, y: 0, width: 336, height: 336))
                precondition(shape.contains(point), "Label outside segment")
                let gap = angle + .pi / Double(count)
                let next = WheelSegment(angle: WheelGeometry.angle(index: (index + 1) % count, count: count), count: count)
                    .path(in: CGRect(x: 0, y: 0, width: 336, height: 336))
                // Every straight gap measures six points perpendicular to its edges,
                // regardless of orientation or distance from the wheel centre.
                for radius in [80.0, 103.0, 125.0] {
                    for offset in [-3.1, -2.9, 0.0, 2.9, 3.1] {
                        let probe = CGPoint(x: 168 + cos(gap) * radius - sin(gap) * offset,
                                            y: 168 + sin(gap) * radius + cos(gap) * offset)
                        precondition((shape.contains(probe) || next.contains(probe)) == (abs(offset) > 3),
                                     "Gap width varies with angle or radius")
                    }
                }
                precondition(WheelGeometry.index(at: CGPoint(x: 168 + cos(gap) * 103, y: 168 + sin(gap) * 103), count: count) != nil, "Visual gap must accept a drop")
            }
            // Sweep the complete ring, including the rounded visual corners and every gap.
            for radius in [57.01, 60.0, 103.0, 142.0, 145.99] {
                for degree in 0..<3600 {
                    let angle = Double(degree) * .pi / 1800
                    let point = CGPoint(x: 168 + cos(angle) * radius, y: 168 + sin(angle) * radius)
                    precondition(WheelGeometry.index(at: point, count: count) != nil, "Hole in drop ring")
                }
            }
            precondition(WheelGeometry.index(at: CGPoint(x: 168, y: 168), count: count) == nil)
            precondition(WheelGeometry.index(at: .zero, count: count) == nil)
        }
        precondition(WheelGeometry.index(at: .zero, count: 0) == nil)
        let state = WheelModel()
        let root = WheelFixtures.actions
        state.reset(actions: root, files: [])
        guard case .submenu(let children) = root[3].destination else { fatalError("Missing example submenu") }
        let start = Date(timeIntervalSince1970: 1000)
        let centre = CGPoint(x: 168, y: 168)
        let convert = CGPoint(x: 168, y: 271)
        state.updateHover(at: convert, now: start)
        precondition(state.hovered?.id == root[3].id)
        state.advanceDwell(at: start.addingTimeInterval(0.3))
        precondition(state.parents.isEmpty && abs(state.dwellProgress(at: start.addingTimeInterval(0.3)) - 0.5) < 0.001)
        state.updateHover(at: centre, now: start.addingTimeInterval(0.4))
        precondition(state.hovered == nil && state.dwellTarget == nil, "Root centre must be empty and cancel dwell")
        state.advanceDwell(at: start.addingTimeInterval(1))
        precondition(state.parents.isEmpty, "Cancelled dwell must not navigate")
        state.updateHover(at: convert, now: start.addingTimeInterval(2))
        state.advanceDwell(at: start.addingTimeInterval(2.59))
        precondition(state.parents.isEmpty, "Must wait until fill completes")
        state.advanceDwell(at: start.addingTimeInterval(2.61))
        precondition(state.actions.count == 7 && state.hovered == nil && state.dwellTarget == nil)
        state.updateHover(at: CGPoint(x: 168, y: 65), now: start.addingTimeInterval(3))
        precondition(state.hovered != nil)
        state.updateHover(at: centre, now: start.addingTimeInterval(4))
        precondition(state.hovered == nil && state.dwellTarget == WheelModel.backTarget, "Centre must immediately show Back")
        state.advanceDwell(at: start.addingTimeInterval(4.59))
        precondition(state.actions.count == 7)
        state.advanceDwell(at: start.addingTimeInterval(4.61))
        precondition(state.parents.isEmpty && state.actions.count == 6 && state.dwellTarget == nil)
        state.enter(children)
        precondition(state.hoveredID == nil && state.dwellTarget == nil && state.actions.count == 7)
        state.back()
        precondition(state.actions.map(\.id) == root.map(\.id) && state.parents.isEmpty)
        state.back()
        precondition(state.actions.count == 6)
        state.enter(children)
        state.reset(actions: root, files: [])
        precondition(state.parents.isEmpty && state.hoveredID == nil)
        print("Passed: sector targets, gaps, centre, boundaries, submenu/back/reset")
    }
}
