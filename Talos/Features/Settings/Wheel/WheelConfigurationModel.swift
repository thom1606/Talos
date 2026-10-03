import Foundation
import Observation

@MainActor
@Observable
final class WheelConfigurationModel {
    private(set) var configuration: WheelConfiguration

    @ObservationIgnored private let defaults: UserDefaults

    convenience init() {
        self.init(defaults: TalosPreferences.defaults)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        configuration = WheelConfigurationStore.load(from: defaults)
    }

    private static func ids(in items: [WheelItem]) -> Set<UUID> {
        Set(items.flatMap { [$0.id] + Array(ids(in: $0.children ?? [])) })
    }

    func items(for wheel: WheelKind) -> [WheelItem] {
        configuration.items(for: wheel)
    }

    func replaceItems(with items: [WheelItem], in wheel: WheelKind) {
        guard items != configuration.items(for: wheel) else { return }

        let previousIDs = Self.ids(in: configuration.allItems)
        configuration.replaceItems(with: items, in: wheel)
        let removed = previousIDs.subtracting(Self.ids(in: configuration.allItems))
        WheelConfigurationStore.save(configuration, to: defaults)
        for id in removed {
            do { try ActionSettingSecretStore().remove(for: id) }
            catch { NSLog("Could not remove action password: %@", error.localizedDescription) }
        }
    }
}
