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

        // Delete any existing key first
        deleteAPIKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Check if an API key is stored.
    var hasAPIKey: Bool {
        retrieveAPIKey() != nil
    }
}
