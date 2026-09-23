import Foundation

/// Persists the wheel in the Talos application's standard preferences.
@MainActor
enum WheelConfigurationStore {
    static func load() -> WheelConfiguration {
        load(from: TalosPreferences.defaults)
    }

    static func load(from defaults: UserDefaults) -> WheelConfiguration {
        guard let data = defaults.data(forKey: TalosPreferenceKey.wheelConfiguration) else {
            let configuration = WheelConfiguration(items: ["talos-actions.crop", "talos-actions.archive", "talos-actions.organize", "talos-actions.compress", "talos-actions.convert", "talos.system.settings"].map { .action($0) })
            save(configuration, to: defaults)
            return configuration
        }

        do {
            let configuration = try JSONDecoder().decode(WheelConfiguration.self, from: data)
            guard configuration.schemaVersion == WheelConfiguration.currentSchemaVersion else {
                NSLog(
                    "Cannot load wheel configuration schema %d",
                    configuration.schemaVersion
                )
                return WheelConfiguration()
            }
            return configuration
        } catch {
            NSLog("Cannot load the wheel configuration: %@", error.localizedDescription)
            return WheelConfiguration()
        }
    }

    static func save(_ configuration: WheelConfiguration) {
        save(configuration, to: TalosPreferences.defaults)
    }

    static func save(_ configuration: WheelConfiguration, to defaults: UserDefaults) {
        do {
            defaults.set(
                try JSONEncoder().encode(configuration),
                forKey: TalosPreferenceKey.wheelConfiguration
            )
        } catch {
            NSLog("Cannot save the wheel configuration: %@", error.localizedDescription)
        }
    }
}
