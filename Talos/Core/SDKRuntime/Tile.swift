import Foundation

/// A tile stores the user-specific state needed to activate one extension action.
/// Display metadata and supported file types remain owned by the extension manifest.
nonisolated struct Tile: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var extensionBundleID: String
    var action: String
    var titleOverride: String?
    var config: [String: TileConfigValue]

    init(
        id: UUID = UUID(),
        extensionBundleID: String,
        action: String,
        titleOverride: String? = nil,
        config: [String: TileConfigValue] = [:]
    ) {
        self.id = id
        self.extensionBundleID = extensionBundleID
        self.action = action
        self.titleOverride = titleOverride
        self.config = config
    }
}

/// Values supported by the TypeScript `TalosContext.config` contract.
nonisolated enum TileConfigValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case boolean(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.typeMismatch(
                TileConfigValue.self,
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a string, number, or boolean"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .boolean(value):
            try container.encode(value)
        }
    }
}
