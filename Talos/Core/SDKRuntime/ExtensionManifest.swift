import Foundation

nonisolated struct ExtensionManifest: Codable, Sendable, Equatable, Identifiable {
    let name: String
    let version: String
    let description: String?
    let talos: TalosConfiguration
    let commands: [ExtensionCommand]

    var id: String { talos.bundleID }

    struct TalosConfiguration: Codable, Sendable, Equatable {
        let bundleID: String
        let entry: String
        let locales: [String: String]

        private enum CodingKeys: String, CodingKey {
            case bundleID = "bundleId"
            case entry
            case locales
        }
    }

    func validate() throws {
        guard Self.isBundleID(talos.bundleID) else {
            throw SDKRuntimeError.invalidManifest("Invalid bundle ID: \(talos.bundleID)")
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !version.isEmpty,
              !commands.isEmpty
        else {
            throw SDKRuntimeError.invalidManifest("Extension identity and commands cannot be empty")
        }
        guard Self.isSafeRelativePath(talos.entry), talos.entry.hasSuffix(".mjs") else {
            throw SDKRuntimeError.invalidManifest("The extension entry must be a safe .mjs path")
        }
        guard talos.locales["en"] != nil else {
            throw SDKRuntimeError.invalidManifest("The extension must define an English locale")
        }

        var commandNames = Set<String>()
        for command in commands {
            guard Self.isIdentifier(command.name),
                  !command.displayName.isEmpty,
                  command.icon?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != true,
                  !command.supportedFileTypes.isEmpty,
                  commandNames.insert(command.name).inserted
            else {
                throw SDKRuntimeError.invalidManifest("Invalid or duplicate action: \(command.name)")
            }
        }
    }

    private static func isBundleID(_ value: String) -> Bool {
        guard let first = value.first, first.isASCII, first.isLowercase, first.isLetter else {
            return false
        }
        return value.allSatisfy {
            $0.isASCII && (($0.isLowercase && $0.isLetter) || $0.isNumber || $0 == "-")
        }
    }

    private static func isIdentifier(_ value: String) -> Bool {
        isBundleID(value)
    }

    private static func isSafeRelativePath(_ value: String) -> Bool {
        !value.isEmpty &&
            !value.hasPrefix("/") &&
            !value.split(separator: "/").contains("..") &&
            !value.contains("\\") &&
            !value.contains("\0")
    }
}

nonisolated struct ExtensionCommand: Codable, Sendable, Equatable, Identifiable {
    let name: String
    let displayName: String
    let icon: String?
    let description: String?
    let supportedFileTypes: [String]
    let settings: [ExtensionSetting]?

    var id: String { name }
}

nonisolated struct ExtensionSetting: Codable, Sendable, Equatable, Identifiable {
    let name: String
    let displayName: String
    let type: ValueType
    let description: String?
    let required: Bool?
    let defaultValue: TileConfigValue?
    let options: [String]?

    var id: String { name }

    enum ValueType: String, Codable, Sendable {
        case text
        case password
        case number
        case boolean
        case select
    }
}

nonisolated struct LoadedExtension: Identifiable, Sendable, Equatable {
    let manifest: ExtensionManifest
    let directory: URL
    let entrypoint: URL

    var id: String { manifest.id }
}

nonisolated struct ExtensionLoadFailure: Sendable, Equatable {
    let directory: URL
    let message: String
}
