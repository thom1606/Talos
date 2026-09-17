import PackagePlugin
import Foundation
import CryptoKit

/// One packaging implementation for every action repository.
@main struct TalosBuild: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        guard arguments.allSatisfy({ $0 == "--release" }) else {
            throw BuildError("Usage: swift package talos-build [--release]")
        }
        let root = context.package.directoryURL
        let configURL = root.appendingPathComponent("config.json")
        guard var config = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any],
              let bundle = config["appBundle"] as? String, bundle.hasSuffix(".app"),
              !bundle.contains("/"), !bundle.contains(".."),
              let identifier = config["id"] as? String,
              let name = config["name"] as? String,
              let version = config["version"] as? String,
              let minimum = config["minimumMacOS"] as? String,
              version.range(of: #"^\d+(\.\d+){0,2}$"#, options: .regularExpression) != nil else {
            throw BuildError("config.json needs appBundle, id, name, version and minimumMacOS.")
        }
        let release = arguments.contains("--release")
        let environment = ProcessInfo.processInfo.environment
        let identity = environment["TALOS_MODULE_SIGNING_IDENTITY"] ?? "-"
        let profile = environment["TALOS_NOTARY_PROFILE"] ?? ""
        if release && (!identity.hasPrefix("Developer ID Application:") || profile.isEmpty) {
            throw BuildError("Publishing requires TALOS_MODULE_SIGNING_IDENTITY and TALOS_NOTARY_PROFILE. Omit --release for local development.")
        }
        let executable = String(bundle.dropLast(4))
        let result = try packageManager.build(.product(executable), parameters: .init(configuration: .release, echoLogs: true))
        guard result.succeeded,
              let binary = result.builtArtifacts.first(where: { $0.kind == .executable && $0.url.lastPathComponent == executable })?.url else {
            throw BuildError("Could not build executable product '\(executable)'.\n\(result.logText)")
        }
        let fm = FileManager.default
        let dist = root.appendingPathComponent("dist")
        let output = dist.appendingPathComponent("module")
        let app = output.appendingPathComponent(bundle)
        let macos = app.appendingPathComponent("Contents/MacOS")
        let metadata = dist.appendingPathComponent("release-config.json")
        if fm.fileExists(atPath: metadata.path) { try fm.removeItem(at: metadata) }
        if fm.fileExists(atPath: output.path) { try fm.removeItem(at: output) }
        try fm.createDirectory(at: macos, withIntermediateDirectories: true)
        try fm.copyItem(at: binary, to: macos.appendingPathComponent(executable))
        // SwiftPM resources are adjacent to the executable; preserve their lookup path.
        var embeddedResources: [URL] = []
        for resource in try fm.contentsOfDirectory(at: binary.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            where resource.pathExtension == "bundle" {
            let destination = macos.appendingPathComponent(resource.lastPathComponent)
            try fm.copyItem(at: resource, to: destination)
            embeddedResources.append(destination)
        }
        let architectures = try capture("/usr/bin/lipo", ["-archs", binary.path]).split(whereSeparator: \.isWhitespace).map(String.init)
        config["architectures"] = architectures
        config.removeValue(forKey: "release")
        try json(config).write(to: output.appendingPathComponent("config.json"))
        let plist: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleName": name,
            "CFBundleExecutable": executable, "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version,
            "CFBundleVersion": version, "LSUIElement": true, "LSMinimumSystemVersion": minimum]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try signNestedCode(in: embeddedResources, identity: identity)
        var signing = ["--force", "--sign", identity]
        if identity != "-" { signing += ["--options", "runtime", "--timestamp"] }
        try run("/usr/bin/codesign", signing + [app.path])
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        if release {
            let submission = dist.appendingPathComponent("notarization.zip")
            try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, submission.path])
            try run("/usr/bin/xcrun", ["notarytool", "submit", submission.path, "--keychain-profile", profile, "--wait"])
            try run("/usr/bin/xcrun", ["stapler", "staple", app.path])
            try run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
            try fm.removeItem(at: submission)
        }
        let asset = "\(executable)-\(version).zip"
        let archive = dist.appendingPathComponent(asset)
        if fm.fileExists(atPath: archive.path) { try fm.removeItem(at: archive) }
        try run("/usr/bin/ditto", ["-c", "-k", output.path, archive.path])
        if release {
            config["release"] = ["tag": "\(executable)-v\(version)", "asset": asset,
                "sha256": SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()]
            try json(config).write(to: metadata)
            print("Upload \(archive.path), then copy \(metadata.path) to config.json.")
        } else {
            print("In Talos: Repositories → Add repository → Local repository → \(output.path)")
            print("Development build. Use --release with Developer ID signing to distribute through GitHub.")
        }
    }

    private func json(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    }
    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw BuildError("\(URL(fileURLWithPath: executable).lastPathComponent) failed (\(process.terminationStatus)).") }
    }
    private func capture(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let pipe = Pipe(); process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw BuildError("Could not inspect executable architectures.") }
        return String(decoding: data, as: UTF8.self)
    }

    private func signNestedCode(in roots: [URL], identity: String) throws {
        let fm = FileManager.default
        var binaries: [URL] = []
        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                      (try? capture("/usr/bin/lipo", ["-archs", url.path])) != nil else { continue }
                binaries.append(url)
            }
        }
        for binary in binaries.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
            var arguments = ["--force", "--sign", identity]
            if identity != "-" { arguments += ["--options", "runtime", "--timestamp"] }
            try run("/usr/bin/codesign", arguments + [binary.path])
        }
        for bundle in roots.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
            var arguments = ["--force", "--sign", identity]
            if identity != "-" { arguments += ["--options", "runtime", "--timestamp"] }
            try run("/usr/bin/codesign", arguments + [bundle.path])
        }
    }
}
struct BuildError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
