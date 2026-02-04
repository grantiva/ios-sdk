import Foundation

public enum GrantivaError: LocalizedError {
    case deviceNotSupported
    case attestationNotAvailable
    case networkError(Error)
    case validationFailed
    case tokenExpired
    case configurationError
    case keyGenerationFailed
    case challengeExpired
    case invalidResponse
    case rateLimited
    case feedbackNotAvailable

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
        }
    }
}