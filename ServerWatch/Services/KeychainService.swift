import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case storeFailed(OSStatus)
    case loadFailed(OSStatus)
    case notFound

    var errorDescription: String? {
        switch self {
        case .storeFailed(let status): return "Keychain store failed (OSStatus \(status))"
        case .loadFailed(let status):  return "Keychain load failed (OSStatus \(status))"
        case .notFound:                return "Key not found in Keychain"
        }
    }
}

enum KeychainService {

    private static let service = "com.serverhealth.sshkeys"

    static func store(privateKey: Data, for keyId: String) throws {
        // Delete any existing entry under the same account so SecItemAdd succeeds.
        delete(for: keyId)

        let query: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    service,
            kSecAttrAccount as String:    keyId,
            kSecValueData as String:      privateKey,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.storeFailed(status) }
    }

    static func load(for keyId: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyId,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw KeychainError.notFound }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }
        return data
    }

    @discardableResult
    static func delete(for keyId: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keyId
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }
}
