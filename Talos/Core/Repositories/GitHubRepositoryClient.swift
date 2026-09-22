import Foundation

nonisolated struct GitHubRelease: Decodable, Sendable {
    let id: Int64
    let assets: [Asset]
    var tagName: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, assets
        case tagName = "tag_name"
    }

    struct Asset: Decodable, Sendable {
        let id: Int64
        let name: String
        let size: Int
        let digest: String?
    }

    func packageAsset() throws -> Asset {
        let packages = assets.filter { $0.name.lowercased().hasSuffix(".talos") }
        guard packages.count == 1, let asset = packages.first, asset.id > 0 else {
            throw GitHubRepositoryError.releasePackage
        }
        guard asset.size > 0, asset.size <= GitHubRepositoryClient.maximumPackageSize else {
            throw GitHubRepositoryError.packageTooLarge
        }
        return asset
    }
}

nonisolated struct GitHubRepositoryClient: Sendable {
    static let maximumPackageSize = 128 * 1_024 * 1_024
    typealias Transport = @Sendable (URLRequest, Int) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport

    init(transport: @escaping Transport = { request, limit in try await GitHubRepositoryClient.send(request, limit: limit) }) {
        self.transport = transport
    }

    func fetch(_ reference: GitHubRepositoryReference, token: String?) async throws -> GitHubRepository {
        let (data, response) = try await transport(Self.request(for: reference, token: token), 2_097_152)
        try Self.validate(response)
        guard let repository = try? JSONDecoder().decode(GitHubRepository.self, from: data),
              repository.id > 0, (try? repository.reference) != nil
        else { throw GitHubRepositoryError.response }
        return repository
    }

    func latestRelease(_ reference: GitHubRepositoryReference, token: String?) async throws -> GitHubRelease {
        var request = try Self.request(for: reference, token: token)
        request.url = reference.apiURL.appending(path: "releases/latest")
        let (data, response) = try await transport(request, 2_097_152)
        if response.statusCode == 404 { throw GitHubRepositoryError.releaseUnavailable }
        try Self.validate(response)
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data), release.id > 0 else {
            throw GitHubRepositoryError.response
        }
        return release
    }

    func download(_ asset: GitHubRelease.Asset, from reference: GitHubRepositoryReference, token: String?) async throws -> Data {
        guard asset.id > 0, asset.size > 0, asset.size <= Self.maximumPackageSize else {
            throw GitHubRepositoryError.packageTooLarge
        }
        var request = try Self.request(for: reference, token: token)
        request.url = reference.apiURL.appending(path: "releases/assets/\(asset.id)")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        for _ in 0..<5 {
            let (data, response) = try await transport(request, Self.maximumPackageSize)
            if (300...399).contains(response.statusCode) {
                guard let location = response.value(forHTTPHeaderField: "Location"),
                      let url = URL(string: location), Self.isAllowedDownloadURL(url)
                else { throw GitHubRepositoryError.unsafeDownload }
                // A fresh request deliberately drops Authorization and all other API headers.
                request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
                continue
            }
            try Self.validate(response)
            guard data.count == asset.size else { throw GitHubRepositoryError.invalidPackage }
            return data
        }
        throw GitHubRepositoryError.unsafeDownload
    }

    static func isAllowedDownloadURL(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443, parts.fragment == nil
        else { return false }
        return ["release-assets.githubusercontent.com", "objects.githubusercontent.com", "github.com"].contains(parts.host)
    }

    static func request(for reference: GitHubRepositoryReference, token: String?) throws -> URLRequest {
        var request = URLRequest(url: reference.apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Talos", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            guard token.utf8.allSatisfy({ (33...126).contains($0) }) else {
                throw GitHubRepositoryError.invalidToken
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200: return
        case 301...308: throw GitHubRepositoryError.moved
        case 401: throw GitHubRepositoryError.authentication
        case 403 where response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0":
            throw GitHubRepositoryError.rateLimited
        case 403, 404: throw GitHubRepositoryError.inaccessible
        case 429: throw GitHubRepositoryError.rateLimited
        default: throw GitHubRepositoryError.response
        }
    }

    static func send(_ request: URLRequest, limit: Int) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: GitHubRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw GitHubRepositoryError.response }
            guard response.expectedContentLength <= limit else { throw GitHubRepositoryError.packageTooLarge }
            var data = Data()
            for try await byte in bytes {
                guard data.count < limit else { throw GitHubRepositoryError.packageTooLarge }
                data.append(byte)
            }
            try Task.checkCancellation()
            return (data, response)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as GitHubRepositoryError {
            throw error
        } catch {
            throw GitHubRepositoryError.network
        }
    }
}

/// Redirects are handled explicitly, with a new request that carries no token.
nonisolated final class GitHubRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
