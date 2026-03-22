import Foundation

public class Grantiva {
    private let apiClient: GrantivaAPIClient
    private let keyManager: KeyManager
    private let attestationManager: AttestationManager
    private let tokenManager: TokenManager
    private let heartbeatManager: HeartbeatManager
    private let teamId: String
    private let configuration: GrantivaConfiguration
    internal let identity: IdentityProvider

    /// Lazy-initialized feedback service for feature requests and support tickets.
    ///
    /// ```swift
    /// let features = try await grantiva.feedback.getFeatureRequests()
    /// try await grantiva.feedback.vote(for: feature.id)
    /// let ticket = try await grantiva.feedback.submitTicket(subject: "Help", body: "Details...")
    /// ```
    public private(set) lazy var feedback: FeedbackService = {
        let feedbackClient = FeedbackAPIClient(configuration: configuration, teamId: teamId)
        return FeedbackService(apiClient: feedbackClient, identity: identity)
    }()

    /// Lazy-initialized feature flag service for remote configuration.
    ///
    /// ```swift
    /// let flags = try await grantiva.flags.getFlags()
    /// if flags["dark_mode"]?.boolValue == true { enableDarkMode() }
    /// let limit = try await grantiva.flags.intValue(for: "upload_limit", default: 10)
    /// ```
    public private(set) lazy var flags: FlagService = {
        let flagClient = FlagAPIClient(configuration: configuration, teamId: teamId)
        let config = configuration
        let tokenMgr = tokenManager
        return FlagService(
            apiClient: flagClient,
            identity: identity,
            getRiskScore: {
                // If we're in API key mode (simulator), skip risk scoring
                if config.apiKey != nil {
                    return nil
                }
                // Use local risk score calculation
                return DeviceIntelligenceExtractor.calculateLocalRiskScore()
            },
            getAttestationStatus: {
                // If we're in API key mode (simulator), return unattested
                if config.apiKey != nil {
                    return "unattested"
                }
                // Check if we have a valid token
                guard let storedToken = tokenMgr.getStoredToken() else {
                    return "unattested"
                }
                if tokenMgr.isTokenExpired(storedToken.expiresAt) {
                    return "expired"
                }
                return "attested"
            }
        )
    }()

    /// - Parameters:
    ///   - teamId: Your Apple Team ID.
    ///   - apiKey: Optional API key for simulator / development use where App Attest is unavailable.
    ///            When provided, the SDK sends a Bearer token instead of Bundle ID + Team ID headers.
    public init(teamId: String, apiKey: String? = nil) {
        self.teamId = teamId
        let config = apiKey != nil
            ? GrantivaConfiguration(baseURL: GrantivaConfiguration.default.baseURL, apiKey: apiKey)
            : .default
        self.configuration = config
        self.identity = IdentityProvider()
        self.apiClient = GrantivaAPIClient(configuration: config, teamId: teamId)
        self.keyManager = KeyManager()
        self.attestationManager = AttestationManager(teamId: teamId)
        self.tokenManager = TokenManager()
        let isAPIKey = apiKey != nil
        self.heartbeatManager = HeartbeatManager(
            apiClient: HeartbeatAPIClient(configuration: config, teamId: teamId),
            getToken: { [tokenManager] in tokenManager.getStoredToken()?.token },
            getDeviceId: { isAPIKey ? PlatformSupport.getDeviceIdentifier() : nil }
        )
        #if targetEnvironment(simulator)
        Logger.warning("[Grantiva] ⚠️ Running in simulator — App Attest unavailable. Using API key fallback. riskScore will be nil. Test on a real device to verify full attestation.")
        #endif
    }

    /// Associate a user identity and context with this Grantiva instance.
    ///
    /// All services (feedback, support, flags, analytics) will use this context
    /// for scoping requests, targeting, and segmentation. Call after your app's login flow.
    ///
    /// Device info (model, OS, app version, etc.) is collected automatically.
    ///
    /// ```swift
    /// grantiva.identify(UserContext(
    ///     userId: "user_123",
    ///     properties: [
    ///         "plan": "premium",
    ///         "state": "TX",
    ///         "beta_tester": "true"
    ///     ]
    /// ))
    /// ```
    ///
    /// - Parameter context: The user context including identifier and custom properties.
    public func identify(_ context: UserContext) async {
        identity.identify(context)
        // Clear caches so queries re-fetch with the new identity
        await feedback.clearCache()
        await flags.clearCache()
    }

