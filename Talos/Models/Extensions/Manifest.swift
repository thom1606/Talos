import Foundation
import UniformTypeIdentifiers

nonisolated public enum TalosContract {
    public static let version = 1
}

nonisolated public struct RepositoryManifest: Codable, Sendable {
    public let schemaVersion: Int
    public let name: String
    public let url: URL
    public let maintainer: String
    /// Relative paths to module folders, each containing config.json.
    public let modules: [String]
}

nonisolated public struct ModuleManifest: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let version: String
    public let sdkVersion: Int
    public let minimumMacOS: String
    public let architectures: [String]
    public var runtime: String? = nil
    public var entrypoint: String? = nil
    public let actions: [ModuleAction]
    public let release: ModuleRelease?

    public func validate() throws {
        guard sdkVersion == TalosContract.version else { throw ManifestError.invalid("Unsupported SDK version: \(sdkVersion)") }
        guard Self.validIdentifier(id), !name.isEmpty, !actions.isEmpty,
              runtime == "javascript", entrypoint.map({ Self.safeComponent($0) && $0.hasSuffix(".mjs") }) == true,
              Version(version) != nil, Version(minimumMacOS) != nil else {
            throw ManifestError.invalid("Invalid module identity, version or JavaScript entrypoint")
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
                var fieldIDs = Set<String>()
                for field in action.settings ?? [] {
                    guard Self.validIdentifier(field.id), !field.label.isEmpty, fieldIDs.insert(field.id).inserted else {
                        throw ManifestError.invalid("Invalid or duplicate settings field")
                    }
                    if field.type == .select, field.choices?.isEmpty != false {
                        throw ManifestError.invalid("A select setting needs choices")
                    }
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
        runtime == other.runtime && entrypoint == other.entrypoint && actions == other.actions
    }

    public static func safeComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\") && !value.contains("\0")
    }

    public static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 120 && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) } && value != "." && value != ".."
    }
}
