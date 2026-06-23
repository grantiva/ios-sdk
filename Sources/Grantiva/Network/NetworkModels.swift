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

    /// Stable hardware-derived fingerprint (hex SHA256 of identifierForVendor on
    /// iOS). The backend uses this as a secondary key in MAD lookup so the same
    /// physical device counts once even when its App Attest key is regenerated
    /// mid-billing-period by the self-heal path. The raw identifier is never
    /// transmitted — only its hash.
    let deviceFingerprint: String?

    /// App-owned entitlement sharing-unit id (e.g. a family/household id). Links this device to
    /// a `Subject` server-side so the org's subscription entitlement is projected into the JWT as
    /// `custom_claims.subscription`. Optional. The same value is used as the Apple StoreKit
    /// `appAccountToken` and the Stripe Checkout `client_reference_id`.
    let subjectId: String?
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
    /// Numeric risk score. `nil` on free tier; present on Pro and above.
    let riskScore: Int?
    /// Risk category: "trusted" (0-20), "suspicious" (21-75), "blocked" (76-100). All tiers.
    let riskCategory: String
    let deviceIntegrity: String
    let jailbreakDetected: Bool
    let attestationCount: Int
    let lastAttestationDate: String?
}

internal struct ErrorResponse: Codable {
    let reason: String
}

internal struct MADLimitResponse: Codable {
    let error: String
    let limit: Int
    let current: Int
}

/// Sent to `POST /api/v1/attestation/refresh` when the JWT has expired
/// and the key has already been attested.
internal struct AssertionRefreshRequest: Codable {
    let keyId: String
    let assertion: String      // base64-encoded CBOR assertion from DCAppAttestService
    let clientDataHash: String // base64-encoded SHA256(challenge.utf8)
    let challenge: String      // raw challenge string for server-side validation
    /// Optional sharing-unit id (see `AttestationRequest.subjectId`). When omitted the backend
    /// keeps the device's existing Subject link, so the subscription claim still rides the token.
    let subjectId: String?
}

internal struct AssertionRefreshResponse: Codable {
    let token: String
    let expiresAt: String
}