    /// Convenience: identify with just a user ID and no custom properties.
    ///
    /// ```swift
    /// grantiva.identify("user_123")
    /// ```
    ///
    /// - Parameter userId: A stable, unique identifier for the user in your system.
    public func identify(_ userId: String) async {
        await identify(UserContext(userId: userId))
    }

    /// Clear the current user identity.
    ///
    /// Services will fall back to device-based identity. Call this on logout.
    ///
    /// ```swift
    /// grantiva.clearIdentity()
    /// ```
    public func clearIdentity() async {
        identity.clearIdentity()
        await feedback.clearCache()
        await flags.clearCache()
    }

    /// The currently identified user ID, or `nil` if no user has been identified.
    public var currentUserId: String? {
        identity.userId
    }

    /// The full user context, or `nil` if no user has been identified.
    public var currentUserContext: UserContext? {
        identity.userContext
    }
    
    public func validateAttestation() async throws -> AttestationResult {
        Logger.info("Starting attestation validation...")
        #if targetEnvironment(simulator)
        Logger.warning("[Grantiva] ⚠️ Running in simulator — App Attest unavailable. Using API key fallback. riskScore will be nil. Test on a real device to verify full attestation.")
        #endif

        // When an API key is configured (e.g. simulator / dev builds), skip the
        // real App Attest flow entirely.  The API key already authenticates the
        // tenant on the backend, so device attestation is unnecessary.
        if configuration.apiKey != nil {
            Logger.info("API key mode — returning synthetic attestation result")
            let deviceIntelligence = DeviceIntelligence(
                deviceId: PlatformSupport.getDeviceIdentifier(),
                riskScore: nil,
                deviceIntegrity: "api_key_mode",
                jailbreakDetected: false,
                attestationCount: 0,
                lastAttestationDate: nil
            )
            heartbeatManager.start()
            return AttestationResult(
                isValid: true,
                token: "simulator-dev-token",
                expiresAt: Date().addingTimeInterval(60 * 60 * 24 * 365), // 1 year
                deviceIntelligence: deviceIntelligence
            )
        }

        try DeviceCompatibility.checkCompatibility()
        
        if let storedToken = tokenManager.getStoredToken() {
            if !tokenManager.isTokenExpired(storedToken.expiresAt) {
                Logger.debug("Using cached token")
                let deviceIntelligence = DeviceIntelligence(
                    deviceId: PlatformSupport.getDeviceIdentifier(),
                    riskScore: nil,
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
        
        Logger.info("Requesting challenge from server...")
        let challengeResponse = try await apiClient.requestChallenge()
        Logger.debug("Received challenge: \(challengeResponse.challenge)")

        Logger.info("Getting or creating key ID...")
        let keyId = try await keyManager.getOrCreateKeyId()
        Logger.debug("Key ID: \(keyId)")

        Logger.info("Generating attestation object...")
        let attestationObject = try await attestationManager.generateAttestation(keyId: keyId, challenge: challengeResponse.challenge)
        Logger.debug("Attestation object size: \(attestationObject.count) bytes")

        let clientDataHashData = attestationManager.createClientDataHash(challenge: challengeResponse.challenge)
        let clientDataHash = clientDataHashData.base64EncodedString()
        Logger.debug("Client data hash: \(clientDataHash)")
        
        let attestationRequest = AttestationRequest(
            bundleId: Bundle.main.bundleIdentifier ?? "",
            teamId: teamId,
            keyId: keyId,
            attestationObject: attestationObject.base64EncodedString(),
            clientDataHash: clientDataHash,
            challenge: challengeResponse.challenge,
            deviceModel: PlatformSupport.getHardwareModel(),
            osVersion: PlatformSupport.getOSVersion(),
            appVersion: PlatformSupport.getAppVersion(),
            appBuildNumber: PlatformSupport.getAppBuildNumber(),
            platform: {
                #if os(iOS)
                return "iOS"
                #elseif os(macOS)
                return "macOS"
                #else
                return nil
                #endif
            }()
        )
        
        Logger.debug("Sending attestation for bundle: \(attestationRequest.bundleId), team: \(attestationRequest.teamId)")

        let response = try await apiClient.validateAttestation(attestationRequest)
        Logger.info("Attestation validated: \(response.isValid)")
        
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
        
        Logger.info("Attestation completed successfully")
        heartbeatManager.start()
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
            riskScore: nil,
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
        Logger.info("Clearing stored attestation data...")
        keyManager.clearStoredKeyId()
        tokenManager.clearTokens()
        heartbeatManager.stop()
        Logger.info("Stored data cleared")
    }
    
}
