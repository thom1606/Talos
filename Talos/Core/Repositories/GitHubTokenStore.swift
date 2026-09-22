import Foundation
import Security

/// Only the host reads these credentials; they never enter an extension context.
nonisolated struct GitHubTokenStore: Sendable {
    let service: String

    init(service: String = "com.thom1606.Talos.GitHub") {
        self.service = service
    }

    private func query(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    func token(for account: String) throws -> String? {
        var query = query(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else { throw GitHubRepositoryError.keychain(status) }
        return token
    }

    func save(_ token: String, for account: String) throws {
        let query = query(for: account)
        let attributes = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(token.utf8)
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw GitHubRepositoryError.keychain(added) }
        } else if status != errSecSuccess {
            throw GitHubRepositoryError.keychain(status)
        }
    }

    func remove(for account: String) throws {
        let status = SecItemDelete(query(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitHubRepositoryError.keychain(status)
        }
    }
}
