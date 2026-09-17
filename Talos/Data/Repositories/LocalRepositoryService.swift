import Foundation
import TalosSDK

actor LocalRepositoryService {
    func refresh(_ source: RepositorySource) throws -> RepositorySource {
        guard let root = source.localDirectory else { throw ManifestError.invalid("Missing local repository folder") }
        let entries = try manifests(in: root)
        guard Set(entries.map { $0.1.id }).count == entries.count else { throw ManifestError.invalid("Duplicate module IDs") }
        var result = source
        if let data = try? Data(contentsOf: root.appendingPathComponent("repository.json")) {
            result.name = try JSONDecoder().decode(RepositoryManifest.self, from: data).name
        }
        result.modules = entries.map(\.1); result.lastChecked = .now; result.error = nil
        return result
    }
    func directory(for manifest: ModuleManifest, source: RepositorySource) throws -> URL {
        guard let root = source.localDirectory,
              let entry = try manifests(in: root).first(where: { $0.1.id == manifest.id }) else {
            throw ManifestError.invalid("Module missing from local repository")
        }
        guard entry.1.hasSameContent(as: manifest) else { throw ManifestError.invalid("Local module changed; refresh the repository first") }
        return entry.0
    }
    private func manifests(in root: URL) throws -> [(URL, ModuleManifest)] {
        let repo = root.appendingPathComponent("repository.json")
        let directories: [URL]
        if FileManager.default.fileExists(atPath: repo.path) {
            let manifest = try JSONDecoder().decode(RepositoryManifest.self, from: Data(contentsOf: repo))
            guard manifest.schemaVersion == TalosContract.version, manifest.modules.count <= 100,
                  manifest.modules.allSatisfy(ModuleManifest.safeComponent) else { throw ManifestError.invalid("Invalid local repository manifest") }
            directories = manifest.modules.map { root.appendingPathComponent($0) }
        } else { directories = [root] }
        return try directories.map { directory in
            let manifest = try JSONDecoder().decode(ModuleManifest.self, from: Data(contentsOf: directory.appendingPathComponent("config.json")))
            try manifest.validate()
            return (directory, manifest)
        }
    }
}
