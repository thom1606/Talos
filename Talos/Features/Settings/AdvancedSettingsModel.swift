import AppKit
import Foundation
import Observation
import ServiceManagement
import Sparkle

@MainActor
@Observable
final class AdvancedSettingsModel {
    private(set) var isLoginItemEnabled = false
    private(set) var isLoginRequestPending = false
    private(set) var loginItemNeedsApproval = false
    var automaticallyChecksForUpdates: Bool {
        didSet {
            guard automaticallyChecksForUpdates != oldValue else { return }
            defaults.set(
                automaticallyChecksForUpdates,
                forKey: TalosPreferenceKey.automaticUpdates
            )
            updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let updaterController: SPUStandardUpdaterController
    @ObservationIgnored private var didStartUpdater = false

    convenience init() {
        self.init(defaults: TalosPreferences.defaults)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        automaticallyChecksForUpdates = defaults.bool(
            forKey: TalosPreferenceKey.automaticUpdates
        )
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        refreshLoginItemStatus()
    }

    var versionDescription: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "–"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "–"

        return "\(version) (\(build))"
    }

    func startUpdater() {
        guard !didStartUpdater, TalosPreferences.uiTestRunID == nil else { return }
        didStartUpdater = true
        updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates

        do {
            try updaterController.updater.start()
        } catch {
            NSLog("Cannot start the Talos updater: %@", error.localizedDescription)
        }
    }

    func setStartAtLogin(_ isEnabled: Bool) {
        guard !isLoginRequestPending else { return }
        isLoginItemEnabled = isEnabled
        isLoginRequestPending = true

        Task {
            do {
                try await applyLoginItemState(isEnabled)
            } catch {
                NSLog("Cannot update the Talos login item: %@", error.localizedDescription)
            }

            refreshLoginItemStatus()
            isLoginRequestPending = false
        }
    }

    func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func refreshLoginItemStatus() {
        let status = SMAppService.mainApp.status
        isLoginItemEnabled = status == .enabled
        loginItemNeedsApproval = status == .requiresApproval
    }

    private func applyLoginItemState(_ shouldStartAtLogin: Bool) async throws {
        let service = SMAppService.mainApp

        if shouldStartAtLogin, service.status != .enabled {
            try service.register()
        } else if !shouldStartAtLogin, service.status != .notRegistered {
            try await service.unregister()
        }
    }
}
