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

    private static func ids(in items: [WheelItem]) -> Set<UUID> {
        Set(items.flatMap { [$0.id] + Array(ids(in: $0.children ?? [])) })
    }

    func replaceItems(with items: [WheelItem]) {
        guard items != self.items else { return }

        let removed = Self.ids(in: self.items).subtracting(Self.ids(in: items))
        self.items = items
        WheelConfigurationStore.save(WheelConfiguration(items: items), to: defaults)
        for id in removed {
            do { try ActionSettingSecretStore().remove(for: id) }
            catch { NSLog("Could not remove action password: %@", error.localizedDescription) }
        }
    }
}
