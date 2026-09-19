import AppKit
import CryptoKit

@main
struct ModuleHostChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let example = URL(fileURLWithPath: CommandLine.arguments[1])
        let installer = ModuleInstaller(modulesDirectory: root.appendingPathComponent("installed"))
        let installed = try await installer.importDirectory(example)
        precondition(installed.manifest.id == "dev.talos.host-test")
        precondition(FileManager.default.fileExists(atPath: installed.directory.appendingPathComponent("extension.mjs").path))
        // A settings process cannot remove code while the host holds a task lease.
        var lease: ModuleLease? = try ModuleLease(installed)
        precondition(ModuleLease.isInUse(installed))
        do { try await installer.remove(installed); fatalError("Removed a running module") }
        catch is ManifestError {}
        withExtendedLifetime(lease) {}
        lease = nil
        precondition(!ModuleLease.isInUse(installed))
        let source = try RepositorySource(url: "https://github.com/example/modules.git")
        precondition(source.slug == "example/modules")
        do { _ = try RepositorySource(url: "https://github.com/example/modules/tree/main"); fatalError("Accepted non-repository URL") }
        catch is ManifestError {}

        let archive = root.appendingPathComponent("module.zip")
        let zip = Process(); zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", example.path, archive.path]
        try zip.run(); zip.waitUntilExit(); precondition(zip.terminationStatus == 0)
        let digest = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: example.appendingPathComponent("config.json"))) as! [String: Any]
        json["release"] = ["tag":"v1.0.0", "asset":"module.zip", "sha256":digest]
        let manifest = try JSONDecoder().decode(ModuleManifest.self, from: JSONSerialization.data(withJSONObject: json))
        let released = try await installer.install(archive: archive, manifest: manifest, sourceID: source.id)
        try await installer.remove(released)
        var native = json
        native.removeValue(forKey: "runtime")
        native.removeValue(forKey: "entrypoint")
        native["appBundle"] = "Old.app"
        let oldManifest = try JSONDecoder().decode(ModuleManifest.self, from: JSONSerialization.data(withJSONObject: native))
        do { try oldManifest.validate(); fatalError("Accepted a native extension") }
        catch is ManifestError {}
        let updated = try await installer.importDirectory(example)
        precondition(updated.manifest.id == manifest.id)
        precondition(FileManager.default.fileExists(atPath: installed.directory.appendingPathComponent("extension.mjs").path), "Installation replaced old version before activation")
        let corrupt = root.appendingPathComponent("bad.zip")
        try Data("invalid".utf8).write(to: corrupt)
        do { _ = try await installer.install(archive: corrupt, manifest: manifest, sourceID: source.id); fatalError("Accepted bad checksum") }
        catch is ManifestError {}

        let jobs = ModuleJobStore(directory: root.appendingPathComponent("jobs"))
        let file = root.appendingPathComponent("hello.txt")
        let input = Data("Hello from Talos".utf8)
        try input.write(to: file)
        let files = await FileInspector().inspect([file])
        precondition(files.count == 1 && files[0].typeIdentifier == "public.plain-text")
        let invocation = try await jobs.create(module: installed, action: "report", files: files)
        let progress = ModuleEvent(kind: .progress, taskID: invocation.taskID, message: "Half", fraction: 0.5, outputs: nil, actions: nil)
        let notification = ModuleEvent(kind: .notification, taskID: invocation.taskID, message: "Ready", fraction: nil, outputs: nil, actions: [.init(id: "reveal", title: "Reveal")])
        var stream = try JSONEncoder().encode(progress)
        stream.append(10)
        stream.append(try JSONEncoder().encode(notification))
        stream.append(10)
        try stream.write(to: invocation.workspace.appendingPathComponent("events.jsonl"))
        let events = try await jobs.read(invocation)
        precondition(events.count == 2)
        let next = try await jobs.read(invocation)
        precondition(next.isEmpty, "Events must not replay")
        try await jobs.registerNotification(events[1], invocation: invocation)
        let restored = try await jobs.notificationContext(id: invocation.taskID, action: "reveal")
        precondition(restored?.0 == installed.id)
        let unauthorized = try await jobs.notificationContext(id: invocation.taskID, action: "unknown")
        precondition(unauthorized == nil)
        try await jobs.cancel(invocation)
        precondition(FileManager.default.fileExists(atPath: invocation.workspace.appendingPathComponent("cancel").path))
        let actual = try await jobs.create(module: installed, action: "report", files: files)
        let process = try JavaScriptRuntime.launch(module: installed, invocation: actual, settings: [:], hostBundle: URL(fileURLWithPath: CommandLine.arguments[2]))
        let deadline = Date.now.addingTimeInterval(15)
        var completed = false
        while Date.now < deadline {
            let events = try await jobs.read(actual)
            if events.contains(where: { $0.kind == .completed }) { completed = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        if process.isRunning { process.terminate() }
        precondition(completed, "Real module did not complete")
        struct Report: Decodable { let path: String; let bytes: Int64 }
        let report = try JSONDecoder().decode([Report].self,
            from: Data(contentsOf: installed.directory.appendingPathComponent("report.json")))
        precondition(report.count == 1 && report[0].path == file.path,
                     "Report must contain exactly the selected file")
        precondition(report[0].bytes == Int64(input.count), "Report byte count must match the input")
        try await installer.remove(installed)
        try await installer.remove(updated)
        print("Passed: repository identity, JavaScript import, native-extension rejection, checksum rejection, file types, event streaming, cancellation, notification routing and real background JavaScript")
    }
}
