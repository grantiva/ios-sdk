import Foundation
import Security

internal class TokenManager {
    private let keychainService = "com.grantiva.sdk.tokens"
    private let tokenKey = "grantiva_attestation_token"
    private let expirationKey = "grantiva_token_expiration"
    
    func saveToken(_ token: String, expiresAt: Date) {
        saveToKeychain(key: tokenKey, value: token)
        
        let expirationString = ISO8601DateFormatter().string(from: expiresAt)
        saveToKeychain(key: expirationKey, value: expirationString)
    }
    
    func getStoredToken() -> (token: String, expiresAt: Date)? {
        guard let token = getFromKeychain(key: tokenKey),
              let expirationString = getFromKeychain(key: expirationKey),
              let expiresAt = ISO8601DateFormatter().date(from: expirationString) else {
            return nil
        }
        
        return (token: token, expiresAt: expiresAt)
    }
    
    func isTokenExpired(_ expiresAt: Date) -> Bool {
        let bufferTime: TimeInterval = 300
        return Date().addingTimeInterval(bufferTime) >= expiresAt
    }
    
    func clearTokens() {
        deleteFromKeychain(key: tokenKey)
        deleteFromKeychain(key: expirationKey)
    }
    
    private func saveToKeychain(key: String, value: String) {
        let data = value.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Failed to save \(key) to keychain: \(status)")
        }
    }
    
    private func getFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}