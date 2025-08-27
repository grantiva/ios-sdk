import Foundation

public struct AttestationResult {
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