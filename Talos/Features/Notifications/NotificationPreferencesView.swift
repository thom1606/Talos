import SwiftUI
import UserNotifications

struct NotificationPreferencesView: View {
    let notifications: NotificationService

    var body: some View {
        Toggle("Update notifications", isOn: Binding(
            get: { notifications.isAuthorized },
            set: { enabled in
                if enabled { Task { await notifications.requestAuthorization() } }
            }
        ))
        .disabled(notifications.isRequesting || notifications.isAuthorized)
        .accessibilityIdentifier("onboarding.notifications")

        if notifications.authorizationStatus == .denied {
            Text("Notifications are disabled in System Settings.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Open Notification Settings…") { notifications.openSystemSettings() }
        }
        if let message = notifications.errorMessage {
            Text(message).font(.callout).foregroundStyle(.red)
        }
    }
}
