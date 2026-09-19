import Foundation
import Security

/// Secrets are isolated per wheel placement and never written into the library snapshot.
actor TileCredentials {
    func load(_ tile: String) throws -> [String: String] {
        var query = query(tile)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess, let data = result as? Data else {
            throw ManifestError.invalid("Cannot read action settings from Keychain (\(status))")
        }
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    func save(_ values: [String: String], tile: String) throws {
        let base = query(tile)
        let data = try JSONEncoder().encode(values)
        let updates = [kSecValueData as String: data]
        var status = SecItemUpdate(base as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(base.merging(updates) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ManifestError.invalid("Cannot save action settings to Keychain (\(status))") }
    }

    private func query(_ tile: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.thom1606.Talos.tiles",
         kSecAttrAccount as String: tile]
    }
}
