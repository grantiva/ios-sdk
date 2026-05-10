import Foundation
import DeviceCheck
import CryptoKit

internal class AttestationManager {
    private let keyManager = KeyManager()
    private let teamId: String
    
    init(teamId: String) {
        self.teamId = teamId
    }
    
    func generateAttestation(keyId: String, challenge: String) async throws -> Data {
        guard DCAppAttestService.shared.isSupported else {
            throw GrantivaError.attestationNotAvailable
        }
        
        let clientDataHash = createClientDataHash(challenge: challenge)
        
        do {
            let attestationObject = try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash)
            return attestationObject
        } catch {
            // Surface the underlying DCError. DCErrorDomain codes map to:
            //   2 = invalidInput, 3 = invalidKey, 4 = serverUnavailable,
            //   5 = featureUnsupported. Logging this is the only way to
            //   diagnose attestation failures without a debugger attached.
            let nsError = error as NSError
            Logger.error("DCAppAttestService.attestKey failed: domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)")
            throw GrantivaError.validationFailed
        }
    }

    func createClientDataHash(challenge: String) -> Data {
        // Apple expects just the challenge data hashed, not combined with bundle/team ID
        let challengeData = Data(challenge.utf8)
        let hash = SHA256.hash(data: challengeData)
        return Data(hash)
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
            throw GrantivaError.validationFailed
        }
    }

    func checkDeviceSupport() -> Bool {
        return DCAppAttestService.shared.isSupported
    }
}
