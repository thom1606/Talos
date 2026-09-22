import SwiftUI

struct AdvancedSettingsView: View {
    let model: AdvancedSettingsModel

    @AppStorage(
        TalosPreferenceKey.hoverSound,
        store: TalosPreferences.defaults
    ) private var hoverSound = true
    @AppStorage(
        TalosPreferenceKey.completionSound,
        store: TalosPreferences.defaults
    ) private var completionSound = true

    var body: some View {
        @Bindable var model = model

        Form {
            Section("Startup and updates") {
                Toggle(
                    "Start Talos at login",
                    isOn: Binding(
                        get: { model.isLoginItemEnabled },
                        set: { model.setStartAtLogin($0) }
                    )
                )
                .disabled(model.isLoginRequestPending)

                Toggle(
                    "Check for updates automatically",
                    isOn: $model.automaticallyChecksForUpdates
                )

                if model.loginItemNeedsApproval {
                    Button("Allow in Login Items…") {
                        model.openLoginItemSettings()
                    }
                }
            }

            Section("Sounds") {
                Toggle("Item hover", isOn: $hoverSound)
                    .accessibilityIdentifier("settings.hoverSound")
                Toggle("Action completed", isOn: $completionSound)
            }

            Section("About") {
                LabeledContent("Version", value: model.versionDescription)
                Button("Check for Updates…") {
                    model.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .onAppear {
            model.refreshLoginItemStatus()
        }
    }
}
