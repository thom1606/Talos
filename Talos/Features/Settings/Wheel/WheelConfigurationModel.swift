import Foundation
import Observation

@MainActor
@Observable
final class WheelConfigurationModel {
    private(set) var items: [WheelItem]

    @ObservationIgnored private let defaults: UserDefaults

    convenience init() {
        self.init(defaults: TalosPreferences.defaults)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        items = WheelConfigurationStore.load(from: defaults).items
    }

    func replaceItems(with items: [WheelItem]) {
        guard items != self.items else { return }

        self.items = items
        WheelConfigurationStore.save(WheelConfiguration(items: items), to: defaults)
    }
}
