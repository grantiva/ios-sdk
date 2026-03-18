import Foundation

public struct DeviceIntelligence {
    public let deviceId: String
    /// Risk score from 0–100. `nil` when risk scoring is unavailable (simulator, Free tier, or API key mode).
    public let riskScore: Int?
    public let deviceIntegrity: String
    public let jailbreakDetected: Bool
    public let attestationCount: Int
    public let lastAttestationDate: Date?

    public init(deviceId: String, riskScore: Int?, deviceIntegrity: String, jailbreakDetected: Bool, attestationCount: Int, lastAttestationDate: Date? = nil) {
        self.deviceId = deviceId
        self.riskScore = riskScore
        self.deviceIntegrity = deviceIntegrity
        self.jailbreakDetected = jailbreakDetected
        self.attestationCount = attestationCount
        self.lastAttestationDate = lastAttestationDate
    }
}