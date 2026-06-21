import Foundation

public enum GrantivaError: LocalizedError {
    case deviceNotSupported
    case attestationNotAvailable
    case networkError(Error)
    case validationFailed
    /// Server reported the device's stored attestation is no longer cryptographically
    /// valid (rpIdHash drift or signature mismatch). The SDK responds by clearing the
    /// cached keyId/attested flag and rerunning the full attestation flow once.
    case reattestRequired
    case tokenExpired
    case configurationError
    case keyGenerationFailed
    case challengeExpired
    case invalidResponse
    case rateLimited
    case feedbackNotAvailable
    case serverError(reason: String)
    /// The tenant's Monthly Active Devices limit has been reached.
    ///
    /// - Parameters:
    ///   - limit: The plan's MAD ceiling.
    ///   - current: The current month's MAD count that triggered the limit.
    case limitExceeded(limit: Int, current: Int)
    /// Thrown when `validateAttestation()` is called in the iOS Simulator without
    /// an API key. Initialize with `Grantiva(teamId:apiKey:)` for simulator builds.
    case simulatorAPIKeyRequired
    /// Apple rejected `DCAppAttestService.attestKey` with `DCError.invalidInput`
    /// (code 2). This typically means the keyId has already been attested in a
    /// prior session and cannot be re-attested — App Attest permits one attestation
    /// per key over its lifetime. The SDK self-heals by clearing the stored keyId
    /// and generating a fresh one once before bubbling this up.
    case keyAlreadyAttested
    /// Apple rejected `DCAppAttestService.generateAssertion` with `DCError.invalidInput`
    /// (code 2) or `DCError.invalidKey` (code 3). The stored keyId references a key the
    /// Secure Enclave can no longer use for assertions — classically after a backup
    /// restore/device transfer (the keychain keyId migrates, Secure Enclave keys never
    /// do), or when the local "attested" flag drifted from reality. The SDK self-heals
    /// by clearing the stored key state and running the full attestation flow once.
    case assertionKeyInvalid

    public var errorDescription: String? {
        switch self {
        case .deviceNotSupported:
            return "This device does not support App Attest functionality"
        case .attestationNotAvailable:
            return "App Attest is not available on this device"
        case .networkError(let error):
            return "Network error occurred: \(error.localizedDescription)"
        case .validationFailed:
            return "Attestation validation failed"
        case .reattestRequired:
            return "Stored device key state diverged from server — re-attestation required"
        case .tokenExpired:
            return "Authentication token has expired"
        case .configurationError:
            return "SDK configuration error"
        case .keyGenerationFailed:
            return "Failed to generate or retrieve attestation key"
        case .challengeExpired:
            return "Challenge has expired and needs to be refreshed"
        case .invalidResponse:
            return "Invalid response received from server"
        case .rateLimited:
            return "Too many requests. Please try again later"
        case .feedbackNotAvailable:
            return "Feedback service is not available for this tenant"
        case .serverError(let reason):
            return "Attestation failed: \(reason)"
        case .limitExceeded(let limit, let current):
            return "Monthly attestation limit reached (\(current)/\(limit) MAD). Upgrade at grantiva.io/upgrade."
        case .simulatorAPIKeyRequired:
            return "App Attest is unavailable in the iOS Simulator — pass an API key to Grantiva(teamId:apiKey:) for simulator builds"
        case .keyAlreadyAttested:
            return "Stored device key was already attested in a prior session — App Attest does not permit re-attesting the same key"
        case .assertionKeyInvalid:
            return "Stored device key can no longer generate assertions — re-attestation with a fresh key required"
        }
    }

    public var failureReason: String? {
        switch self {
        case .deviceNotSupported:
            return "App Attest requires iOS 14.0 or later and is not available in simulator"
        case .attestationNotAvailable:
            return "App Attest service is not supported on this device or region"
        case .networkError:
            return "Check your internet connection and try again"
        case .validationFailed:
            return "The device attestation could not be verified by the server"
        case .reattestRequired:
            return "Local key/keychain state is out of sync with the server's stored attestation"
        case .tokenExpired:
            return "The authentication token needs to be refreshed"
        case .configurationError:
            return "Invalid Bundle ID or Team ID configuration"
        case .keyGenerationFailed:
            return "Unable to create or access secure attestation key"
        case .challengeExpired:
            return "Server challenge has expired"
        case .invalidResponse:
            return "Server returned an unexpected response format"
        case .rateLimited:
            return "You have exceeded the rate limit for this action"
        case .feedbackNotAvailable:
            return "Your current plan may not include feedback features"
        case .serverError(let reason):
            return reason
        case .limitExceeded:
            return "Upgrade your Grantiva plan at grantiva.io/upgrade to increase your MAD limit"
        case .simulatorAPIKeyRequired:
            return "Create a development API key in the Grantiva dashboard (Dashboard → API Keys) and pass it to Grantiva(teamId:apiKey:). See https://docs.grantiva.io/simulator"
        case .keyAlreadyAttested:
            return "The keyId persisted from a previous install or session. The SDK clears it and generates a fresh one automatically; this error only surfaces if the second attestation attempt also fails."
        case .assertionKeyInvalid:
            return "The keyId in the keychain references a Secure Enclave key that is unusable for assertions (e.g. after a backup restore to a different device). The SDK clears the stored key state and re-attests automatically; this error only surfaces if that recovery also fails."
        }
    }
}