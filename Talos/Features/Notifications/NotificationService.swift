import AppKit
import Observation
import UserNotifications

@MainActor
@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var isRequesting = false
    var errorMessage: String?
    @ObservationIgnored var openRepositories: (() -> Void)?
    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    var isAuthorized: Bool { authorizationStatus == .authorized || authorizationStatus == .provisional }

    func start() {
        center.delegate = self
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
    }

    /// Only a user action asks macOS for permission; background checks never trigger a prompt.
    func requestAuthorization() async {
        guard !isRequesting else { return }
        isRequesting = true
        errorMessage = nil
        defer { isRequesting = false }
        await refreshAuthorization()
        if authorizationStatus == .denied {
            openSystemSettings()
            return
        }
        do {
            if authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            }
            await refreshAuthorization()
        } catch { errorMessage = error.localizedDescription }
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Returns true only after macOS accepted the request, so failed or denied delivery is retryable.
    func postRepositoryUpdate(_ update: RepositoryUpdate) async throws -> Bool {
        await refreshAuthorization()
        guard isAuthorized else { return false }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Repository update available")
        if let version = update.version {
            content.body = String(localized: "\(update.repositoryName) has a new release (\(version)). Open Talos to update.")
        } else {
            content.body = String(localized: "\(update.repositoryName) has a new release. Open Talos to update.")
        }
        content.sound = .default
        content.userInfo = ["repositoryID": update.repositoryID]
        content.threadIdentifier = "repository-updates"
        try Task.checkCancellation()
        try await center.add(UNNotificationRequest(identifier: notificationID(update.repositoryID), content: content, trigger: nil))
        return true
    }

    func dismissRepositoryUpdate(_ id: String) {
        let ids = [notificationID(id)]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func notificationID(_ repositoryID: String) -> String { "talos.repository-update.\(repositoryID)" }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              response.notification.request.content.userInfo["repositoryID"] is String else { return }
        await MainActor.run { self.openRepositories?() }
    }
}
