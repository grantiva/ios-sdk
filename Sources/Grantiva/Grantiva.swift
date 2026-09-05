import Foundation
#if os(iOS)
import UIKit
#endif

public class Grantiva {
    private let apiClient: GrantivaAPIClient
    private let keyManager: KeyManager
    private let attestationManager: AttestationManager
    private let tokenManager: TokenManager
    private let heartbeatManager: HeartbeatManager
    /// Lets the heartbeat and flag stream renew an expired token on their own.
    private let backgroundRefresher = BackgroundTokenRefresher()
    private let teamId: String
    private let configuration: GrantivaConfiguration
    internal let identity: IdentityProvider
    internal let pushTokens: PushTokenStore

    // Background/foreground lifecycle observers (iOS only)
    private var lifecycleObservers: [NSObjectProtocol] = []

    /// Lazy-initialized feedback service for feature requests and support tickets.
    ///
    /// ```swift
    /// let features = try await grantiva.feedback.getFeatureRequests()
    /// try await grantiva.feedback.vote(for: feature.id)
    /// let ticket = try await grantiva.feedback.submitTicket(subject: "Help", body: "Details...")
    /// ```
    public private(set) lazy var feedback: FeedbackService = {
        let feedbackClient = FeedbackAPIClient(
            configuration: configuration,
            teamId: teamId,
            getToken: { [tokenManager] in tokenManager.getStoredToken()?.token }
        )
        return FeedbackService(apiClient: feedbackClient, identity: identity, pushTokens: pushTokens)
    }()

    /// Lazy-initialized feature flag service for remote configuration.
    ///
    /// ```swift
    /// let flags = try await grantiva.flags.getFlags()
    /// if flags["dark_mode"]?.boolValue == true { enableDarkMode() }
    /// let limit = try await grantiva.flags.intValue(for: "upload_limit", default: 10)
    /// ```
    public private(set) lazy var flags: FlagService = {
        let flagClient = FlagAPIClient(
            configuration: configuration,
            teamId: teamId,
            getToken: { [tokenManager] in tokenManager.getStoredToken()?.token }
        )
        return FlagService(apiClient: flagClient, identity: identity)
    }()

    /// Lazy-initialized "What's New" service for version-targeted release notes.
    ///
    /// ```swift
    /// for note in try await grantiva.whatsNew.getReleaseNotes() {
    ///     show(note)
    ///     try await grantiva.whatsNew.markSeen(note.id)
    /// }
    /// ```
    ///
    /// Always returns an empty list in the iOS Simulator — see ``WhatsNewService``.
    public private(set) lazy var whatsNew: WhatsNewService = {
        let whatsNewClient = WhatsNewAPIClient(
            configuration: configuration,
            teamId: teamId,
            getToken: { [tokenManager] in tokenManager.getStoredToken()?.token }
        )
        return WhatsNewService(apiClient: whatsNewClient)
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
        self.pushTokens = PushTokenStore()
        self.apiClient = GrantivaAPIClient(configuration: config, teamId: teamId)
        self.keyManager = KeyManager()
        self.attestationManager = AttestationManager(teamId: teamId)
        self.tokenManager = TokenManager()
        let isAPIKey = apiKey != nil
        // In API key mode there is no JWT to renew: the key itself authenticates,
        // so background clients get no refresh hook and fall back to the key.
        let refresher = backgroundRefresher
        let refreshToken: (@Sendable () async -> Bool)? = isAPIKey
            ? nil
            : { @Sendable in await refresher.refresh() }
        self.backgroundRefreshToken = refreshToken
        self.heartbeatManager = HeartbeatManager(
            apiClient: HeartbeatAPIClient(configuration: config, teamId: teamId),
            getToken: { [tokenManager] in tokenManager.getValidToken() },
            getDeviceId: { isAPIKey ? PlatformSupport.getDeviceIdentifier() : nil },
            refreshToken: refreshToken
        )
        #if targetEnvironment(simulator)
        if apiKey == nil {
            // No-apiKey simulator builds will throw `simulatorAPIKeyRequired` from
            // validateAttestation(); warn at init so the developer sees the actionable
            // setup link before they hit the runtime error.
            Logger.warning(
                "Running on iOS Simulator — App Attest is unavailable. " +
                "Call Grantiva(teamId:apiKey:) with a development API key to authenticate " +
                "simulator builds. Get your key at: Dashboard → API Keys. " +
                "See https://docs.grantiva.io/simulator for setup instructions."
            )
        } else {
            // apiKey-mode simulator builds work, but `riskScore` will be nil because
            // there is no attestation. Worth saying so once at init.
            Logger.warning("[Grantiva] Running in simulator with API key fallback. riskScore will be nil. Test on a real device for full attestation.")
        }
        #endif

        registerLifecycleObservers()
        backgroundRefresher.owner = self
    }

