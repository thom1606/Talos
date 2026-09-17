import Foundation
import UniformTypeIdentifiers

public enum TalosContract {
    public static let version = 1
}

public struct RepositoryManifest: Codable, Sendable {
    public let schemaVersion: Int
    public let name: String
    public let url: URL
    public let maintainer: String
    /// Relative paths to module folders, each containing config.json.
    public let modules: [String]
}

public struct ModuleManifest: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let version: String
    public let sdkVersion: Int
    public let minimumMacOS: String
    public let architectures: [String]
    public let appBundle: String
    public let actions: [ModuleAction]
    public let release: ModuleRelease?

    public func validate() throws {
        guard sdkVersion == TalosContract.version else { throw ManifestError.invalid("Unsupported SDK version: \(sdkVersion)") }
        guard Self.validIdentifier(id), !name.isEmpty, !actions.isEmpty,
              Self.safeComponent(appBundle), appBundle.hasSuffix(".app"),
              Version(version) != nil, Version(minimumMacOS) != nil else {
            throw ManifestError.invalid("Invalid module identity, version or app bundle")
        }
        var ids = Set<String>()
        func check(_ items: [ModuleAction], depth: Int) throws {
            guard depth <= 5, items.count <= 64 else {
                throw ManifestError.invalid("Use submenus of at most 64 declared actions, up to five levels deep")
            }
            for action in items {
                guard Self.validIdentifier(action.id), !action.title.isEmpty, ids.insert(action.id).inserted else {
                    throw ManifestError.invalid("Invalid or duplicate action ID")
                }
                guard action.minimumFiles >= 1, action.maximumFiles.map({ $0 >= action.minimumFiles }) ?? true else {
                    throw ManifestError.invalid("Invalid file selection limits")
                }
                if let children = action.children {
                    guard !children.isEmpty else { throw ManifestError.invalid("Empty submenu") }
                    try check(children, depth: depth + 1)
                }
            }
        }
        try check(actions, depth: 0)
        if let release {
            guard !release.tag.isEmpty, Self.safeComponent(release.asset),
                  release.sha256.count == 64, release.sha256.allSatisfy({ $0.isHexDigit }) else {
                throw ManifestError.invalid("Invalid release asset or SHA-256")
            }
        }
    }

    /// Release transport metadata lives only in the repository, avoiding a self-referential archive checksum.
    public func hasSameContent(as other: ModuleManifest) -> Bool {
        id == other.id && name == other.name && description == other.description && version == other.version &&
        sdkVersion == other.sdkVersion && minimumMacOS == other.minimumMacOS && architectures == other.architectures &&
        appBundle == other.appBundle && actions == other.actions
    }

    public static func safeComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\") && !value.contains("\0")
    }

    public static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 120 && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) } && value != "." && value != ".."
    }
}

public struct ModuleRelease: Codable, Sendable, Equatable {
    public let tag: String
    public let asset: String
    public let sha256: String
}

public struct ModuleAction: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let symbol: String?
    public let acceptedTypes: [String]
    public let minimumFiles: Int
    public let maximumFiles: Int?
    public let children: [ModuleAction]?

    public func matches(_ files: [ModuleFile]) -> Bool {
        guard files.count >= minimumFiles, maximumFiles.map({ files.count <= $0 }) ?? true else { return false }
        return files.allSatisfy { file in
            acceptedTypes.contains { accepted in
                if accepted == "public.folder" { return file.isDirectory && !file.isPackage }
                guard let type = UTType(file.typeIdentifier), let expected = UTType(accepted) else { return false }
                return type.conforms(to: expected)
            }
        }
    }

    public func filtered(for files: [ModuleFile]) -> ModuleAction? {
        guard matches(files) else { return nil }
        guard let children else { return self }
        let matching = children.compactMap { $0.filtered(for: files) }
        guard !matching.isEmpty else { return nil }
        return ModuleAction(id: id, title: title, symbol: symbol, acceptedTypes: acceptedTypes,
                            minimumFiles: minimumFiles, maximumFiles: maximumFiles, children: matching)
    }
}

public struct ModuleFile: Codable, Sendable, Equatable {
    public let url: URL
    public let typeIdentifier: String
    public let isDirectory: Bool
    public let isPackage: Bool
    public init(url: URL, typeIdentifier: String, isDirectory: Bool = false, isPackage: Bool = false) {
        self.url = url; self.typeIdentifier = typeIdentifier; self.isDirectory = isDirectory; self.isPackage = isPackage
    }
}

public struct Version: Comparable, Sendable {
    public let components: [Int]
    public init?(_ raw: String) {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == parts.count else { return nil }
        components = values + Array(repeating: 0, count: 3 - values.count)
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.components.lexicographicallyPrecedes(rhs.components) }
}

public enum ManifestError: LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
}
