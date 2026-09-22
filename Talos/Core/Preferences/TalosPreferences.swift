import Foundation

/// Preference keys shared by the Talos runtime and settings interface.
enum TalosPreferenceKey {
    static let completedOnboarding = "completedOnboarding"
    static let automaticUpdates = "automaticUpdates"
    static let completionSound = "completionSound"
    static let hoverSound = "hoverSound"
    static let linkedLocalProjects = "linkedLocalProjects"
    static let wheelConfiguration = "wheelConfiguration"
}

/// Persistent storage for the single Talos application process.
@MainActor
enum TalosPreferences {
    // Only storage is isolated. UI tests still exercise the production screens and actions.
    nonisolated static var uiTestRunID: String? {
        #if DEBUG
        guard let value = ProcessInfo.processInfo.environment["TALOS_UI_TEST_RUN"],
              let id = UUID(uuidString: value) else { return nil }
        return id.uuidString
        #else
        return nil
        #endif
    }

    static let defaults: UserDefaults = {
        let defaults: UserDefaults
        #if DEBUG
        if let id = uiTestRunID {
            defaults = UserDefaults(suiteName: "com.thom1606.Talos.UITests.\(id)")!
        } else {
            defaults = .standard
        }
        #else
        defaults = .standard
        #endif

        defaults.register(defaults: [
            TalosPreferenceKey.completedOnboarding: false,
            TalosPreferenceKey.automaticUpdates: true,
            TalosPreferenceKey.completionSound: true,
            TalosPreferenceKey.hoverSound: true,
        ])
        return defaults
    }()
}
