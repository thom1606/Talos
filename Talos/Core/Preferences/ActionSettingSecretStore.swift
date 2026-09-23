import Foundation
import Security

/// Password settings are kept out of the wheel configuration in UserDefaults.
nonisolated struct ActionSettingSecretStore: Sendable {
    private let service = "com.thom1606.Talos.ActionSettings"

    private func query(for tileID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tileID.uuidString,
            kSecAttrSynchronizable as String: false,
        ]
    }

    func passwords(for tileID: UUID) throws -> [String: String] {
        var request = query(for: tileID)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess, let data = result as? Data else {
            throw ActionSettingSecretError.keychain(status)
        }
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    func save(_ passwords: [String: String], for tileID: UUID) throws {
        let query = query(for: tileID)
        let data = try JSONEncoder().encode(passwords)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw ActionSettingSecretError.keychain(added) }
        } else if status != errSecSuccess {
            throw ActionSettingSecretError.keychain(status)
        }
    }

    func remove(for tileID: UUID) throws {
        let status = SecItemDelete(query(for: tileID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ActionSettingSecretError.keychain(status)
        }
    }
}

nonisolated enum ActionSettingSecretError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain:
            "Couldn't access the action password in Keychain. Unlock Keychain and try again."
        }
    }
}
