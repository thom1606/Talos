import Foundation
import TalosSDK

/// Authorization is scoped to api.github.com. Redirects to release storage lose it.
nonisolated final class GitHubRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard request.url?.scheme == "https" else { completionHandler(nil); return }
        var request = request
        if request.url?.host != "api.github.com" { request.setValue(nil, forHTTPHeaderField: "Authorization") }
        completionHandler(request)
    }
}

actor GitHubRepositoryService {
    private let session = URLSession(configuration: .ephemeral, delegate: GitHubRedirectPolicy(), delegateQueue: nil)

    func refresh(_ source: RepositorySource, token: String?) async throws -> RepositorySource {
        let repository: RepositoryManifest = try await contents(source, path: "repository.json", token: token)
        guard repository.schemaVersion == TalosContract.version, repository.modules.count <= 100 else {
            throw ManifestError.invalid("Unsupported repository format or too many modules")
        }
        var result = source
        result.name = repository.name
        var modules: [ModuleManifest] = []
        var ids = Set<String>()
        for folder in repository.modules {
            guard ModuleManifest.safeComponent(folder) else { throw ManifestError.invalid("Invalid module folder") }
            let module: ModuleManifest = try await contents(source, path: "\(folder)/config.json", token: token)
            try module.validate()
            guard ids.insert(module.id).inserted else { throw ManifestError.invalid("Duplicate module ID in repository") }
            modules.append(module)
        }
        result.modules = modules; result.lastChecked = .now; result.error = nil
        return result
    }

    func download(_ manifest: ModuleManifest, from source: RepositorySource, token: String?) async throws -> URL {
        guard let release = manifest.release else { throw ManifestError.invalid("This module has no published release") }
        let url = api(source).appendingPathComponent("releases").appendingPathComponent("tags").appendingPathComponent(release.tag)
        let data = try await fetch(url, token: token)
        let response = try JSONDecoder().decode(Release.self, from: data)
        guard !response.draft, let asset = response.assets.first(where: { $0.name == release.asset }),
              asset.size > 0, asset.size <= 512 * 1024 * 1024 else {
            throw ManifestError.invalid("Release asset missing or larger than 512 MB")
        }
        let assetURL = api(source).appendingPathComponent("releases/assets/\(asset.id)")
        var request = request(assetURL, token: token)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (temporary, responseData) = try await session.download(for: request)
        try check(responseData)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    private struct Release: Decodable { let draft: Bool; let assets: [Asset] }
    private struct Asset: Decodable { let id: Int; let name: String; let size: Int }
    private struct Contents: Decodable { let content: String; let encoding: String }

    private func contents<T: Decodable & Sendable>(_ source: RepositorySource, path: String, token: String?) async throws -> T {
        let data = try await fetch(api(source).appendingPathComponent("contents").appendingPathComponent(path), token: token)
        let result = try JSONDecoder().decode(Contents.self, from: data)
        guard result.encoding == "base64", let decoded = Data(base64Encoded: result.content, options: .ignoreUnknownCharacters), decoded.count <= 1_000_000 else {
            throw ManifestError.invalid("Repository manifest is invalid or too large")
        }
        return try JSONDecoder().decode(T.self, from: decoded)
    }
    private func api(_ source: RepositorySource) -> URL {
        URL(string: "https://api.github.com/repos")!.appendingPathComponent(source.owner).appendingPathComponent(source.repository)
    }
    private func request(_ url: URL, token: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Talos", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }
    private func fetch(_ url: URL, token: String?) async throws -> Data {
        let (data, response) = try await session.data(for: request(url, token: token))
        try check(response)
        return data
    }
    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ManifestError.invalid("GitHub returned HTTP \(code). Check the repository URL, token permissions and rate limit.")
        }
    }
}
