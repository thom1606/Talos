import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class TaskPillModel {
    private(set) var presentation: TaskPillPresentation?
    @ObservationIgnored private var active: [UUID: TaskPillPresentation] = [:]
    @ObservationIgnored private var order: [UUID] = []
    @ObservationIgnored private var dismissal: Task<Void, Never>?
    @ObservationIgnored private let completionDelay: Duration

    init(completionDelay: Duration = .seconds(1.25)) {
        self.completionDelay = completionDelay
    }

    func start(id: UUID, title: String) {
        dismissal?.cancel()
        let item = TaskPillPresentation(
            id: id,
            title: title,
            message: title,
            progress: 0,
            phase: .running
        )
        active[id] = item
        order.removeAll { $0 == id }
        order.append(id)
        presentation = item
    }

    func update(id: UUID, message: String, progress: Double?) {
        guard var item = active[id] else { return }
        if !message.isEmpty { item.message = message }
        if let progress { item.progress = min(1, max(0, progress)) }
        active[id] = item
        if presentation?.id == id, presentation?.phase == .running {
            presentation = item
        }
    }

    func finish(id: UUID, message: String, failed: Bool) {
        guard var item = active.removeValue(forKey: id) else { return }
        order.removeAll { $0 == id }
        guard presentation?.id == id else { return }

        dismissal?.cancel()
        if !message.isEmpty { item.message = message }
        item.progress = failed ? item.progress : 1
        item.phase = failed ? .failed : .completed
        presentation = item
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: self?.completionDelay ?? .seconds(1.25)) }
            catch { return }
            self?.showLatest()
        }
    }

    func stop() {
        dismissal?.cancel()
        active.removeAll()
        order.removeAll()
        presentation = nil
    }

    private func showLatest() {
        dismissal = nil
        presentation = order.last.flatMap { active[$0] }
    }
}
