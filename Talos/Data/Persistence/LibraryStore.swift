import Foundation
import OSLog

actor LibraryStore {
    private let file: URL
    init(root: URL = TalosPaths.root) { file = root.appendingPathComponent("library.json") }
    func load() throws -> LibrarySnapshot {
        guard FileManager.default.fileExists(atPath: file.path) else { return LibrarySnapshot() }
        return try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: file))
    }
    // Only the host can read its old sandbox. Publish the shared snapshot last.
    func migrateLegacyLibrary() throws {
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        let old = TalosPaths.legacyRoot
        let source = old.appendingPathComponent("library.json")
        Logger(subsystem: "com.thom1606.Talos", category: "migration").notice("Migrating \(source.path, privacy: .public) to \(self.file.path, privacy: .public)")
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        var snapshot = try JSONDecoder().decode(LibrarySnapshot.self, from: Data(contentsOf: source))
        try FileManager.default.createDirectory(at: TalosPaths.modules, withIntermediateDirectories: true)
        for index in snapshot.installed.indices {
            let module = snapshot.installed[index]
            let destination = TalosPaths.modules.appendingPathComponent(module.id.uuidString)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: module.directory, to: destination)
            }
            snapshot.installed[index].directory = destination
        }
        try save(snapshot)
    }
    func save(_ snapshot: LibrarySnapshot) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
    }
}
