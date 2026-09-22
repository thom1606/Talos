import CryptoKit
import Foundation
import ZIPFoundation

nonisolated struct TalosPackageInstaller {
    let root: URL
    static let maximumExpandedSize = 256 * 1_024 * 1_024

    struct StagedPackage {
        let directory: URL
        let manifest: ExtensionManifest
    }

    func stage(_ data: Data, digest: String?) throws -> StagedPackage {
        guard data.count <= GitHubRepositoryClient.maximumPackageSize else { throw GitHubRepositoryError.packageTooLarge }
        if let digest {
            let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest.lowercased() == "sha256:\(checksum)" else { throw GitHubRepositoryError.invalidPackage }
        }
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = root.appendingPathComponent(".install-\(UUID().uuidString)")
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            let archive = try Archive(data: data, accessMode: .read)
            var paths = Set<String>()
            var expandedSize = 0
            var count = 0
            for entry in archive {
                try Task.checkCancellation()
                count += 1
                guard count <= 4096, entry.type != .symlink else { throw GitHubRepositoryError.invalidPackage }
                let relativePath = entry.path
                let components = relativePath.split(separator: "/")
                guard !relativePath.hasPrefix("/"), !relativePath.contains("\\"), !relativePath.contains("\0"),
                      !components.isEmpty, !components.contains(".."), !components.contains("."),
                      paths.insert(components.joined(separator: "/").precomposedStringWithCanonicalMapping.lowercased()).inserted
                else { throw GitHubRepositoryError.invalidPackage }
                guard entry.uncompressedSize <= Self.maximumExpandedSize else { throw GitHubRepositoryError.packageTooLarge }
                let destination = directory.appendingPathComponent(relativePath)
                if entry.type == .directory {
                    try manager.createDirectory(at: destination, withIntermediateDirectories: true)
                } else {
                    try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    guard manager.createFile(atPath: destination.path, contents: nil) else { throw GitHubRepositoryError.invalidPackage }
                    let handle = try FileHandle(forWritingTo: destination)
                    defer { try? handle.close() }
                    var fileSize = 0
                    let checksum = try archive.extract(entry) { chunk in
                        try Task.checkCancellation()
                        expandedSize += chunk.count
                        fileSize += chunk.count
                        guard expandedSize <= Self.maximumExpandedSize, fileSize <= entry.uncompressedSize else {
                            throw GitHubRepositoryError.packageTooLarge
                        }
                        try handle.write(contentsOf: chunk)
                    }
                    guard checksum == entry.checksum, fileSize == entry.uncompressedSize else {
                        throw GitHubRepositoryError.invalidPackage
                    }
                }
            }
            let manifest = try JSONDecoder().decode(
                ExtensionManifest.self,
                from: Data(contentsOf: directory.appendingPathComponent("package.json"))
            )
            try manifest.validate()
            for path in [manifest.talos.entry] + Array(manifest.talos.locales.values) {
                let destination = directory.appendingPathComponent(path).standardizedFileURL
                guard destination.path.hasPrefix(directory.path + "/"),
                      try destination.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
                else { throw GitHubRepositoryError.invalidPackage }
            }
            return .init(directory: directory, manifest: manifest)
        } catch {
            try? manager.removeItem(at: directory)
            if error is CancellationError { throw CancellationError() }
            if let error = error as? GitHubRepositoryError { throw error }
            throw GitHubRepositoryError.invalidPackage
        }
    }

    /// The verified staging directory is on the same volume as the installation.
    func commit(_ package: StagedPackage, replacing extensionID: String?) throws {
        if let extensionID, extensionID != package.manifest.id { throw GitHubRepositoryError.identityMismatch }
        let destination = root.appendingPathComponent(package.manifest.id)
        if FileManager.default.fileExists(atPath: destination.path) {
            guard extensionID != nil else { throw GitHubRepositoryError.alreadyInstalled }
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: package.directory)
        } else {
            try FileManager.default.moveItem(at: package.directory, to: destination)
        }
    }
}
