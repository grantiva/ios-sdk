import Foundation

internal struct ChallengeResponse: Codable {
    let challenge: String
    let expiresAt: String
}

internal struct AttestationRequest: Codable {
    let bundleId: String
    let teamId: String
    let keyId: String
    let attestationObject: String
    let clientDataHash: String
    let challenge: String
}

internal struct AttestationResponse: Codable {
    let isValid: Bool
    let token: String
    let expiresAt: String
    let deviceIntelligence: DeviceIntelligenceResponse
    let customClaims: [String: String]
}

internal struct DeviceIntelligenceResponse: Codable {
    let deviceId: String
    let riskScore: Int
    let deviceIntegrity: String
    let jailbreakDetected: Bool
    let attestationCount: Int
    let lastAttestationDate: String?
}

internal struct ErrorResponse: Codable {
    let reason: String
}