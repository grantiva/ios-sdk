import Foundation

/// `customClaims` is `[String: Any]` for source compatibility; the SDK only ever
/// populates it with the `String` values the server returns, and every stored
/// property is immutable, so the value is safe to pass across concurrency domains.
public struct AttestationResult: @unchecked Sendable {
    public let isValid: Bool
    public let token: String
    public let expiresAt: Date
    public let deviceIntelligence: DeviceIntelligence
    public let customClaims: [String: Any]
    
    public init(isValid: Bool, token: String, expiresAt: Date, deviceIntelligence: DeviceIntelligence, customClaims: [String: Any] = [:]) {
        self.isValid = isValid
        self.token = token
        self.expiresAt = expiresAt
        self.deviceIntelligence = deviceIntelligence
        self.customClaims = customClaims
    }
}