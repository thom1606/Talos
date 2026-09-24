import Observation
import SwiftUI

@MainActor
@Observable
final class WheelModel {
    static let dwellDuration: TimeInterval = 0.7
    static let backTarget = "talos.wheel.back"

    var actions: [WheelAction] = []
    var parents: [[WheelAction]] = []
    var hoveredID: WheelAction.ID?
    var dwellTarget: String?
    var dwellStarted: Date?
    var isVisible = false

    var hoveredAction: WheelAction? {
        actions.first { $0.id == hoveredID }
    }

    func updateHover(at point: CGPoint, now: Date = .now) {
        let index = WheelLayout.runtime.index(at: point, count: actions.count)
        let nextHoveredID = index.map { actions[$0].id }
        if hoveredID != nextHoveredID { hoveredID = nextHoveredID }

        let isInsideCenter = hypot(
            point.x - WheelLayout.runtime.size / 2,
            point.y - WheelLayout.runtime.size / 2
        ) <= WheelLayout.runtime.centerRadius
        let nextTarget: String?
        if isInsideCenter, !parents.isEmpty {
            nextTarget = Self.backTarget
        } else if let hoveredAction, hoveredAction.isFolder {
            nextTarget = hoveredAction.id.uuidString
        } else {
            nextTarget = nil
        }

        if nextTarget != dwellTarget {
            dwellTarget = nextTarget
            dwellStarted = nextTarget == nil ? nil : now
        }
    }

    func dwellProgress(at date: Date) -> Double {
        guard let dwellStarted else { return 0 }
        return min(1, max(0, date.timeIntervalSince(dwellStarted) / Self.dwellDuration))
    }

    func advanceDwell(at date: Date = .now) {
        guard dwellProgress(at: date) >= 1, let dwellTarget else { return }

        if dwellTarget == Self.backTarget {
            back()
        } else if
            let hoveredAction,
            hoveredAction.id.uuidString == dwellTarget,
            case let .folder(children) = hoveredAction.destination
        {
            enter(children)
        }
    }

    func reset(actions: [WheelAction]) {
        self.actions = actions
        parents = []
        clearHover()
    }

    func enter(_ children: [WheelAction]) {
        guard !children.isEmpty else { return }
        parents.append(actions)
        actions = children
        clearHover()
    }

    func back() {
        guard let previous = parents.popLast() else { return }
        actions = previous
        clearHover()
    }

    func clearHover() {
        hoveredID = nil
        dwellTarget = nil
        dwellStarted = nil
    }
}
