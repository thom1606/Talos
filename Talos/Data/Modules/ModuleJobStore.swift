import Foundation
import TalosSDK

actor ModuleJobStore {
    private let directory: URL
    init(directory: URL = TalosPaths.jobs) { self.directory = directory }
    private var offsets: [UUID: UInt64] = [:]
    private var pending: [UUID: Data] = [:]
    func create(module: InstalledModule, action: String, files: [ModuleFile], notificationAction: String? = nil) throws -> ModuleInvocation {
        let id = UUID()
        let directory = self.directory.appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let invocation = ModuleInvocation(taskID: id, moduleID: module.manifest.id, actionID: action, files: files, workspace: directory, notificationAction: notificationAction)
        try JSONEncoder().encode(invocation).write(to: directory.appendingPathComponent("invocation.json"), options: .atomic)
        try Data(module.id.uuidString.utf8).write(to: directory.appendingPathComponent("installation.txt"))
        return invocation
    }
    func read(_ invocation: ModuleInvocation) throws -> [ModuleEvent] {
        let url = invocation.workspace.appendingPathComponent("events.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offsets[invocation.taskID] ?? 0)
        let data = try handle.read(upToCount: 1_000_000) ?? Data()
        offsets[invocation.taskID, default: 0] += UInt64(data.count)
        var buffer = pending[invocation.taskID] ?? Data()
        buffer.append(data)
        var events: [ModuleEvent] = []
        while let newline = buffer.firstIndex(of: 10) {
            let event = try JSONDecoder().decode(ModuleEvent.self, from: buffer[..<newline])
            guard event.taskID == invocation.taskID, event.fraction.map({ $0.isFinite && (0...1).contains($0) }) ?? true else {
                throw ManifestError.invalid("Invalid module event")
            }
            events.append(event)
            buffer.removeSubrange(...newline)
        }
        guard buffer.count < 1_000_000 else { throw ManifestError.invalid("Module event exceeded size limit") }
        pending[invocation.taskID] = buffer
        return events
    }
    func registerNotification(_ event: ModuleEvent, invocation: ModuleInvocation) throws {
        let url = invocation.workspace.appendingPathComponent("notification-actions.json")
        var actions = (try? JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: url))) ?? []
        actions.formUnion((event.actions ?? []).map(\.id))
        try JSONEncoder().encode(actions).write(to: url, options: .atomic)
    }
    func notificationContext(id: UUID, action: String) throws -> (UUID, ModuleInvocation)? {
        let directory = self.directory.appendingPathComponent(id.uuidString)
        let actions = try JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: directory.appendingPathComponent("notification-actions.json")))
        guard actions.contains(action) else { return nil }
        let installation = try String(contentsOf: directory.appendingPathComponent("installation.txt"), encoding: .utf8)
        guard let installationID = UUID(uuidString: installation) else { return nil }
        let invocation = try JSONDecoder().decode(ModuleInvocation.self, from: Data(contentsOf: directory.appendingPathComponent("invocation.json")))
        return (installationID, invocation)
    }
    func deliverNotificationAction(_ action: String, invocation: ModuleInvocation) throws {
        try JSONEncoder().encode(action).write(to: invocation.workspace.appendingPathComponent("notification-action.json"), options: .atomic)
    }
    func cancel(_ invocation: ModuleInvocation) throws {
        try Data().write(to: invocation.workspace.appendingPathComponent("cancel"), options: .atomic)
    }
    func finish(_ id: UUID) { offsets[id] = nil; pending[id] = nil }
}
