import Foundation
import Security
import TalosSDK

actor RepositoryCredentials {
    private let service = "com.thom1606.Talos.repositories"
    func token(for id: UUID) throws -> String? {
        var query = query(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw ManifestError.invalid("Cannot read repository credential (Keychain \(status))")
        }
        return String(data: data, encoding: .utf8)
    }
    func set(_ token: String, for id: UUID) throws {
        let base = query(id)
        if token.isEmpty {
            let status = SecItemDelete(base as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw ManifestError.invalid("Cannot remove credential") }
            return
        }
        let values = [kSecValueData as String: Data(token.utf8)]
        var status = SecItemUpdate(base as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(base.merging(values) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ManifestError.invalid("Cannot save repository credential (Keychain \(status))") }
    }
    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString]
    }
}
