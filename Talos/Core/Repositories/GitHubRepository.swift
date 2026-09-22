import Foundation

nonisolated struct GitHubRepositoryReference: Sendable, Equatable {
    let owner: String
    let name: String

    init(_ input: String) throws {
        guard let url = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host?.lowercased() == "github.com",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil
        else { throw GitHubRepositoryError.invalidURL }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2 else { throw GitHubRepositoryError.invalidURL }
        let owner = String(parts[0])
        var name = String(parts[1])
        if name.hasSuffix(".git") { name.removeLast(4) }
        let ownerCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        let repositoryCharacters = ownerCharacters.union(CharacterSet(charactersIn: "_."))
        guard !owner.isEmpty, !name.isEmpty, name != ".", name != "..",
              owner.unicodeScalars.allSatisfy(ownerCharacters.contains),
              name.unicodeScalars.allSatisfy(repositoryCharacters.contains)
        else { throw GitHubRepositoryError.invalidURL }
        self.owner = owner
        self.name = name
    }

    var fullName: String { "\(owner)/\(name)" }
    var keychainAccount: String { fullName.lowercased() }
    var webURL: URL { URL(string: "https://github.com/\(fullName)")! }
    var apiURL: URL { URL(string: "https://api.github.com/repos/\(fullName)")! }
}

nonisolated struct GitHubRepository: Codable, Sendable, Identifiable, Equatable {
    let id: Int64
    let fullName: String
    let isPrivate: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case isPrivate = "private"
    }

    var presentationID: String { "github:\(id)" }
    var reference: GitHubRepositoryReference {
        get throws { try GitHubRepositoryReference("https://github.com/\(fullName)") }
    }
}

nonisolated enum GitHubRepositoryError: LocalizedError {
    case invalidURL, invalidToken, authentication, inaccessible, rateLimited, moved, network, response
    case keychain(OSStatus)
    case busy
    case releaseUnavailable, releasePackage, packageTooLarge, invalidPackage, unsafeDownload, identityMismatch, alreadyInstalled

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a repository URL such as https://github.com/owner/repository."
        case .invalidToken: "The personal access token contains invalid characters."
        case .authentication: "GitHub rejected this token. Check that it is valid and has not expired."
        case .inaccessible: "The repository is unavailable. For a private repository, provide a token with access to that repository and read-only Contents permission. Your organization may also need to approve it."
        case .rateLimited: "GitHub is limiting requests. Try again later or provide a personal access token."
        case .moved: "This repository has moved. Enter its current GitHub URL."
        case .network: "Couldn’t connect to GitHub. Check your connection and try again."
        case .response: "GitHub returned an unexpected response. Try again later."
        case .busy: "Another repository operation is still running. Try again when it finishes."
        case .releaseUnavailable: "No published release is available, or the token cannot read releases. Private repositories require read-only Contents permission."
        case .releasePackage: "The latest release must contain exactly one .talos package."
        case .packageTooLarge: "This extension exceeds the download or extraction size limit."
        case .invalidPackage: "The release contains an invalid or unsafe Talos package."
        case .unsafeDownload: "GitHub returned an unsupported download destination."
        case .identityMismatch: "This release uses a different extension ID from the installed version."
        case .alreadyInstalled: "Another source already installed an extension with this ID. Remove it before adding this repository."
        case .keychain: "Couldn’t access the GitHub token in Keychain. Unlock your keychain and try again."
        }
    }
}
