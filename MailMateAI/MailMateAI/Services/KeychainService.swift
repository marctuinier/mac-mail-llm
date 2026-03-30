import Foundation
import Security

/// Service for securely storing and retrieving the Gemini API key in the macOS Keychain.
final class KeychainService {
    static let shared = KeychainService()

    private let service = "com.mailmate.ai"
    private let account = AppGroupConstants.apiKeyKeychainAccount

    private init() {}

    // MARK: - API Key Management

    /// Store the Gemini API key securely in the Keychain.
    ///
    /// - Parameter apiKey: The API key string to store.
    /// - Returns: `true` if the key was stored successfully.
    @discardableResult
    func storeAPIKey(_ apiKey: String) -> Bool {
        guard let data = apiKey.data(using: .utf8) else { return false }

        deleteAPIKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: AppGroupConstants.keychainAccessGroup,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: kCFBooleanFalse!
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve the Gemini API key from the Keychain.
    ///
    /// - Returns: The API key string, or `nil` if not found.
    func retrieveAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: AppGroupConstants.keychainAccessGroup,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return key
    }

    /// Delete the API key from the Keychain.
    @discardableResult
    func deleteAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: AppGroupConstants.keychainAccessGroup
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Migrate an API key stored without an access group to the shared group.
    /// Safe to call multiple times — no-ops if no legacy key exists or if already migrated.
    func migrateToSharedAccessGroupIfNeeded() {
        // Check if a key already exists in the shared group
        if retrieveAPIKey() != nil { return }

        // Look for a key stored without an explicit access group (legacy)
        let oldQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(oldQuery as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return }

        // Re-add with the shared access group
        let newQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: AppGroupConstants.keychainAccessGroup,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: kCFBooleanFalse!
        ]
        SecItemAdd(newQuery as CFDictionary, nil)
    }

    /// Check if an API key is stored.
    var hasAPIKey: Bool {
        retrieveAPIKey() != nil
    }
}
