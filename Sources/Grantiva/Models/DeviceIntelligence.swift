import Foundation

/// Risk category for a device. Available on all tiers.
public enum RiskCategory: String, Codable, CaseIterable {
    /// Score 0–20: device is trusted.
    case trusted = "trusted"
    /// Score 21–75: device shows suspicious signals.
    case suspicious = "suspicious"
    /// Score 76–100: device is blocked.
    case blocked = "blocked"
}

public struct DeviceIntelligence: Codable {
    public let deviceId: String
    /// Risk score from 0–100. `nil` when risk scoring is unavailable (simulator, Free tier, or API key mode).
    public let riskScore: Int?
    /// Risk category derived from the score. Available on all tiers.
    public let riskCategory: RiskCategory
    public let deviceIntegrity: String
    public let jailbreakDetected: Bool
    public let attestationCount: Int
    public let lastAttestationDate: Date?

    public init(deviceId: String, riskScore: Int?, riskCategory: RiskCategory = .trusted, deviceIntegrity: String, jailbreakDetected: Bool, attestationCount: Int, lastAttestationDate: Date? = nil) {
        self.deviceId = deviceId
        self.riskScore = riskScore
        self.riskCategory = riskCategory
        self.deviceIntegrity = deviceIntegrity
        self.jailbreakDetected = jailbreakDetected
        self.attestationCount = attestationCount
        self.lastAttestationDate = lastAttestationDate
    }
}
