import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let library = ModuleLibraryModel()
    lazy var controller = DragWheelController(actionsProvider: { [weak self] files in self?.library.actions(for: files) ?? [] })
    lazy var taskPill = TaskPillController(model: library.tasks.pill)
    private let preferences = HostPreferencesService()
    private var refresh: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        library.configureOpenSettings { [weak self] in self?.showSettings() }
        Task {
            do { try await LibraryStore().migrateLegacyLibrary() }
            catch {
                let alert = NSAlert()
                alert.messageText = "Cannot prepare Talos library"
                alert.informativeText = error.localizedDescription
                alert.runModal()
                return
            }
            library.configureHostNotifications()
            await library.load()
            controller.start()
            taskPill.start()
            Task { [library] in
                await library.installDefaultActionsIfNeeded()
            }
            preferences.start()
            await library.tasks.notifications.publishAccess()
            let defaults = UserDefaults.standard
            if !ProcessInfo.processInfo.arguments.contains("--background"),
               !defaults.bool(forKey: "hasOpenedSettings") || ProcessInfo.processInfo.arguments.contains("--settings") {
                showSettings()
                defaults.set(true, forKey: "hasOpenedSettings")
            }
            refresh = Task {
                while !Task.isCancelled {
                    await library.reload()
                    await preferences.refresh()
                    if FileManager.default.fileExists(atPath: TalosPaths.notificationRequest.path) {
                        try? FileManager.default.removeItem(at: TalosPaths.notificationRequest)
                        _ = try? await library.tasks.notifications.requestAccess()
                    }
                    if FileManager.default.fileExists(atPath: TalosPaths.notificationTestRequest.path) {
                        try? FileManager.default.removeItem(at: TalosPaths.notificationTestRequest)
                        await library.tasks.notifications.sendTest()
                    }
                    await library.tasks.notifications.publishAccess()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        refresh?.cancel()
        controller.stop()
        taskPill.stop()
        library.tasks.stopAll()
    }
    func showSettings() {
        let app = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Talos Settings.app")
        NSWorkspace.shared.openApplication(at: app, configuration: .init()) { _, error in
            if let error { NSLog("Cannot open Talos Settings: %@", error.localizedDescription) }
        }
    }
}

@main
struct TalosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}
