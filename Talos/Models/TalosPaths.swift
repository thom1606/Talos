import Foundation

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
