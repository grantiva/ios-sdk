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

    // Device metadata — sent alongside attestation so the backend doesn't need
    // to guess from CBOR (which doesn't contain this data).
    let deviceModel: String?
    let osVersion: String?
    let appVersion: String?
    let appBuildNumber: String?
    let platform: String?
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