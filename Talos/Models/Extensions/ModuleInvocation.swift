import Foundation

nonisolated public struct ModuleInvocation: Codable, Sendable {
    public let protocolVersion: Int
    public let taskID: UUID
    public let moduleID: String
    public let actionID: String
    public let files: [ModuleFile]
    public let workspace: URL
    public let notificationAction: String?
    public var language: String? = Locale.current.language.languageCode?.identifier
    public init(taskID: UUID, moduleID: String, actionID: String, files: [ModuleFile], workspace: URL, notificationAction: String? = nil) {
        protocolVersion = TalosContract.version
        self.taskID = taskID; self.moduleID = moduleID; self.actionID = actionID; self.files = files; self.workspace = workspace
        self.notificationAction = notificationAction
    }
}

nonisolated public struct ModuleNotificationAction: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
}

nonisolated public struct ModuleEvent: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case progress, completed, failed, notification }
    public let kind: Kind
    public let taskID: UUID
    public let message: String
    public let fraction: Double?
    public let outputs: [URL]?
    public let actions: [ModuleNotificationAction]?
}

