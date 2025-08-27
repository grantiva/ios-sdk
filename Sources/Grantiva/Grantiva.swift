import Foundation

public class Grantiva {
    private let apiClient: GrantivaAPIClient
    private let keyManager: KeyManager
    private let attestationManager: AttestationManager
    private let tokenManager: TokenManager
    private let teamId: String
    
    public init(teamId: String) {
        self.teamId = teamId
        self.apiClient = GrantivaAPIClient(configuration: .default, teamId: teamId)
        self.keyManager = KeyManager()
        self.attestationManager = AttestationManager(teamId: teamId)
        self.tokenManager = TokenManager()
    }
    
    public func validateAttestation() async throws -> AttestationResult {
        print("[Grantiva] Starting attestation validation...")
        try DeviceCompatibility.checkCompatibility()
        
        if let storedToken = tokenManager.getStoredToken() {
            if !tokenManager.isTokenExpired(storedToken.expiresAt) {
                print("[Grantiva] Using cached token")
                let deviceIntelligence = DeviceIntelligence(
                    deviceId: PlatformSupport.getDeviceIdentifier(),
                    riskScore: 0,
                    deviceIntegrity: "cached",
                    jailbreakDetected: false,
                    attestationCount: 0,
                    lastAttestationDate: nil
                )
                
                return AttestationResult(
                    isValid: true,
                    token: storedToken.token,
                    expiresAt: storedToken.expiresAt,
                    deviceIntelligence: deviceIntelligence
                )
            }
        }
        
        print("[Grantiva] Requesting challenge from server...")
        let challengeResponse = try await apiClient.requestChallenge()
        print("[Grantiva] Received challenge: \(challengeResponse.challenge)")
        
        print("[Grantiva] Getting or creating key ID...")
        let keyId = try await keyManager.getOrCreateKeyId()
        print("[Grantiva] Key ID: \(keyId)")
        
        print("[Grantiva] Generating attestation object...")
        let attestationObject = try await attestationManager.generateAttestation(keyId: keyId, challenge: challengeResponse.challenge)
        print("[Grantiva] Attestation object size: \(attestationObject.count) bytes")
        
        let clientDataHashData = attestationManager.createClientDataHash(challenge: challengeResponse.challenge)
        let clientDataHash = clientDataHashData.base64EncodedString()
        print("[Grantiva] Client data hash (hex): \(clientDataHashData.map { String(format: "%02x", $0) }.joined())")
        print("[Grantiva] Client data hash (base64): \(clientDataHash)")
        
        let attestationRequest = AttestationRequest(
            bundleId: Bundle.main.bundleIdentifier ?? "",
            teamId: teamId,
            keyId: keyId,
            attestationObject: attestationObject.base64EncodedString(),
            clientDataHash: clientDataHash,
            challenge: challengeResponse.challenge
        )
        
        print("[Grantiva] Sending attestation request:")
        print("[Grantiva]   Bundle ID: \(attestationRequest.bundleId)")
        print("[Grantiva]   Team ID: \(attestationRequest.teamId)")
        print("[Grantiva]   Key ID: \(attestationRequest.keyId)")
        print("[Grantiva]   Challenge: \(attestationRequest.challenge)")
        print("[Grantiva]   Attestation object (first 100 chars): \(attestationRequest.attestationObject.prefix(100))...")
        
        let response = try await apiClient.validateAttestation(attestationRequest)
        print("[Grantiva] Attestation validation response received")
        print("[Grantiva]   Is valid: \(response.isValid)")
        print("[Grantiva]   Token (first 50 chars): \(response.token.prefix(50))...")
        
        let dateFormatter = ISO8601DateFormatter()
        guard let expiresAt = dateFormatter.date(from: response.expiresAt) else {
            throw GrantivaError.invalidResponse
        }
        
        tokenManager.saveToken(response.token, expiresAt: expiresAt)
        
        let deviceIntelligence = DeviceIntelligence(
            deviceId: response.deviceIntelligence.deviceId,
            riskScore: response.deviceIntelligence.riskScore,
            deviceIntegrity: response.deviceIntelligence.deviceIntegrity,
            jailbreakDetected: response.deviceIntelligence.jailbreakDetected,
            attestationCount: response.deviceIntelligence.attestationCount,
            lastAttestationDate: response.deviceIntelligence.lastAttestationDate != nil ? dateFormatter.date(from: response.deviceIntelligence.lastAttestationDate!) : nil
        )
        
        let customClaims = response.customClaims
        
        print("[Grantiva] Attestation validation completed successfully!")
        return AttestationResult(
            isValid: response.isValid,
            token: response.token,
            expiresAt: expiresAt,
            deviceIntelligence: deviceIntelligence,
            customClaims: customClaims
        )
    }
    
    public func refreshToken() async throws -> AttestationResult? {
        guard let storedToken = tokenManager.getStoredToken() else {
            return nil
        }
        
        if tokenManager.isTokenExpired(storedToken.expiresAt) {
            return try await validateAttestation()
        }
        
        let deviceIntelligence = DeviceIntelligence(
            deviceId: PlatformSupport.getDeviceIdentifier(),
            riskScore: 0,
            deviceIntegrity: "valid",
            jailbreakDetected: false,
            attestationCount: 0,
            lastAttestationDate: nil
        )
        
        return AttestationResult(
            isValid: true,
            token: storedToken.token,
            expiresAt: storedToken.expiresAt,
            deviceIntelligence: deviceIntelligence
        )
    }
    
    public func getCurrentToken() -> String? {
        guard let storedToken = tokenManager.getStoredToken() else {
            return nil
        }
        
        if tokenManager.isTokenExpired(storedToken.expiresAt) {
            return nil
        }
        
        return storedToken.token
    }
    
    public func isTokenValid() -> Bool {
        guard let storedToken = tokenManager.getStoredToken() else {
            return false
        }
        
        return !tokenManager.isTokenExpired(storedToken.expiresAt)
    }
    
    /// Clears stored attestation data for testing purposes
    /// This will force generation of a new key on next attestation
    public func clearStoredData() {
        print("[Grantiva] Clearing stored attestation data...")
        keyManager.clearStoredKeyId()
        tokenManager.clearTokens()
        print("[Grantiva] Stored data cleared")
    }
    
}
