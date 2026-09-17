import Foundation

public struct ModuleInvocation: Codable, Sendable {
    public let protocolVersion: Int
    public let taskID: UUID
    public let moduleID: String
    public let actionID: String
    public let files: [ModuleFile]
    public let workspace: URL
    public let notificationAction: String?
    public init(taskID: UUID, moduleID: String, actionID: String, files: [ModuleFile], workspace: URL, notificationAction: String? = nil) {
        protocolVersion = TalosContract.version
        self.taskID = taskID; self.moduleID = moduleID; self.actionID = actionID; self.files = files; self.workspace = workspace
        self.notificationAction = notificationAction
    }
}

public struct ModuleNotificationAction: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
}

public struct ModuleEvent: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case progress, completed, failed, notification }
    public let kind: Kind
    public let taskID: UUID
    public let message: String
    public let fraction: Double?
    public let outputs: [URL]?
    public let actions: [ModuleNotificationAction]?
}

/// Module-side IPC. Each invocation gets its own workspace and event stream.
/// File I/O is actor-isolated; a SwiftUI view never writes the stream directly.
public actor ModuleSession {
    public nonisolated let invocation: ModuleInvocation
    private let events: FileHandle
    private var finished = false

    public init(invocationURL: URL) throws {
        let invocation = try JSONDecoder().decode(ModuleInvocation.self, from: Data(contentsOf: invocationURL))
        guard invocation.protocolVersion == TalosContract.version else { throw ManifestError.invalid("Unsupported host protocol") }
        self.invocation = invocation
        let url = invocation.workspace.appendingPathComponent("events.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        events = try FileHandle(forWritingTo: url)
        try events.seekToEnd()
    }

    public static func fromLaunchArguments() throws -> ModuleSession {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--talos-invocation"), args.indices.contains(i + 1) else {
            throw ManifestError.invalid("Open this module through Talos")
        }
        return try ModuleSession(invocationURL: URL(fileURLWithPath: args[i + 1]))
    }

    public func progress(_ fraction: Double, message: String) throws {
        try emit(.progress, message: message, fraction: min(1, max(0, fraction)))
    }
    public func complete(message: String, outputs: [URL] = []) throws {
        try emit(.completed, message: message, outputs: outputs)
        finished = true
    }
    public func fail(_ message: String) throws {
        try emit(.failed, message: message)
        finished = true
    }
    public func notify(_ message: String, actions: [ModuleNotificationAction] = []) throws {
        try emit(.notification, message: message, actions: Array(actions.prefix(4)))
    }
    public func checkCancellation() throws {
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: invocation.workspace.appendingPathComponent("cancel").path) {
            throw CancellationError()
        }
    }
    /// Returns the next notification action, if the user has chosen one.
    public func takeNotificationAction() throws -> String? {
        let url = invocation.workspace.appendingPathComponent("notification-action.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let action = try JSONDecoder().decode(String.self, from: Data(contentsOf: url))
        try FileManager.default.removeItem(at: url)
        return action
    }
    private func emit(_ kind: ModuleEvent.Kind, message: String, fraction: Double? = nil,
                      outputs: [URL]? = nil, actions: [ModuleNotificationAction]? = nil) throws {
        guard !finished else { return }
        let event = ModuleEvent(kind: kind, taskID: invocation.taskID, message: message, fraction: fraction, outputs: outputs, actions: actions)
        var data = try JSONEncoder().encode(event)
        guard data.count < 1_000_000 else { throw ManifestError.invalid("Event too large") }
        data.append(10)
        try events.write(contentsOf: data)
    }
}
