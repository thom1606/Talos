import Foundation

@main
struct TaskPillChecks {
    @MainActor
    static func main() async throws {
        let model = TaskPillModel(completionDelay: .milliseconds(20))
        let first = UUID()
        let second = UUID()

        model.start(id: first, title: "Convert photos")
        precondition(model.presentation == TaskPillPresentation(
            id: first,
            title: "Convert photos",
            message: "Convert photos",
            progress: 0,
            phase: .running
        ))

        model.update(id: first, message: "Converting 2 of 4", progress: 0.5)
        precondition(model.presentation?.message == "Converting 2 of 4")
        precondition(model.presentation?.progress == 0.5)

        model.start(id: second, title: "Resize images")
        precondition(model.presentation?.id == second)
        model.finish(id: second, message: "Done", failed: false)
        precondition(model.presentation?.phase == .completed)
        precondition(model.presentation?.progress == 1)

        try await Task.sleep(for: .milliseconds(50))
        precondition(model.presentation?.id == first, "The previous active task should return after completion")

        model.finish(id: first, message: "Could not convert", failed: true)
        precondition(model.presentation?.phase == .failed)
        try await Task.sleep(for: .milliseconds(50))
        precondition(model.presentation == nil)

        print("Passed: task pill start, progress, completion, failure, dismissal and concurrent fallback")
    }
}
