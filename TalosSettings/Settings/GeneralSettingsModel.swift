import AppKit
import Observation

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
