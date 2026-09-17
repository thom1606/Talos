import Foundation
import OSLog
import UserNotifications
import TalosSDK

nonisolated struct NotificationAccessState: Codable {
    let status: String
    let error: String?
    let updatedAt: Date
}

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    var onAction: (@MainActor (UUID, String) -> Void)?
    private var categories: Set<UNNotificationCategory> = []
    func start() { UNUserNotificationCenter.current().delegate = self }
    private var lastError: String?
    func requestAccess() async throws -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            lastError = nil
            await publishAccess()
            return granted
        } catch {
            lastError = error.localizedDescription
            await publishAccess()
            throw error
        }
    }
    func publishAccess() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let status: String = switch settings.authorizationStatus {
        case .authorized: settings.alertStyle == .none ? "silent" : "authorized"
        case .provisional: "silent"
        case .denied: "denied"
        default: "notDetermined"
        }
        do {
            try FileManager.default.createDirectory(at: TalosPaths.root, withIntermediateDirectories: true)
            let state = NotificationAccessState(status: status, error: lastError, updatedAt: .now)
            try JSONEncoder().encode(state).write(to: TalosPaths.notificationState, options: .atomic)
        } catch {
            Logger(subsystem: "com.thom1606.Talos", category: "notifications").error("Cannot publish notification status: \(error.localizedDescription, privacy: .public)")
        }
    }
    func sendTest() async {
        do {
            let content = UNMutableNotificationContent()
            content.title = "Talos"
            content.body = "Notifications are working."
            content.sound = .default
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            lastError = nil
        } catch { lastError = error.localizedDescription }
        await publishAccess()
    }
    func post(_ event: ModuleEvent, module: InstalledModule) async throws {
        let centre = UNUserNotificationCenter.current()
        if await centre.notificationSettings().authorizationStatus == .notDetermined { _ = try await requestAccess() }
        guard await centre.notificationSettings().authorizationStatus == .authorized else { return }
        let actions = event.actions ?? []
        let categoryID = "talos.\(event.taskID.uuidString)"
        let category = UNNotificationCategory(identifier: categoryID, actions: actions.map {
            UNNotificationAction(identifier: $0.id, title: $0.title)
        }, intentIdentifiers: [])
        categories.update(with: category)
        centre.setNotificationCategories(categories)
        let content = UNMutableNotificationContent()
        content.title = module.manifest.name; content.body = event.message
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.userInfo = ["taskID": event.taskID.uuidString]
        try await centre.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo["taskID"] as? String,
              let id = UUID(uuidString: raw), response.actionIdentifier != UNNotificationDefaultActionIdentifier,
              response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
        let action = response.actionIdentifier
        await MainActor.run { self.onAction?(id, action) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
