#if TALOS_HOST
import AppKit
import ServiceManagement
import Sparkle

@MainActor final class HostPreferencesService {
    private let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    private var error: String?
    private var published: HostPreferencesStatus?
    func start() {
        updater.updater.automaticallyChecksForUpdates = AppPreferences.defaults.bool(forKey: "automaticUpdates")
        do { try updater.updater.start() } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        if let data = try? Data(contentsOf: AppPreferences.loginRequestURL),
           let enabled = try? JSONDecoder().decode(Bool.self, from: data) {
            do {
                if enabled, SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
                else if !enabled, SMAppService.mainApp.status != .notRegistered { try await SMAppService.mainApp.unregister() }
                error = nil
            } catch { self.error = error.localizedDescription }
            try? FileManager.default.removeItem(at: AppPreferences.loginRequestURL)
        }
        let automatic = AppPreferences.defaults.bool(forKey: "automaticUpdates")
        if updater.updater.automaticallyChecksForUpdates != automatic { updater.updater.automaticallyChecksForUpdates = automatic }
        if FileManager.default.fileExists(atPath: AppPreferences.updateRequestURL.path) {
            try? FileManager.default.removeItem(at: AppPreferences.updateRequestURL)
            updater.checkForUpdates(nil)
        }
        let value = HostPreferencesStatus(loginEnabled: SMAppService.mainApp.status == .enabled,
                                          loginNeedsApproval: SMAppService.mainApp.status == .requiresApproval, error: error)
        if value != published {
            do {
                try FileManager.default.createDirectory(at: TalosPaths.root, withIntermediateDirectories: true)
                try JSONEncoder().encode(value).write(to: AppPreferences.statusURL, options: .atomic)
                published = value
            } catch { self.error = error.localizedDescription }
        }
    }
}
#endif
