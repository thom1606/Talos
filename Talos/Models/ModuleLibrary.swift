import Foundation
import TalosSDK

nonisolated struct RepositorySource: Codable, Identifiable, Sendable {
    let id: UUID
    let owner: String
    let repository: String
    var name: String
    var modules: [ModuleManifest]
    var lastChecked: Date?
    var error: String?
    var localDirectory: URL?
    var isLocal: Bool { localDirectory != nil }
    var slug: String { localDirectory?.path ?? "\(owner)/\(repository)" }
    init(directory: URL, name: String? = nil) {
        id = UUID(); owner = ""; repository = ""; localDirectory = directory
        self.name = name ?? directory.lastPathComponent; modules = []
    }

    init(url: String) throws {
        guard let parsed = URL(string: url), parsed.scheme == "https", parsed.host?.lowercased() == "github.com",
              parsed.user == nil, parsed.password == nil, parsed.query == nil, parsed.fragment == nil else {
            throw ManifestError.invalid("Use https://github.com/owner/repository")
        }
        let parts = parsed.path.split(separator: "/").map(String.init)
        guard parts.count == 2, parts.allSatisfy(ModuleManifest.validIdentifier) else {
            throw ManifestError.invalid("Use a GitHub repository URL, without a branch or subfolder")
        }
        id = UUID(); owner = parts[0]
        repository = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
        guard !repository.isEmpty else { throw ManifestError.invalid("Missing repository name") }
        name = "\(owner)/\(repository)"; modules = []
    }
}

nonisolated struct InstalledModule: Codable, Identifiable, Sendable {
    let id: UUID
    var sourceID: UUID?
    let manifest: ModuleManifest
    var directory: URL
    var enabled: Bool
    var appURL: URL { directory.appendingPathComponent(manifest.appBundle) }
}

nonisolated struct LibrarySnapshot: Codable, Sendable {
    var repositories: [RepositorySource] = []
    var installed: [InstalledModule] = []
    var actionOrder: [String] = []
    var disabledActions: Set<String> = []
    var wheel: [WheelEntry]?
    init() {}
    private enum CodingKeys: String, CodingKey { case repositories, installed, actionOrder, disabledActions, wheel }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        repositories = try values.decodeIfPresent([RepositorySource].self, forKey: .repositories) ?? []
        installed = try values.decodeIfPresent([InstalledModule].self, forKey: .installed) ?? []
        actionOrder = try values.decodeIfPresent([String].self, forKey: .actionOrder) ?? []
        disabledActions = try values.decodeIfPresent(Set<String>.self, forKey: .disabledActions) ?? []
        wheel = try values.decodeIfPresent([WheelEntry].self, forKey: .wheel)
    }
}

nonisolated enum TalosPaths {
    static let group = "U6WA8YA735.com.thom1606.Talos"
    static var root: URL {
        if let path = ProcessInfo.processInfo.environment["TALOS_TEST_ROOT"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            preconditionFailure("Talos requires its shared App Group container")
        }
        return container.appendingPathComponent("Library/Application Support/Talos", isDirectory: true)
    }
    static var notificationRequest: URL { root.appendingPathComponent("request-notification-access") }
    static var legacyRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.thom1606.Talos/Data/Library/Application Support/Talos", isDirectory: true)
    }
    static var modules: URL { root.appendingPathComponent("Modules", isDirectory: true) }
    // External modules use ordinary application support, outside protected app containers.
    static var jobs: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Talos/Jobs", isDirectory: true)
    }
    static var notificationState: URL { root.appendingPathComponent("notification-state.json") }
    static var notificationTestRequest: URL { root.appendingPathComponent("request-notification-test") }

}

/// A placement has its own identity, so actions may appear more than once.
nonisolated struct WheelEntry: Codable, Identifiable, Sendable, Equatable {
    var id = UUID().uuidString
    var actionID: String?
    var title: String = "Folder"
    var children: [WheelEntry]?

    static func action(_ id: String) -> Self { Self(actionID: id) }
    static func folder(_ title: String) -> Self { Self(title: title, children: []) }

    static func entries(in entries: [Self], path: [String]) -> [Self] {
        guard let first = path.first else { return entries }
        guard let folder = entries.first(where: { $0.id == first }), let children = folder.children else { return [] }
        return Self.entries(in: children, path: Array(path.dropFirst()))
    }

    static func replace(in entries: inout [Self], path: [String], with replacement: [Self]) {
        guard let first = path.first else { entries = replacement; return }
        guard let index = entries.firstIndex(where: { $0.id == first }), var children = entries[index].children else { return }
        replace(in: &children, path: Array(path.dropFirst()), with: replacement)
        entries[index].children = children
    }
}
