import SwiftUI

struct OnboardingExperienceView: View {
    let onNext: () -> Void

    @State private var model = GeneralSettingsModel()
    @AppStorage("automaticUpdates", store: AppPreferences.defaults) private var automaticUpdates = true

    var body: some View {
        OnboardingPage(
            title: "Set up your experience",
            subtitle: "Choose how Talos stays ready for you. You can change all of this later in Settings."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                preferenceRow(
                    "Start at login",
                    identifier: "onboarding.startAtLogin",
                    isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) })
                )
                preferenceRow(
                    "Check for updates automatically",
                    identifier: "onboarding.automaticUpdates",
                    isOn: $automaticUpdates
                )
                preferenceRow(
                    "Receive action notifications",
                    identifier: "onboarding.notifications",
                    isOn: Binding(get: { model.notificationsEnabled }, set: {
                        if $0 {
                            model.requestNotifications()
                        }
                    })
                )
                .disabled(model.notificationsEnabled)

                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } actions: {
            Spacer()
            OnboardingButton(title: "Next", prominent: true, action: onNext)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.next")
        }
        .task { model.reload() }
    }

    private func preferenceRow(_ title: LocalizedStringKey, identifier: String,
                               isOn: Binding<Bool>) -> some View
    {
        HStack(spacing: 10) {
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(Text(title))
                .accessibilityIdentifier(identifier)
            Text(title)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    OnboardingExperienceView {}
        .tint(.accentColor)
}
