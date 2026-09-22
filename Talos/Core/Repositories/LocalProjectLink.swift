import Foundation

/// A security-scoped link to a local extension project used for development.
nonisolated struct LocalProjectLink: Codable, Sendable, Equatable, Identifiable {
    let id: String
    var bookmark: Data
    let lastKnownName: String
    let lastKnownPath: String
}

@MainActor
enum LocalProjectLinkStore {
    static func load() -> [LocalProjectLink] {
        load(from: TalosPreferences.defaults)
    }

    static func load(from defaults: UserDefaults) -> [LocalProjectLink] {
        defaults.data(forKey: TalosPreferenceKey.linkedLocalProjects)
            .flatMap { try? JSONDecoder().decode([LocalProjectLink].self, from: $0) }
            ?? []
    }

    static func save(_ links: [LocalProjectLink]) {
        save(links, to: TalosPreferences.defaults)
    }

    static func save(_ links: [LocalProjectLink], to defaults: UserDefaults) {
        do {
            defaults.set(
                try JSONEncoder().encode(links),
                forKey: TalosPreferenceKey.linkedLocalProjects
            )
        } catch {
            NSLog("Cannot save linked local projects: %@", error.localizedDescription)
        }
    }
}
