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
    private(set) var activeWheel: WheelKind = .primary

    private struct NavigationState {
        let actions: [WheelAction]
        let parents: [[WheelAction]]
    }

    @ObservationIgnored private var navigation: [WheelKind: NavigationState] = [:]

    var canNavigateBack: Bool { !parents.isEmpty }

    var hoveredAction: WheelAction? {
        actions.first { $0.id == hoveredID }
    }

    func updateHover(at point: CGPoint, now: Date = .now) {
        let index = WheelLayout.runtime.index(at: point, count: actions.count, reservesBack: canNavigateBack)
        let nextHoveredID = index.map { actions[$0].id }
        if hoveredID != nextHoveredID { hoveredID = nextHoveredID }

        let nextTarget: String?
        if canNavigateBack, WheelLayout.runtime.isBack(at: point) {
            nextTarget = Self.backTarget
        } else if let hoveredAction, hoveredAction.isFolder, hoveredAction.isEnabled {
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
            case let .folder(children) = hoveredAction.destination,
            hoveredAction.isEnabled
        {
            enter(children)
        }
    }

    func reset(actions: [WheelAction], secondaryActions: [WheelAction] = [], wheel: WheelKind = .primary) {
        navigation = [
            .primary: NavigationState(actions: actions, parents: []),
            .secondary: NavigationState(actions: secondaryActions, parents: [])
        ]
        activeWheel = wheel
        self.actions = navigation[wheel]?.actions ?? []
        parents = []
        clearHover()
    }

    func switchWheel(to wheel: WheelKind) {
        guard wheel != activeWheel else { return }
        navigation[activeWheel] = NavigationState(actions: actions, parents: parents)
        let next = navigation[wheel]
        activeWheel = wheel
        actions = next?.actions ?? []
        parents = next?.parents ?? []
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
