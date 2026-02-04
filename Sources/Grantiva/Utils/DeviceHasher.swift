import Foundation
import CommonCrypto

/// Generates a stable, anonymous device hash for spam prevention.
/// The hash is derived from the vendor identifier and cannot be reversed to identify the device.
internal class DeviceHasher {

    /// Returns a SHA-256 hash of the device's vendor identifier, providing a stable
    /// anonymous identifier for rate limiting and spam prevention.
    static func generateDeviceHash() -> String {
        let deviceId = PlatformSupport.getDeviceIdentifier()
        let salt = Bundle.main.bundleIdentifier ?? "com.grantiva.sdk"
        let input = "\(deviceId):\(salt)"
        return sha256(input)
    }

    /// Generates a stable anonymous voter ID from the device hash.
    /// This is used to track votes without exposing the device identity.
    static func generateVoterId() -> String {
        let deviceHash = generateDeviceHash()
        return sha256("voter:\(deviceHash)")
    }

    /// Generates a stable anonymous submitter ID from the device hash.
    /// This is used to track ticket/feature request submissions.
    static func generateSubmitterId() -> String {
        let deviceHash = generateDeviceHash()
        return sha256("submitter:\(deviceHash)")
    }

    private static func sha256(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
