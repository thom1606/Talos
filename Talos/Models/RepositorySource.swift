import Foundation

nonisolated struct RepositorySource: Codable, Identifiable, Sendable {
    let id: UUID
    let owner: String
    let repository: String
    var name: String
    var modules: [ModuleManifest]
    var lastChecked: Date?
    var error: String?
    var localDirectory: URL?
    var isLocal: Bool { localDirectory != nil }
    var slug: String { localDirectory?.path ?? "\(owner)/\(repository)" }
    init(directory: URL, name: String? = nil) {
        id = UUID(); owner = ""; repository = ""; localDirectory = directory
        self.name = name ?? directory.lastPathComponent; modules = []
    }

    init(url: String) throws {
        guard let parsed = URL(string: url), parsed.scheme == "https", parsed.host?.lowercased() == "github.com",
              parsed.user == nil, parsed.password == nil, parsed.query == nil, parsed.fragment == nil else {
            throw ManifestError.invalid("Use https://github.com/owner/repository")
        }
        let parts = parsed.path.split(separator: "/").map(String.init)
        guard parts.count == 2, parts.allSatisfy(ModuleManifest.validIdentifier) else {
            throw ManifestError.invalid("Use a GitHub repository URL, without a branch or subfolder")
        }
        id = UUID(); owner = parts[0]
        repository = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
        guard !repository.isEmpty else { throw ManifestError.invalid("Missing repository name") }
        name = "\(owner)/\(repository)"; modules = []
    }
}
