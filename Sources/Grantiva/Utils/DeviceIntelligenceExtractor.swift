import Foundation

internal enum DeviceIntelligenceExtractor {

    /// Builds the public `DeviceIntelligence` from the attestation response body.
    static func extractFromResponse(_ response: DeviceIntelligenceResponse) -> DeviceIntelligence {
        let dateFormatter = ISO8601DateFormatter()
        return DeviceIntelligence(
            deviceId: response.deviceId,
            riskScore: response.riskScore,
            riskCategory: RiskCategory(rawValue: response.riskCategory) ?? .trusted,
            deviceIntegrity: response.deviceIntegrity,
            jailbreakDetected: response.jailbreakDetected,
            attestationCount: response.attestationCount,
            lastAttestationDate: response.lastAttestationDate.flatMap { dateFormatter.date(from: $0) }
        )
    }
}
