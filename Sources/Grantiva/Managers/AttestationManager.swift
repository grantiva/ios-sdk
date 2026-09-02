import Foundation
import DeviceCheck
import CryptoKit

internal final class AttestationManager {
    private static let dcErrorDomain = "com.apple.devicecheck.error"

    func generateAttestation(keyId: String, challenge: String) async throws -> Data {
        guard DCAppAttestService.shared.isSupported else {
            throw GrantivaError.attestationNotAvailable
        }
        
        let clientDataHash = createClientDataHash(challenge: challenge)
        
        do {
            let attestationObject = try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash)
            return attestationObject
        } catch {
            // DCError codes: 0 unknownSystemFailure, 1 featureUnsupported,
            // 2 invalidInput (in practice: keyId already attested, can't re-attest),
            // 3 invalidKey, 4 serverUnavailable.
            let nsError = error as NSError
            Logger.error("DCAppAttestService.attestKey failed: domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)")
            throw Self.mapAttestationError(nsError)
        }
    }

    func createClientDataHash(challenge: String) -> Data {
        // Apple expects just the challenge data hashed, not combined with bundle/team ID
        let challengeData = Data(challenge.utf8)
        let hash = SHA256.hash(data: challengeData)
        return Data(hash)
    }

    /// Maps a `DCAppAttestService.attestKey` failure to a `GrantivaError`.
    ///
    /// `invalidInput` (2) means the key was already attested and triggers the
    /// fresh-key retry in `Grantiva.performFullAttestation`. `serverUnavailable`
    /// (4) is Apple's attestation service being unreachable — transient, so it
    /// surfaces as `networkError` rather than a terminal validation failure.
    static func mapAttestationError(_ error: NSError) -> GrantivaError {
        guard error.domain == dcErrorDomain else { return .validationFailed }
        switch error.code {
        case 2: return .keyAlreadyAttested
        case 4: return .networkError(error)
        default: return .validationFailed
        }
    }

    /// Generates an App Attest assertion for token refresh.
    ///
    /// Called when the JWT has expired and the key has already been attested.
    /// Unlike `generateAttestation`, this can be called multiple times for the same key.
    ///
    /// - Parameters:
    ///   - keyId: The key ID previously returned by `getOrCreateKeyId()`
    ///   - challenge: The challenge string received from the server
    /// - Returns: Raw assertion data (CBOR-encoded)
    func generateAssertion(keyId: String, challenge: String) async throws -> Data {
        guard DCAppAttestService.shared.isSupported else {
            throw GrantivaError.attestationNotAvailable
        }

        let clientDataHash = createClientDataHash(challenge: challenge)

        do {
            let assertionObject = try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash)
            return assertionObject
        } catch {
            let nsError = error as NSError
            Logger.error("DCAppAttestService.generateAssertion failed: domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)")
            throw Self.mapAssertionError(nsError)
        }
    }

    /// Maps a `DCAppAttestService.generateAssertion` failure to a `GrantivaError`.
    ///
    /// DCErrorDomain codes 2 (invalidInput) and 3 (invalidKey) both mean the stored
    /// keyId references a key the Secure Enclave cannot use for assertions — the local
    /// "attested" state has drifted from reality (backup restore, device transfer,
    /// partially-completed prior attestation). These are recoverable by re-attesting
    /// with a fresh key, so they map to `assertionKeyInvalid` and trigger the
    /// self-heal path in `validateAttestation()`. Code 4 (serverUnavailable) is
    /// transient and surfaces as `networkError`; everything else stays
    /// `validationFailed`. Neither must trigger the self-heal, which would burn
    /// the key for nothing.
    static func mapAssertionError(_ error: NSError) -> GrantivaError {
        guard error.domain == dcErrorDomain else { return .validationFailed }
        switch error.code {
        case 2, 3: return .assertionKeyInvalid
        case 4: return .networkError(error)
        default: return .validationFailed
        }
    }
}
