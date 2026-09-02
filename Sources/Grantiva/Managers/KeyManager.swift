import Foundation
import Security
import DeviceCheck

internal final class KeyManager {
    private let keychainService = "com.grantiva.sdk.keys"
    private let keyIdKey = "grantiva_attest_key_id"
    private let attestedKey = "grantiva_attest_key_attested"
    
    func getOrCreateKeyId() async throws -> String {
        if let existingKeyId = getStoredKeyId() {
            Logger.debug("[KeyManager] Existing key ID found in keychain")
            return existingKeyId
        }
        
        Logger.debug("[KeyManager] No existing key ID found, generating new one")
        
        guard DCAppAttestService.shared.isSupported else {
            Logger.error("[KeyManager] App Attest is not supported on this device")
            throw GrantivaError.attestationNotAvailable
        }
        
        do {
            Logger.debug("[KeyManager] Calling DCAppAttestService.generateKey()")
            let keyId = try await DCAppAttestService.shared.generateKey()
            Logger.debug("[KeyManager] Generated new key ID")
            try saveKeyId(keyId)
            return keyId
        } catch {
            Logger.error("[KeyManager] Failed to generate key: \(error)")
            throw GrantivaError.keyGenerationFailed
        }
    }
    
    func saveKeyId(_ keyId: String) throws {
        let data = keyId.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keyIdKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            Logger.error("[KeyManager] Failed to save key ID to Keychain (OSStatus \(status)) — key will be lost")
            throw GrantivaError.keyGenerationFailed
        }
    }
    
    func getStoredKeyId() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keyIdKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let keyId = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return keyId
    }
    
    /// Marks the current key as having been successfully attested on the server.
    /// After this is set, token refresh will use the assertion path instead of re-attesting.
    func markAsAttested() {
        let data = "true".data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: attestedKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            Logger.error("[KeyManager] Failed to mark key as attested (OSStatus \(status))")
        }
    }

    /// Returns true if the current key has been successfully attested on the server.
    func hasBeenAttested() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: attestedKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    func clearStoredKeyId() {
        Logger.debug("[KeyManager] Clearing stored key ID")
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keyIdKey
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            Logger.debug("[KeyManager] Successfully cleared key ID")
        } else if status == errSecItemNotFound {
            Logger.debug("[KeyManager] No key ID to clear")
        } else {
            Logger.error("[KeyManager] Failed to clear key ID (OSStatus \(status))")
        }

        // Also clear the attested flag so the next key goes through full attestation
        let attestedQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: attestedKey
        ]
        SecItemDelete(attestedQuery as CFDictionary)
    }
}