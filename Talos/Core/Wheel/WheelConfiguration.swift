import Foundation

/// The single wheel layout shared by the Talos host and its settings app.
nonisolated struct WheelConfiguration: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var items: [WheelItem]

    init(items: [WheelItem] = []) {
        schemaVersion = Self.currentSchemaVersion
        self.items = items
    }
}

/// A persisted action or folder in the wheel.
nonisolated struct WheelItem: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var actionID: String?
    var customTitle: String?
    var config: [String: TileConfigValue]
    var children: [Self]?

    private enum CodingKeys: String, CodingKey {
        case id, actionID, customTitle, config, children
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        actionID = try values.decodeIfPresent(String.self, forKey: .actionID)
        customTitle = try values.decodeIfPresent(String.self, forKey: .customTitle)
        config = try values.decodeIfPresent([String: TileConfigValue].self, forKey: .config) ?? [:]
        children = try values.decodeIfPresent([Self].self, forKey: .children)
    }

    init(id: UUID, actionID: String?, customTitle: String?, config: [String: TileConfigValue], children: [Self]?) {
        self.id = id
        self.actionID = actionID
        self.customTitle = customTitle
        self.config = config
        self.children = children
    }

    var isFolder: Bool {
        children != nil
    }

    static func action(
        _ actionID: String,
        id: UUID = UUID(),
        customTitle: String? = nil
    ) -> Self {
        .init(
            id: id,
            actionID: actionID,
            customTitle: customTitle,
            config: [:],
            children: nil
        )
    }

    static func folder(
        _ title: String,
        id: UUID = UUID(),
        children: [Self] = []
    ) -> Self {
        .init(
            id: id,
            actionID: nil,
            customTitle: title,
            config: [:],
            children: children
        )
    }

    static func items(in roots: [Self], at path: [ID]) -> [Self] {
        guard let folderID = path.first else { return roots }
        guard
            let folder = roots.first(where: { $0.id == folderID }),
            let children = folder.children
        else {
            return roots
        }

        return items(in: children, at: Array(path.dropFirst()))
    }

    static func replacingItems(
        in roots: [Self],
        at path: [ID],
        with replacement: [Self]
    ) -> [Self] {
        guard let folderID = path.first else { return replacement }
        guard let folderIndex = roots.firstIndex(where: { $0.id == folderID }) else {
            return roots
        }

        var result = roots
        var folder = result[folderIndex]
        folder.children = replacingItems(
            in: folder.children ?? [],
            at: Array(path.dropFirst()),
            with: replacement
        )
        result[folderIndex] = folder
        return result
    }

    static func updating(_ updatedItem: Self, in items: [Self]) -> [Self] {
        items.map { item in
            if item.id == updatedItem.id {
                return updatedItem
            }

            guard let children = item.children else { return item }
            var folder = item
            folder.children = updating(updatedItem, in: children)
            return folder
        }
    }
}
