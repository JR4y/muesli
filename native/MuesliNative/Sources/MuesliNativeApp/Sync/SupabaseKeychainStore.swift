import Foundation
import Security

/// Stores and retrieves the Supabase session in the macOS Keychain.
/// One service entry per app variant (`Bundle.main.bundleIdentifier`).
struct SupabaseKeychainStore {
    enum Account: String {
        case refreshToken = "refresh_token"
        case accessToken = "access_token"
        case expiresAt = "expires_at"      // ISO8601 timestamp
        case userID = "user_id"
        case email = "email"
    }

    let service: String

    init(service: String = SupabaseConfig.keychainService) {
        self.service = service
    }

    func read(_ account: Account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String, for account: Account) {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    func delete(_ account: Account) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(query as CFDictionary)
    }

    func wipeAll() {
        for account in Account.allCases {
            delete(account)
        }
    }
}

extension SupabaseKeychainStore.Account: CaseIterable {}
