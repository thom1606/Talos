import AppKit
import Observation

@MainActor enum AppPreferences {
    static let defaults: UserDefaults = {
        if let suite = ProcessInfo.processInfo.environment["TALOS_TEST_SUITE"], !suite.isEmpty {
            let value = UserDefaults(suiteName: "com.thom1606.Talos.tests.\(suite)")!
            value.register(defaults: [
                "automaticUpdates": true,
                "hoverSound": true,
                "completionSound": true,
                "completedOnboarding": false
            ])
            return value
        }
        let value = UserDefaults(suiteName: TalosPaths.group)!
        value.register(defaults: [
            "automaticUpdates": true,
            "hoverSound": true,
            "completionSound": true,
            "completedOnboarding": false
        ])
        return value
    }()
    static var statusURL: URL { TalosPaths.root.appendingPathComponent("preferences-status.json") }
    static var loginRequestURL: URL { TalosPaths.root.appendingPathComponent("login-request.json") }
    static var updateRequestURL: URL { TalosPaths.root.appendingPathComponent("update-request") }
}
