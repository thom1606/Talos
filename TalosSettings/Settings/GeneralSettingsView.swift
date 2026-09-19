import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @State private var model = GeneralSettingsModel()
    @AppStorage("automaticUpdates", store: AppPreferences.defaults) private var automaticUpdates = true
    @AppStorage("hoverSound", store: AppPreferences.defaults) private var hoverSound = true
    @AppStorage("completionSound", store: AppPreferences.defaults) private var completionSound = true

    var body: some View {
        Form {
            Section("Startup and updates") {
                Toggle("Start at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                    .disabled(model.loginPending)
                    .accessibilityIdentifier("advanced.startAtLogin")
                Toggle("Check for updates automatically", isOn: $automaticUpdates)
                    .accessibilityIdentifier("advanced.automaticUpdates")
                if model.status.loginNeedsApproval {
                    Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                        .accessibilityIdentifier("advanced.allowLoginItem")
                }
                if let error = model.error ?? model.status.error { Text(error).foregroundStyle(.red) }
            }
            Section("Sounds") {
                Toggle("Item hover", isOn: $hoverSound)
                    .accessibilityIdentifier("advanced.hoverSound")
                Toggle("Action completed", isOn: $completionSound)
                    .accessibilityIdentifier("advanced.completionSound")
            }
            Section("About") {
                LabeledContent("Version", value: model.version)
                Button("Check for Updates…") { model.checkUpdates() }
                    .accessibilityIdentifier("advanced.checkForUpdates")
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .task {
            model.reload()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
                model.reload()
            }
        }
    }
}
