import SwiftUI

@main
struct TalosSettingsApp: App {
    @NSApplicationDelegateAdaptor(SettingsAppDelegate.self) private var delegate
    @State private var library = ModuleLibraryModel()
    @State private var onboarding: Bool

    init() {
        let testing = ProcessInfo.processInfo.environment["TALOS_SKIP_ONBOARDING"] == "1"
        _onboarding = State(initialValue: !testing && !AppPreferences.defaults.bool(forKey: "completedOnboarding"))
    }

    var body: some Scene {
        Window("Talos", id: "settings") {
            Group {
                if onboarding {
                    OnboardingView {
                        onboarding = false
                        NSApp.terminate(nil)
                    }
                } else {
                    SettingsView(model: library)
                }
            }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

@MainActor
final class SettingsAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.thom1606.Talos").isEmpty else { return }
        let host = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard host.pathExtension == "app" else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.arguments = ["--background"]
        NSWorkspace.shared.openApplication(at: host, configuration: configuration)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
