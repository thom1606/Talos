import AppKit
import CryptoKit

@main struct JavaScriptHostChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        var manifest: [String: Any] = ["id": "test.javascript", "name": "JavaScript test", "description": "Integration test",
            "version": "1.0.0", "sdkVersion": 1, "minimumMacOS": "26.0", "architectures": ["arm64", "x86_64"],
            "runtime": "javascript", "entrypoint": "extension.mjs",
            "actions": [["id": "copy", "title": "Copy", "acceptedTypes": ["public.data"], "minimumFiles": 1]]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: source.appendingPathComponent("config.json"))
        let script = """
        import { copyFile } from 'node:fs/promises';
        import { constants } from 'node:fs';
        export default { actions: [{ id: 'copy', async run(session) {
          if (session.settings.secret !== 'test-only-value') throw new Error('Missing pipe settings');
          await session.progress(0.5, 'Copying');
          const output = session.files[0].path + '.copy';
          await copyFile(session.files[0].path, output, constants.COPYFILE_EXCL);
          await session.complete('Copied', [output]);
        } }] };
        """
        try Data(script.utf8).write(to: source.appendingPathComponent("extension.mjs"))
        let archive = root.appendingPathComponent("extension.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", source.path, archive.path]
        try zip.run(); zip.waitUntilExit()
        precondition(zip.terminationStatus == 0)
        let digest = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
        manifest["release"] = ["tag": "v1.0.0", "asset": "extension.zip", "sha256": digest]
        let published = try JSONDecoder().decode(ModuleManifest.self, from: JSONSerialization.data(withJSONObject: manifest))
        let installer = ModuleInstaller(modulesDirectory: root.appendingPathComponent("installed"))
        let localArchive = root.appendingPathComponent("extension.talos")
        try FileManager.default.copyItem(at: archive, to: localArchive)
        let imported = try await installer.importPackage(localArchive)
        precondition(imported.manifest.id == "test.javascript")
        precondition(FileManager.default.fileExists(atPath: localArchive.path), "Import must preserve the package")
        try await installer.remove(imported)
        let installed = try await installer.install(archive: archive, manifest: published, sourceID: UUID())
        let original = root.appendingPathComponent("input.txt")
        try Data("Original".utf8).write(to: original)
        let store = ModuleJobStore(directory: root.appendingPathComponent("jobs"))
        let invocation = try await store.create(module: installed, action: "copy", files: [ModuleFile(url: original, typeIdentifier: "public.plain-text")])
        let process = try JavaScriptRuntime.launch(module: installed, invocation: invocation,
            settings: ["secret": "test-only-value"], hostBundle: URL(fileURLWithPath: CommandLine.arguments[1]))
        let deadline = Date.now.addingTimeInterval(15)
        while process.isRunning && Date.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        precondition(!process.isRunning, "JavaScript action did not exit")
        precondition(process.terminationStatus == 0)
        let events = try await store.read(invocation)
        precondition(events.map(\.kind) == [.progress, .completed])
        let originalContents = try String(contentsOf: original, encoding: .utf8)
        let copiedContents = try String(contentsOf: URL(fileURLWithPath: original.path + ".copy"), encoding: .utf8)
        precondition(originalContents == "Original" && copiedContents == "Original")
        let persisted = try String(contentsOf: invocation.workspace.appendingPathComponent("invocation.json"), encoding: .utf8)
        precondition(!persisted.contains("test-only-value"))
        print("Passed: unsigned JavaScript release installation, bundled runtime, private settings pipe, progress and real file output")
    }
}
