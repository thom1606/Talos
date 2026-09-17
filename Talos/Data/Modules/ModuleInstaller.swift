import Foundation
import CryptoKit
import TalosSDK

actor ModuleInstaller {
    private let modulesDirectory: URL
    init(modulesDirectory: URL = TalosPaths.modules) { self.modulesDirectory = modulesDirectory }

    func install(archive: URL, manifest: ModuleManifest, sourceID: UUID) throws -> InstalledModule {
        defer { try? FileManager.default.removeItem(at: archive) }
        guard let expected = manifest.release?.sha256 else { throw ManifestError.invalid("Missing release checksum") }
        let digest = SHA256.hash(data: try Data(contentsOf: archive, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
        guard digest == expected.lowercased() else { throw ManifestError.invalid("Release checksum does not match config.json") }
        // Validate entries BEFORE extraction: traversal and symlinks cannot write outside staging.
        let entries = try command("/usr/bin/unzip", ["-Z1", archive.path]).split(separator: "\n").map(String.init)
        guard !entries.isEmpty, entries.count < 20_000 else { throw ManifestError.invalid("Invalid archive") }
        for entry in entries {
            guard !entry.hasPrefix("/"), !entry.contains("\\"), !entry.contains("\r"),
                  !entry.split(separator: "/").contains("..") else { throw ManifestError.invalid("Unsafe archive path") }
        }
        let summary = try command("/usr/bin/unzip", ["-Z", "-t", archive.path])
        let expression = try NSRegularExpression(pattern: "([0-9]+) bytes uncompressed")
        guard let match = expression.firstMatch(in: summary, range: NSRange(summary.startIndex..., in: summary)),
              let range = Range(match.range(at: 1), in: summary), let size = Int64(summary[range]), size <= 1_073_741_824 else {
            throw ManifestError.invalid("Expanded module exceeds 1 GB or has an invalid archive summary")
        }
        let listing = try command("/usr/bin/unzip", ["-Z", "-l", archive.path])
        guard !listing.split(separator: "\n").contains(where: { $0.first == "l" }) else {
            throw ManifestError.invalid("Module archives must not contain symbolic links")
        }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        _ = try command("/usr/bin/ditto", ["-x", "-k", archive.path, staging.path])
        return try importDirectory(staging, expected: manifest, sourceID: sourceID)
    }

    func importDirectory(_ directory: URL, expected: ModuleManifest? = nil, sourceID: UUID? = nil) throws -> InstalledModule {
        let access = directory.startAccessingSecurityScopedResource()
        defer { if access { directory.stopAccessingSecurityScopedResource() } }
        let manifest = try JSONDecoder().decode(ModuleManifest.self, from: Data(contentsOf: directory.appendingPathComponent("config.json")))
        try manifest.validate()
        if let expected, !expected.hasSameContent(as: manifest) { throw ManifestError.invalid("Installed manifest differs from repository manifest") }
        let current = ProcessInfo.processInfo.operatingSystemVersion
        let os = Version("\(current.majorVersion).\(current.minorVersion).\(current.patchVersion)")!
        guard let minimum = Version(manifest.minimumMacOS), os >= minimum else { throw ManifestError.invalid("A newer macOS version is required") }
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        guard manifest.architectures.contains(architecture) else { throw ManifestError.invalid("Module does not support this Mac's architecture") }
        let app = directory.appendingPathComponent(manifest.appBundle)
        guard let bundle = Bundle(url: app), let executable = bundle.executableURL,
              (try executable.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { throw ManifestError.invalid("Missing module executable") }
        if expected != nil {
            // Published native code must pass the system's distribution assessment.
            _ = try command("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
        }
        // Verify the bundle signature; do not remove quarantine or bypass Gatekeeper.
        _ = try command("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            throw ManifestError.invalid("Cannot read module files")
        }
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw ManifestError.invalid("Module directories must not contain symbolic links")
            }
        }
        let id = UUID()
        let installed = modulesDirectory.appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: modulesDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: directory, to: installed)
        return InstalledModule(id: id, sourceID: sourceID, manifest: expected ?? manifest, directory: installed, enabled: true)
    }

    func remove(_ module: InstalledModule) throws {
        guard module.directory.deletingLastPathComponent().standardizedFileURL == modulesDirectory.standardizedFileURL else {
            throw ManifestError.invalid("Refusing to remove a directory outside the module store")
        }
        let lease = try ModuleLease(module, exclusive: true)
        try withExtendedLifetime(lease) { try FileManager.default.removeItem(at: module.directory) }
    }

    private func command(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output; process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ManifestError.invalid("Module validation failed in \(URL(fileURLWithPath: executable).lastPathComponent)")
        }
        return String(decoding: data, as: UTF8.self)
    }
}
