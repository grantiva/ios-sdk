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
            throw GrantivaError.validationFailed
        }
    }
    
    func createClientDataHash(challenge: String) -> Data {
        // Apple expects just the challenge data hashed, not combined with bundle/team ID
        let challengeData = Data(challenge.utf8)
        let hash = SHA256.hash(data: challengeData)
        return Data(hash)
    }
    
    
    func checkDeviceSupport() -> Bool {
        return DCAppAttestService.shared.isSupported
    }
}