    deinit {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
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

    /// Associate this device with an entitlement **sharing unit** (e.g. a family/household).
    ///
    /// Grantiva attaches subscription entitlements to a sharing unit, so one paying member can
    /// entitle every device in the unit. Call this (before `validateAttestation()`) on **every**
    /// member's device with the same id, so the resulting JWT carries `custom_claims.subscription`.
    ///
    /// The id is opaque and stable. Use the **same value** as:
    /// - the Apple StoreKit `appAccountToken` at purchase, and
    /// - the Stripe Checkout `client_reference_id`.
    ///
    /// Apple requires `appAccountToken` to be a `UUID`, so use a UUID string here too.
    ///
    /// Distinct from `identify(_:)`, which sets the individual user for feedback/flags scoping.
    ///
    /// ```swift
    /// grantiva.setSubjectId(familyId.uuidString)
    /// ```
    ///
    /// - Parameter subjectId: A stable, opaque sharing-unit identifier (UUID string recommended).
    public func setSubjectId(_ subjectId: String) {
        identity.setSubjectId(subjectId)
    }

    /// Clear the entitlement sharing-unit association (e.g. on leaving the family / sign-out).
    public func clearSubjectId() {
        identity.setSubjectId(nil)
    }

    /// The current entitlement sharing-unit id, or `nil` if unset.
    public var subjectId: String? {
        identity.subjectId
    }

    // MARK: - Push Notifications

    /// Register the device's APNs push token with the SDK.
    ///
    /// Apple delivers the token to your `UIApplicationDelegate`'s
    /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` — forward
    /// the raw `Data` here. Once set, the token is attached to feedback submissions and
    /// comments so the backend subscribes this device to those threads and pushes it
    /// when an admin replies. (Requires the org to have a linked push app; otherwise
    /// it's silently ignored server-side.)
    ///
    /// ```swift
    /// func application(_ app: UIApplication,
    ///                  didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    ///     grantiva.setPushToken(deviceToken)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - deviceToken: The raw token `Data` from `didRegisterForRemoteNotificationsWithDeviceToken`.
    ///   - environment: The APNs environment the token belongs to. Defaults to
    ///     `PushEnvironment.detected`, which reads the provisioning profile and falls
    ///     back to the build configuration. Pass an explicit value if your pipeline
    ///     doesn't fit those heuristics.
    public func setPushToken(_ deviceToken: Data, environment: PushEnvironment = .detected) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        setPushToken(hex, environment: environment)
    }

