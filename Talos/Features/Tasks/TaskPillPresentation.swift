import AppKit
import Observation
import SwiftUI

nonisolated struct TaskPillPresentation: Equatable {
    enum Phase: Equatable {
        case running
        case completed
        case failed
    }

    let id: UUID
    let title: String
    var message: String
    var progress: Double
    var phase: Phase
}
