import SwiftUI

@MainActor
@Observable
final class WheelModel {
    var actions: [TalosAction] = []
    var parents: [[TalosAction]] = []
    var hoveredID: String?
    var dwellTarget: String?
    var dwellStarted: Date?
    static let dwellDuration: TimeInterval = 0.6
    static let backTarget = "__back"
    var isVisible = false
    var files: [URL] = []
    var hovered: TalosAction? { actions.first { $0.id == hoveredID } }

    func updateHover(at point: CGPoint, now: Date = .now) {
        let index = WheelGeometry.index(at: point, count: actions.count)
        hoveredID = index.map { actions[$0].id }
        let inCentre = hypot(point.x - WheelGeometry.size / 2, point.y - WheelGeometry.size / 2) <= 44
        let target: String?
        if inCentre && !parents.isEmpty {
            target = Self.backTarget
        } else if let hovered, hovered.isSubmenu {
            target = hovered.id
        } else {
            target = nil
        }
        if target != dwellTarget {
            dwellTarget = target
            dwellStarted = target == nil ? nil : now
        }
    }

    func dwellProgress(at now: Date) -> Double {
        guard let dwellStarted else { return 0 }
        return min(1, max(0, now.timeIntervalSince(dwellStarted) / Self.dwellDuration))
    }

    func advanceDwell(at now: Date = .now) {
        guard dwellProgress(at: now) >= 1, let target = dwellTarget else { return }
        if target == Self.backTarget {
            back()
        } else if let hovered, hovered.id == target, case .submenu(let children) = hovered.destination {
            SoundService.shared.playWheelCompletion()
            enter(children)
        }
    }

    func clearHover() {
        hoveredID = nil
        dwellTarget = nil
        dwellStarted = nil
    }

    func reset(actions: [TalosAction], files: [URL]) {
        self.actions = actions
        self.files = files
        parents = []
        clearHover()
    }

    func enter(_ children: [TalosAction]) {
        parents.append(actions)
        actions = children
        clearHover()
    }

    func back() {
        guard let previous = parents.popLast() else { return }
        SoundService.shared.playWheelCompletion()
        actions = previous
        clearHover()
    }
}
