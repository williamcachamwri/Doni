import Foundation
import Security
import TdSession

/// The TDLib database key, created once and kept in the Keychain.
///
/// TDLib keeps the logged-in session in its own database under Application
/// Support. That file is only secret while the device is locked if the key is
/// not stored next to it, which is the whole reason this class exists.
/// `bytes` fields in the JSON interface are base64, so that is the form
/// TDLib is handed.
struct KeychainDatabaseKey: TdDatabaseKeyProviding {
    enum Failure: Error, Equatable {
        case randomBytes(status: Int)
        case save(status: Int)
    }

    private static let service = "local.doni.app.tdlib"
    private static let account = "database-encryption-key"

    func databaseEncryptionKey() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let key = String(data: data, encoding: .utf8) {
            return key
        }
        return try store()
    }

    /// Generates 32 random bytes, writes them, and returns the value to use
    /// now — reading it back after the add would only race with itself.
    private func store() throws -> String {
        var raw = [UInt8](repeating: 0, count: 32)
        let random = SecRandomCopyBytes(kSecRandomDefault, raw.count, &raw)
        guard random == errSecSuccess else { throw Failure.randomBytes(status: Int(random)) }
        let key = Data(raw).base64EncodedString()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            // Never copied to another device, and unreadable while locked.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            kSecValueData as String: Data(key.utf8),
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.save(status: Int(status)) }
        return key
    }
}
