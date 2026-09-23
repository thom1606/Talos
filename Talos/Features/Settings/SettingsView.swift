import SwiftUI

struct SettingsView: View {
    let advancedSettingsModel: AdvancedSettingsModel
    let repositoriesModel: RepositoriesModel

    @AppStorage("selectedSettingsPage", store: TalosPreferences.defaults) private var selection = SettingsPage.wheel
    @State private var wheelConfigurationModel = WheelConfigurationModel()

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $selection) { page in
                Label(page.title, systemImage: page.symbolName)
                    .tag(page)
            }
            .listStyle(.sidebar)
            .navigationTitle("Talos")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            NavigationStack {
                page
                    .navigationTitle(selection.title)
            }
            .id(selection)
        }
        .frame(minWidth: 820, minHeight: 540)
    }

    @ViewBuilder
    private var page: some View {
        switch selection {
        case .wheel:
            WheelSettingsView(
                tiles: repositoriesModel.tiles,
                configuration: wheelConfigurationModel
            )
        case .repositories:
            RepositoriesView(model: repositoriesModel)
        case .advanced:
            AdvancedSettingsView(model: advancedSettingsModel)
        }
    }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case wheel
    case repositories
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .wheel: String(localized: "Wheel")
        case .repositories: String(localized: "Repositories")
        case .advanced: String(localized: "Advanced")
        }
    }

    var symbolName: String {
        switch self {
        case .wheel: "circle.hexagonpath"
        case .repositories: "shippingbox"
        case .advanced: "gearshape.2"
        }
    }
}
