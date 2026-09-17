import AppKit
import TalosSDK

@MainActor
final class TasksModel {
    private let store = ModuleJobStore()
    private var running: [UUID: NSRunningApplication] = [:]
    private var notificationActions: [UUID: Set<String>] = [:]
    private var monitors: [UUID: Task<Void, Never>] = [:]
    private var finished: Set<UUID> = []
    var resumeNotification: ((UUID, ModuleInvocation, String) -> Void)?
    let notifications = NotificationService()
    let pill = TaskPillModel()

    init() {
        notifications.start()
        notifications.onAction = { [weak self] id, action in self?.notificationAction(id: id, action: action) }
    }
    func run(module: InstalledModule, action: String, files: [ModuleFile], notificationAction: String? = nil) async {
        var scopes: [URL] = []
        var taskID: UUID?
        do {
            let lease = try ModuleLease(module)
            for file in files where file.url.startAccessingSecurityScopedResource() { scopes.append(file.url) }
            let invocation = try await store.create(module: module, action: action, files: files, notificationAction: notificationAction)
            let id = invocation.taskID
            taskID = id
            let title = actionTitle(action, in: module.manifest.actions) ?? module.manifest.name
            pill.start(id: id, title: title)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = ["--talos-invocation", invocation.workspace.appendingPathComponent("invocation.json").path]
            configuration.createsNewApplicationInstance = true
            configuration.activates = false
            do {
                running[id] = try await NSWorkspace.shared.openApplication(at: module.appURL, configuration: configuration)
            } catch {
                finish(id, message: error.localizedDescription, failed: true)
                throw error
            }
            let heldScopes = scopes
            monitors[id] = Task { [weak self] in
                guard let self else { return }
                defer {
                    withExtendedLifetime(lease) {}
                    for url in heldScopes { url.stopAccessingSecurityScopedResource() }
                    self.monitors[id] = nil
                    self.running[id] = nil
                    self.finished.remove(id)
                }
                do {
                    while !Task.isCancelled {
                        for event in try await store.read(invocation) {
                            apply(event)
                            if event.kind == .notification {
                                notificationActions[id, default: []].formUnion((event.actions ?? []).map(\.id))
                                try await store.registerNotification(event, invocation: invocation)
                                // Notification failure must not turn successful file processing into a failed task.
                                try? await notifications.post(event, module: module)
                            }
                        }
                        if finished.contains(id) { break }
                        if running[id]?.isTerminated != false {
                            finish(id, message: "Module closed before completing the task", failed: true)
                            break
                        }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                } catch is CancellationError {
                    finish(id, message: "Cancelled", failed: false)
                } catch {
                    finish(id, message: error.localizedDescription, failed: true)
                }
                await store.finish(id)
            }
        } catch {
            for url in scopes { url.stopAccessingSecurityScopedResource() }
            if let taskID {
                finished.remove(taskID)
            } else {
                let id = UUID()
                pill.start(id: id, title: module.manifest.name)
                pill.finish(id: id, message: error.localizedDescription, failed: true)
            }
        }
    }
    func stopAll() {
        // Termination cannot wait for the asynchronous cancellation grace period.
        for application in running.values { application.terminate() }
        for monitor in monitors.values { monitor.cancel() }
    }
    private func apply(_ event: ModuleEvent) {
        guard !finished.contains(event.taskID) else { return }
        if event.kind != .notification {
            pill.update(id: event.taskID, message: event.message, progress: event.fraction)
        }
        if event.kind == .completed { SoundService.shared.playCompletion() }
        if event.kind == .completed || event.kind == .failed {
            finish(event.taskID, message: event.message, failed: event.kind == .failed)
        }
    }
    private func finish(_ id: UUID, message: String, failed: Bool) {
        guard finished.insert(id).inserted else { return }
        pill.finish(id: id, message: message, failed: failed)
    }
    private func notificationAction(id: UUID, action: String) {
        Task {
            do {
                guard let (installationID, invocation) = try await store.notificationContext(id: id, action: action) else { return }
                if let app = running[id], !app.isTerminated {
                    try await store.deliverNotificationAction(action, invocation: invocation)
                } else {
                    resumeNotification?(installationID, invocation, action)
                }
            } catch { finish(id, message: error.localizedDescription, failed: true) }
        }
    }

    private func actionTitle(_ id: String, in actions: [ModuleAction]) -> String? {
        for action in actions {
            if action.id == id { return action.title }
            if let children = action.children, let title = actionTitle(id, in: children) { return title }
        }
        return nil
    }
}
