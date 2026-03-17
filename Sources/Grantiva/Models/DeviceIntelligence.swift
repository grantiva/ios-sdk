import Foundation

/// Risk category exposed to all tiers.
/// The numeric `riskScore` is only available on Pro and above.
public enum RiskCategory: String, Codable, CaseIterable {
    /// Score 0-20: device is trusted.
    case trusted = "trusted"
    /// Score 21-75: device shows some suspicious signals.
    case suspicious = "suspicious"
    /// Score 76-100: device is blocked.
    case blocked = "blocked"
}

public struct DeviceIntelligence: Codable {
    public let deviceId: String
    /// Numeric risk score (0-100). `nil` on free tier — upgrade to Pro to access.
    public let riskScore: Int?
    /// Risk category derived from the score. Available on all tiers.
    public let riskCategory: RiskCategory
    public let deviceIntegrity: String
    public let jailbreakDetected: Bool
    public let attestationCount: Int
    public let lastAttestationDate: Date?

    public init(
        deviceId: String,
        riskScore: Int?,
        riskCategory: RiskCategory,
        deviceIntegrity: String,
        jailbreakDetected: Bool,
        attestationCount: Int,
        lastAttestationDate: Date? = nil
    ) {
        self.deviceId = deviceId
        self.riskScore = riskScore
        self.riskCategory = riskCategory
        self.deviceIntegrity = deviceIntegrity
        self.jailbreakDetected = jailbreakDetected
        self.attestationCount = attestationCount
        self.lastAttestationDate = lastAttestationDate
    }
}