    /// Register an already hex-encoded APNs push token.
    ///
    /// Prefer the `Data` overload with the raw token from Apple; use this only if you've
    /// already converted the token to a hex string.
    ///
    /// - Parameters:
    ///   - hexToken: The lowercase hex-encoded device token.
    ///   - environment: The APNs environment the token belongs to. Defaults to `.detected`.
    public func setPushToken(_ hexToken: String, environment: PushEnvironment = .detected) {
        let normalized = hexToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            Logger.warning("setPushToken called with an empty token — ignoring")
            return
        }
        pushTokens.set(token: normalized, environment: environment)
        Logger.info("Registered APNs push token (\(environment.rawValue))")
    }

    /// The currently registered hex-encoded APNs push token, or `nil` if none is set.
    public var pushToken: String? {
        pushTokens.token
    }

    /// Clear the registered push token.
    ///
    /// Call this when the app unregisters for remote notifications or the user opts out.
    /// Subsequent feedback submissions and comments will no longer subscribe the device
    /// to threads.
    public func clearPushToken() {
        pushTokens.clear()
        Logger.info("Cleared APNs push token")
    }

    public func validateAttestation() async throws -> AttestationResult {
        try await validateAttestation(forceRefresh: false)
    }

    internal func validateAttestation(forceRefresh: Bool) async throws -> AttestationResult {
        Logger.info("Starting attestation validation...")

        #if targetEnvironment(simulator)
        // App Attest is unavailable in the simulator. Without an API key fallback,
        // throw a targeted error rather than letting DeviceCompatibility surface a
        // generic `deviceNotSupported`. Init has already logged the setup link.
        guard configuration.apiKey != nil else {
            Logger.error("validateAttestation() called on iOS Simulator without an API key. Initialize with Grantiva(teamId:apiKey:) for simulator builds. See https://docs.grantiva.io/simulator")
            throw GrantivaError.simulatorAPIKeyRequired
        }
        #endif

        // When an API key is configured (e.g. simulator / dev builds), skip the
        // real App Attest flow entirely.  The API key already authenticates the
        // tenant on the backend, so device attestation is unnecessary.
        if configuration.apiKey != nil {
            Logger.info("API key mode — returning synthetic attestation result")
            let deviceIntelligence = DeviceIntelligence(
                deviceId: PlatformSupport.getDeviceIdentifier(),
                riskScore: nil,
                riskCategory: .trusted,
                deviceIntegrity: "api_key_mode",
                jailbreakDetected: false,
                attestationCount: 0,
                lastAttestationDate: nil
            )
            heartbeatManager.start()
            await startFlagStreaming()
            return AttestationResult(
                isValid: true,
                token: "simulator-dev-token",
                expiresAt: Date().addingTimeInterval(60 * 60 * 24 * 365), // 1 year
                deviceIntelligence: deviceIntelligence
            )
        }

        #if targetEnvironment(simulator)
        // Simulator path without an API key — give a clear, actionable error instead
        // of letting DeviceCompatibility throw a generic deviceNotSupported.
        Logger.error(
            "validateAttestation() called on iOS Simulator without an API key. " +
            "Initialize with Grantiva(teamId:apiKey:) for simulator builds. " +
            "See https://docs.grantiva.io/simulator"
        )
        throw GrantivaError.simulatorAPIKeyRequired
        #endif

        try DeviceCompatibility.checkCompatibility()
        
        if !forceRefresh, let storedToken = tokenManager.getStoredToken() {
            if !tokenManager.isTokenExpired(storedToken.expiresAt) {
                Logger.debug("Using cached token")
                let deviceIntelligence = tokenManager.getStoredDeviceIntelligence() ?? DeviceIntelligence(
                    deviceId: PlatformSupport.getDeviceIdentifier(),
                    riskScore: nil,
                    riskCategory: .trusted,
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

        // If the key has already been attested, use the assertion path for refresh.
        // Re-calling attestKey with the same key is rejected by the backend's replay protection.
        if keyManager.hasBeenAttested(), let existingKeyId = keyManager.getStoredKeyId() {
            Logger.info("Key already attested — using assertion path for token refresh")
            do {
                return try await refreshViaAssertion(
                    keyId: existingKeyId,
                    challenge: challengeResponse.challenge
                )
            } catch GrantivaError.reattestRequired, GrantivaError.assertionKeyInvalid {
                // Two triggers, same recovery:
                // - reattestRequired: server invalidated the stored attestation row
                //   (rpIdHash drift or signature mismatch).
                // - assertionKeyInvalid: Apple rejected generateAssertion locally
                //   (DCError 2/3) — the stored keyId no longer maps to a usable
                //   Secure Enclave key (backup restore, state drift).
                // Drop local key state and fall through to the full attest path below.
                // Request a fresh challenge — the previous one was consumed by the
                // failed refresh. Also clear the keyId so a fresh one is generated;
                // App Attest does not permit re-attesting the same key.
                Logger.warning("Stored key unusable for assertion refresh — clearing local key state and re-attesting")
                keyManager.clearStoredKeyId()
                tokenManager.clearTokens()
                let freshChallenge = try await apiClient.requestChallenge()
                return try await performFullAttestation(challenge: freshChallenge.challenge)
            }
        }

        return try await performFullAttestation(challenge: challengeResponse.challenge)
    }

    /// Runs the App Attest generateKey → attest → /validate flow against the supplied
    /// (single-use) challenge. Extracted so the assertion-refresh self-heal path can
    /// re-enter the attest flow with a fresh challenge after the server reports
    /// `reattestRequired`.
    ///
    /// If Apple rejects `attestKey` with `keyAlreadyAttested` (DCError 2), drop the
    /// stored keyId and retry once with a fresh one. This handles the case where
    /// the keyId persisted across an event that cleared the "attested" flag (e.g.,
    /// a partial keychain wipe, or earlier SDK versions that only cleared the flag).
    /// Limited to one retry to prevent infinite loops on persistent Apple errors.
    private func performFullAttestation(challenge: String) async throws -> AttestationResult {
        do {
            return try await attemptFullAttestation(challenge: challenge)
        } catch GrantivaError.keyAlreadyAttested {
            Logger.warning("Apple reported keyAlreadyAttested — clearing stored keyId and retrying with a fresh key")
            keyManager.clearStoredKeyId()
            let freshChallenge = try await apiClient.requestChallenge()
            return try await attemptFullAttestation(challenge: freshChallenge.challenge)
        }
    }

    private func attemptFullAttestation(challenge: String) async throws -> AttestationResult {
        Logger.info("Getting or creating key ID...")
        let keyId = try await keyManager.getOrCreateKeyId()
        Logger.debug("Key ID: \(keyId)")

        Logger.info("Generating attestation object...")
        let attestationObject = try await attestationManager.generateAttestation(keyId: keyId, challenge: challenge)
        Logger.debug("Attestation object size: \(attestationObject.count) bytes")

        let clientDataHashData = attestationManager.createClientDataHash(challenge: challenge)
        let clientDataHash = clientDataHashData.base64EncodedString()
        Logger.debug("Client data hash: \(clientDataHash)")

        let attestationRequest = AttestationRequest(
            bundleId: Bundle.main.bundleIdentifier ?? "",
            teamId: teamId,
            keyId: keyId,
            attestationObject: attestationObject.base64EncodedString(),
            clientDataHash: clientDataHash,
            challenge: challenge,
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
            }(),
            deviceFingerprint: PlatformSupport.getDeviceFingerprint(),
            subjectId: identity.subjectId
        )

        Logger.debug("Sending attestation for bundle: \(attestationRequest.bundleId), team: \(attestationRequest.teamId)")

        let response = try await apiClient.validateAttestation(attestationRequest)
        Logger.info("Attestation validated: \(response.isValid)")

        let dateFormatter = ISO8601DateFormatter()
        guard let expiresAt = dateFormatter.date(from: response.expiresAt) else {
            throw GrantivaError.invalidResponse
        }

        tokenManager.saveToken(response.token, expiresAt: expiresAt)
        keyManager.markAsAttested()

        let riskCategory = RiskCategory(rawValue: response.deviceIntelligence.riskCategory) ?? .trusted
        let deviceIntelligence = DeviceIntelligence(
            deviceId: response.deviceIntelligence.deviceId,
            riskScore: response.deviceIntelligence.riskScore,
            riskCategory: riskCategory,
            deviceIntegrity: response.deviceIntelligence.deviceIntegrity,
            jailbreakDetected: response.deviceIntelligence.jailbreakDetected,
            attestationCount: response.deviceIntelligence.attestationCount,
            lastAttestationDate: response.deviceIntelligence.lastAttestationDate != nil ? dateFormatter.date(from: response.deviceIntelligence.lastAttestationDate!) : nil
        )
        tokenManager.saveDeviceIntelligence(deviceIntelligence)

        let customClaims = response.customClaims

        Logger.info("Attestation completed successfully")
        heartbeatManager.start()
        await startFlagStreaming()
        return AttestationResult(
            isValid: response.isValid,
            token: response.token,
            expiresAt: expiresAt,
            deviceIntelligence: deviceIntelligence,
            customClaims: customClaims
        )
    }
    
    /// Refreshes the JWT using an App Attest assertion (for already-attested keys).
    private func refreshViaAssertion(keyId: String, challenge: String) async throws -> AttestationResult {
        let assertionData = try await attestationManager.generateAssertion(keyId: keyId, challenge: challenge)
        let clientDataHashData = attestationManager.createClientDataHash(challenge: challenge)

        let refreshRequest = AssertionRefreshRequest(
            keyId: keyId,
            assertion: assertionData.base64EncodedString(),
            clientDataHash: clientDataHashData.base64EncodedString(),
            challenge: challenge,
            subjectId: identity.subjectId
        )

        let response = try await apiClient.refreshWithAssertion(refreshRequest)

        let dateFormatter = ISO8601DateFormatter()
        guard let expiresAt = dateFormatter.date(from: response.expiresAt) else {
            throw GrantivaError.invalidResponse
        }

        tokenManager.saveToken(response.token, expiresAt: expiresAt)
        Logger.info("Token refreshed via assertion")

        let deviceIntelligence = tokenManager.getStoredDeviceIntelligence() ?? DeviceIntelligence(
            deviceId: PlatformSupport.getDeviceIdentifier(),
            riskScore: nil,
            riskCategory: .trusted,
            deviceIntegrity: "asserted",
            jailbreakDetected: false,
            attestationCount: 0,
            lastAttestationDate: nil
        )

        heartbeatManager.start()
        return AttestationResult(
            isValid: true,
            token: response.token,
            expiresAt: expiresAt,
            deviceIntelligence: deviceIntelligence
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
            riskCategory: .trusted,
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
    
    /// Clears stored attestation data for testing purposes.
    ///
    /// This stops all background services (heartbeats, SSE stream) and forces a fresh
    /// attestation on the next `validateAttestation()` call.
    public func clearStoredData() {
        Logger.info("Clearing stored attestation data...")
        keyManager.clearStoredKeyId()
        tokenManager.clearTokens()
        heartbeatManager.stop()
        let flagService = flags
        Task { await flagService.stopStreaming() }
        Logger.info("Stored data cleared")
    }

    // MARK: - Flag Streaming Helpers

    /// Refresh hook handed to background clients; `nil` in API key mode.
    private let backgroundRefreshToken: (@Sendable () async -> Bool)?

    /// Start SSE flag streaming. The stream reads the current non-expired JWT on every
    /// (re)connect and can renew it through `backgroundRefreshToken` when it has expired.
    private func startFlagStreaming() async {
        await flags.startStreaming(
            configuration: configuration,
            teamId: teamId,
            getToken: { [tokenManager] in tokenManager.getValidToken() },
            refreshToken: backgroundRefreshToken
        )
    }

    // MARK: - App Lifecycle

    /// Registers for app background/foreground notifications to pause and resume SSE streaming.
    private func registerLifecycleObservers() {
        #if os(iOS)
        let background = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            let flagService = self.flags
            Task { await flagService.stopStreaming() }
        }

        let foreground = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            let flagService = self.flags
            let configuration = self.configuration
            let teamId = self.teamId
            let tokenManager = self.tokenManager
            let refreshToken = self.backgroundRefreshToken
            Task {
                await flagService.startStreaming(
                    configuration: configuration,
                    teamId: teamId,
                    getToken: { tokenManager.getValidToken() },
                    refreshToken: refreshToken
                )
            }
        }

        lifecycleObservers = [background, foreground]
        #endif
    }
}
