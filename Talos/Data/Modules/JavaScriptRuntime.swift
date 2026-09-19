import Foundation

/// Each action runs in its own bundled Node process. No end-user toolchain is required.
@MainActor
final class JavaScriptRuntime {
    static func launch(module: InstalledModule, invocation: ModuleInvocation, settings: [String: String], hostBundle: URL = Bundle.main.bundleURL) throws -> Process {
        let process = Process()
        let bundle = hostBundle
        let executable = bundle.appendingPathComponent("Contents/Helpers/node")
        let runner = Bundle(url: hostBundle)?.url(forResource: "runner", withExtension: "mjs")
            ?? bundle.appendingPathComponent("Contents/Resources/JavaScript/runner.mjs")
        guard FileManager.default.isExecutableFile(atPath: executable.path),
              FileManager.default.fileExists(atPath: runner.path), let entry = module.manifest.entrypoint else {
            throw ManifestError.invalid("The bundled JavaScript runtime is missing. Reinstall Talos.")
        }
        process.executableURL = executable
        process.arguments = [runner.path, module.directory.appendingPathComponent(entry).path,
                             invocation.workspace.appendingPathComponent("invocation.json").path]
        process.currentDirectoryURL = module.directory
        // Do not inherit NODE_OPTIONS or developer preload hooks into an installed action.
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
                               "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                               "TMPDIR": FileManager.default.temporaryDirectory.path]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let data = try JSONEncoder().encode(settings)
        guard data.count <= 16_384 else { throw ManifestError.invalid("Action settings are too large") }
        try process.run()
        do {
            try input.fileHandleForWriting.write(contentsOf: data)
            try input.fileHandleForWriting.close()
        } catch {
            process.terminate()
            throw error
        }
        return process
    }
}
