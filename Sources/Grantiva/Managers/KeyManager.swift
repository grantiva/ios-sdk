import Foundation
import Security
import DeviceCheck

internal class KeyManager {
    private let keychainService = "com.grantiva.sdk.keys"
    private let keyIdKey = "grantiva_attest_key_id"
    
    func getOrCreateKeyId() async throws -> String {
        if let existingKeyId = getStoredKeyId() {
            print("[KeyManager] Found existing key ID: \(existingKeyId)")
            return existingKeyId
        }
        
        print("[KeyManager] No existing key ID found, generating new one...")
        
        guard DCAppAttestService.shared.isSupported else {
            print("[KeyManager] ERROR: App Attest not supported")
            throw GrantivaError.attestationNotAvailable
        }
        
        do {
            print("[KeyManager] Calling DCAppAttestService.generateKey()...")
            let keyId = try await DCAppAttestService.shared.generateKey()
            print("[KeyManager] Generated new key ID: \(keyId)")
            saveKeyId(keyId)
            return keyId
        } catch {
            print("[KeyManager] ERROR generating key: \(error)")
            throw GrantivaError.keyGenerationFailed
        }
    }
    
    func saveKeyId(_ keyId: String) {
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
            print("Failed to save key ID to keychain: \(status)")
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
    
    func clearStoredKeyId() {
        print("[KeyManager] Clearing stored key ID...")
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keyIdKey
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            print("[KeyManager] Successfully cleared key ID")
        } else if status == errSecItemNotFound {
            print("[KeyManager] No key ID to clear")
        } else {
            print("[KeyManager] Error clearing key ID: \(status)")
        }
    }
}