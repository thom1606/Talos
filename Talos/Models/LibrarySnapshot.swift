import Foundation

nonisolated struct LibrarySnapshot: Codable, Sendable {
    var repositories: [RepositorySource] = []
    var installed: [InstalledModule] = []
    var actionOrder: [String] = []
    var disabledActions: Set<String> = []
    var wheel: [WheelEntry]?
    init() {}
    private enum CodingKeys: String, CodingKey { case repositories, installed, actionOrder, disabledActions, wheel }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        repositories = try values.decodeIfPresent([RepositorySource].self, forKey: .repositories) ?? []
        installed = try values.decodeIfPresent([InstalledModule].self, forKey: .installed) ?? []
        actionOrder = try values.decodeIfPresent([String].self, forKey: .actionOrder) ?? []
        disabledActions = try values.decodeIfPresent(Set<String>.self, forKey: .disabledActions) ?? []
        wheel = try values.decodeIfPresent([WheelEntry].self, forKey: .wheel)
    }
}
