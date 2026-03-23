import Foundation
import Security

enum APIKeyService: String {
    case elevenLabs = "com.voiceink.elevenlabs-api-key"
}

final class KeychainManager {
    static let shared = KeychainManager()
    private init() {}

    func saveAPIKey(_ key: String, for service: APIKeyService) throws {
        let data = Data(key.utf8)

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.rawValue
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func getAPIKey(for service: APIKeyService) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    func deleteAPIKey(for service: APIKeyService) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service.rawValue
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    func hasAPIKey(for service: APIKeyService) -> Bool {
        getAPIKey(for: service) != nil
    }

    /// On first launch, migrate API key from environment variable to Keychain
    func migrateFromEnvironmentIfNeeded() {
        guard !hasAPIKey(for: .elevenLabs),
              let envKey = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"],
              !envKey.isEmpty else {
            return
        }
        try? saveAPIKey(envKey, for: .elevenLabs)
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain (status: \(status))"
        }
    }
}
