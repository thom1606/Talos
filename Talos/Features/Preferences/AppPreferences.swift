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

nonisolated struct HostPreferencesStatus: Codable, Equatable {
    var loginEnabled = false
    var loginNeedsApproval = false
    var error: String?
}

@MainActor @Observable final class GeneralSettingsModel {
    var loginEnabled = false
    var loginPending = false
    var status = HostPreferencesStatus()
    var notificationStatus = "notDetermined"
    var error: String?
    var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "–") (\(info["CFBundleVersion"] as? String ?? "–"))"
    }
    func reload() {
        if let data = try? Data(contentsOf: AppPreferences.statusURL),
           let value = try? JSONDecoder().decode(HostPreferencesStatus.self, from: data) {
            status = value
            loginPending = FileManager.default.fileExists(atPath: AppPreferences.loginRequestURL.path)
            if !loginPending { loginEnabled = value.loginEnabled }
        }
        if let data = try? Data(contentsOf: TalosPaths.notificationState),
           let value = try? JSONDecoder().decode(NotificationAccessState.self, from: data) {
            notificationStatus = value.status
            if let error = value.error { self.error = error }
        }
    }
    func setLogin(_ enabled: Bool) {
        do {
            try FileManager.default.createDirectory(at: TalosPaths.root, withIntermediateDirectories: true)
            try JSONEncoder().encode(enabled).write(to: AppPreferences.loginRequestURL, options: .atomic)
            loginEnabled = enabled; loginPending = true
        } catch { self.error = error.localizedDescription }
    }
    func checkUpdates() {
        do { try Data().write(to: AppPreferences.updateRequestURL, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
    var notificationsEnabled: Bool {
        notificationStatus == "authorized" || notificationStatus == "silent"
    }
    func requestNotifications() {
        guard !notificationsEnabled else { return }
        if notificationStatus == "denied" {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
            NSWorkspace.shared.open(url)
            return
        }
        do {
            try FileManager.default.createDirectory(at: TalosPaths.root, withIntermediateDirectories: true)
            try Data().write(to: TalosPaths.notificationRequest, options: .atomic)
        } catch { self.error = error.localizedDescription }
    }
}

@MainActor final class SoundService {
    static let shared = SoundService()
    private let glass = Bundle.main.url(forResource: "Glass_006", withExtension: "ogg")
        .flatMap { NSSound(contentsOf: $0, byReference: false) }

    func playHover() {
        guard AppPreferences.defaults.bool(forKey: "hoverSound") else { return }
        play(volume: 0.5)
    }

    func playWheelCompletion() {
        guard AppPreferences.defaults.bool(forKey: "hoverSound") else { return }
        play(volume: 0.65)
    }

    func playCompletion() {
        guard AppPreferences.defaults.bool(forKey: "completionSound") else { return }
        play(volume: 0.65)
    }

    private func play(volume: Float) {
        glass?.stop()
        glass?.volume = volume
        glass?.play()
    }
}
