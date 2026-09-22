import SwiftUI

struct OnboardingExperienceView: View {
    let model: AdvancedSettingsModel
    let notifications: NotificationService
    let onNext: () -> Void

    var body: some View {
        @Bindable var model = model
        OnboardingPage(
            title: "Set up your experience",
            subtitle: "Choose how Talos stays ready for you. You can change all of this later in Settings."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Start at login", isOn: Binding(
                    get: { model.isLoginItemEnabled }, set: { model.setStartAtLogin($0) }
                ))
                .disabled(model.isLoginRequestPending)
                .accessibilityIdentifier("onboarding.startAtLogin")
                if model.loginItemNeedsApproval {
                    Button("Allow in Login Items…") { model.openLoginItemSettings() }
                }
                Toggle("Check for app updates automatically", isOn: $model.automaticallyChecksForUpdates)
                NotificationPreferencesView(notifications: notifications)
            }
            .toggleStyle(OnboardingToggleStyle())
            .controlSize(.small)
        } actions: {
            Spacer()
            OnboardingButton(title: "Next", prominent: true, action: onNext)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.next")
        }
        .task {
            model.refreshLoginItemStatus()
            await notifications.refreshAuthorization()
        }
    }
}

/// Keep the prototype's aligned leading switches while retaining native controls.
private struct OnboardingToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden()
                .toggleStyle(.switch)
                .fixedSize()
            configuration.label.accessibilityHidden(true)
        }
    }
}
