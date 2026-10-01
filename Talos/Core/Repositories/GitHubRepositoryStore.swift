import Foundation

nonisolated struct InstalledGitHubRepository: Codable, Sendable, Identifiable {
    let repository: GitHubRepository
    let extensionID: String
    let version: String
    let releaseID: Int64
    let assetID: Int64
    var id: String { repository.presentationID }
}

nonisolated struct ImportedPackage: Codable, Sendable, Identifiable {
    let extensionID: String
    let version: String
    let filename: String
    var id: String { "package:\(extensionID)" }
}

/// Network and Keychain work stay off the UI actor. Credentials are never persisted in defaults.
actor GitHubRepositoryStore {
    private let defaults: UserDefaults
    private let client: GitHubRepositoryClient
    private let tokens: GitHubTokenStore
    private let installer: TalosPackageInstaller
    private var busy = false
    nonisolated static let preferenceKey = "installedGitHubRepositories"

    init(defaults: UserDefaults = .standard, client: GitHubRepositoryClient = .init(),
         tokens: GitHubTokenStore = .init(), directory: URL = SDKRuntime.defaultExtensionsDirectory) {
        self.defaults = defaults
        self.client = client
        self.tokens = tokens
        installer = .init(root: directory)
    }

    nonisolated static func installed(in defaults: UserDefaults) -> [InstalledGitHubRepository] {
        defaults.data(forKey: preferenceKey)
            .flatMap { try? JSONDecoder().decode([InstalledGitHubRepository].self, from: $0) } ?? []
    }

    nonisolated static let importedPreferenceKey = "importedPackages"

    nonisolated static func imported(in defaults: UserDefaults) -> [ImportedPackage] {
        defaults.data(forKey: importedPreferenceKey)
            .flatMap { try? JSONDecoder().decode([ImportedPackage].self, from: $0) } ?? []
    }

    func importPackage(_ url: URL) throws {
        guard !busy else { throw GitHubRepositoryError.busy }
        busy = true
        defer { busy = false }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw GitHubRepositoryError.invalidPackage }
        guard let size = values.fileSize, size <= GitHubRepositoryClient.maximumPackageSize else {
            throw GitHubRepositoryError.packageTooLarge
        }
        let package = try installer.stage(Data(contentsOf: url), digest: nil)
        defer { try? FileManager.default.removeItem(at: package.directory) }
        guard !Self.installed(in: defaults).contains(where: { $0.extensionID == package.manifest.id }),
              !LocalProjectLinkStore.load(from: defaults).contains(where: { $0.id == package.manifest.id }) else {
            throw GitHubRepositoryError.alreadyInstalled
        }
        var packages = Self.imported(in: defaults)
        let previous = packages.first { $0.extensionID == package.manifest.id }
        packages.removeAll { $0.extensionID == package.manifest.id }
        packages.append(.init(extensionID: package.manifest.id, version: package.manifest.version,
                              filename: url.lastPathComponent))
        let encoded = try JSONEncoder().encode(packages)
        try Task.checkCancellation()
        try installer.commit(package, replacing: previous?.extensionID)
        defaults.set(encoded, forKey: Self.importedPreferenceKey)
    }

    func removeImported(_ package: ImportedPackage) throws {
        guard !busy else { throw GitHubRepositoryError.busy }
        let packages = Self.imported(in: defaults)
        guard packages.contains(where: { $0.id == package.id && $0.extensionID == package.extensionID }) else { return }
        let directory = installer.root.appendingPathComponent(package.extensionID).standardizedFileURL
        guard directory.deletingLastPathComponent().path == installer.root.standardizedFileURL.path else {
            throw GitHubRepositoryError.invalidPackage
        }
        let encoded = try JSONEncoder().encode(packages.filter { $0.id != package.id })
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        defaults.set(encoded, forKey: Self.importedPreferenceKey)
    }

    func install(url: String, token suppliedToken: String) async throws {
        // Actor reentrancy must not allow two downloads to commit the same identity.
        guard !busy else { throw GitHubRepositoryError.busy }
        busy = true
        defer { busy = false }
        let reference = try GitHubRepositoryReference(url)
        let suppliedToken = suppliedToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousToken = try tokens.token(for: reference.keychainAccount)
        let token = suppliedToken.isEmpty ? previousToken : suppliedToken
        let repository = try await client.fetch(reference, token: token)
        let canonicalReference = try repository.reference
        guard canonicalReference.keychainAccount == reference.keychainAccount else { throw GitHubRepositoryError.moved }
        let release = try await client.latestRelease(reference, token: token)
        let asset = try release.packageAsset()
        let data = try await client.download(asset, from: reference, token: token)
        let package = try installer.stage(data, digest: asset.digest)
        defer { try? FileManager.default.removeItem(at: package.directory) }
        var installed = Self.installed(in: defaults)
        let previous = installed.first { $0.repository.id == repository.id }
        guard !installed.contains(where: { $0.repository.id != repository.id && $0.extensionID == package.manifest.id }) else {
            throw GitHubRepositoryError.alreadyInstalled
        }
        let link = InstalledGitHubRepository(repository: repository, extensionID: package.manifest.id,
            version: package.manifest.version, releaseID: release.id, assetID: asset.id)
        installed.removeAll { $0.id == link.id }
        installed.append(link)
        let encoded = try JSONEncoder().encode(installed)
        try Task.checkCancellation()
        // From this point onward the commit is synchronous and cannot be half-cancelled.
        if let token { try tokens.save(token, for: reference.keychainAccount) }
        do {
            try installer.commit(package, replacing: previous?.extensionID)
        } catch {
            if let previousToken { try? tokens.save(previousToken, for: reference.keychainAccount) }
            else { try? tokens.remove(for: reference.keychainAccount) }
            throw error
        }
        defaults.set(encoded, forKey: Self.preferenceKey)
    }

    func latestRelease(for link: InstalledGitHubRepository) async throws -> GitHubRelease {
        let reference = try link.repository.reference
        return try await client.latestRelease(reference, token: tokens.token(for: reference.keychainAccount))
    }

    func remove(_ link: InstalledGitHubRepository) throws {
        guard !busy else { throw GitHubRepositoryError.busy }
        let account = try link.repository.reference.keychainAccount
        // Only delete credentials and an installation owned by this saved repository.
        guard Self.installed(in: defaults).contains(where: { $0.id == link.id && $0.extensionID == link.extensionID }) else { return }
        let path = installer.root.appendingPathComponent(link.extensionID).standardizedFileURL
        guard path.deletingLastPathComponent().path == installer.root.standardizedFileURL.path else {
            throw GitHubRepositoryError.invalidPackage
        }
        let oldToken = try tokens.token(for: account)
        try tokens.remove(for: account)
        do {
            if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
        } catch {
            if let oldToken { try? tokens.save(oldToken, for: account) }
            throw error
        }
        let remaining = Self.installed(in: defaults).filter { $0.id != link.id }
        defaults.set(try JSONEncoder().encode(remaining), forKey: Self.preferenceKey)
    }
}
