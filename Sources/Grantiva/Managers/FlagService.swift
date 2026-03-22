import Foundation

/// Provides access to remotely-configured feature flags.
///
/// Access via `grantiva.flags`:
/// ```swift
/// let flags = try await grantiva.flags.getFlags()
/// if flags["dark_mode"]?.boolValue == true { ... }
/// let limit = try await grantiva.flags.value(for: "upload_limit")?.intValue ?? 10
/// ```
///
/// Flags are cached in-memory with a configurable TTL (default: 5 minutes).
/// Call ``refresh()`` to force a fresh fetch.
public actor FlagService {
    private let apiClient: FlagAPIClient
    private let identity: IdentityProvider
    private let getRiskScore: @Sendable () -> Int?
    private let getAttestationStatus: @Sendable () -> String?

    /// Default environment used for flag evaluation.
    public var environment: FlagEnvironment

    /// Cache TTL in seconds. Defaults to 5 minutes.
    public var cacheTTL: TimeInterval = 300

    // In-memory cache
    private var cachedFlags: [String: FlagValue]?
    private var cacheExpiry: Date?

    internal init(
        apiClient: FlagAPIClient,
        identity: IdentityProvider,
        environment: FlagEnvironment = .production,
        getRiskScore: @escaping @Sendable () -> Int? = { nil },
        getAttestationStatus: @escaping @Sendable () -> String? = { nil }
    ) {
        self.apiClient = apiClient
        self.identity = identity
        self.environment = environment
        self.getRiskScore = getRiskScore
        self.getAttestationStatus = getAttestationStatus
    }

    // MARK: - Public API

    /// Fetch all feature flags for the current environment.
    ///
    /// Returns cached values if available and not expired.
    /// - Parameter forceRefresh: Pass `true` to bypass the cache.
    /// - Returns: A dictionary mapping flag keys to their resolved values.
    public func getFlags(forceRefresh: Bool = false) async throws -> [String: FlagValue] {
        if !forceRefresh, let cached = cachedFlags, let expiry = cacheExpiry, Date() < expiry {
            return cached
        }

        let deviceContext = buildDeviceContext()
        let flags = try await apiClient.fetchFlags(environment: environment, deviceContext: deviceContext)
        cachedFlags = flags
        cacheExpiry = Date().addingTimeInterval(cacheTTL)
        return flags
    }

    // MARK: - Device Context

    /// Build device context headers for targeting rules.
    private func buildDeviceContext() -> DeviceContextHeaders {
        // Collect locale and country
        let locale = Locale.current
        let localeIdentifier = locale.identifier // e.g. "en_US"
        let country = locale.region?.identifier // e.g. "US"

        // Custom properties from user context
        let customProps = identity.userContext?.properties ?? [:]

        return DeviceContextHeaders(
            deviceModel: PlatformSupport.getHardwareModel(),
            osVersion: PlatformSupport.getOSVersion(),
            appVersion: PlatformSupport.getAppVersion(),
            deviceId: PlatformSupport.getDeviceIdentifier(),
            riskScore: getRiskScore(),
            locale: localeIdentifier,
            country: country,
            userId: identity.userId,
            attestationStatus: getAttestationStatus(),
            customProperties: customProps
        )
    }

    /// Get a single flag value by key.
    ///
    /// - Parameter key: The flag key (e.g. `"dark_mode"`).
    /// - Returns: The resolved `FlagValue`, or `nil` if the flag doesn't exist.
    public func value(for key: String) async throws -> FlagValue? {
        let flags = try await getFlags()
        return flags[key]
    }

    /// Convenience: get a boolean flag, returning a default if not found or not a boolean.
    ///
    /// ```swift
    /// let darkMode = try await grantiva.flags.boolValue(for: "dark_mode", default: false)
    /// ```
    public func boolValue(for key: String, default defaultValue: Bool = false) async throws -> Bool {
        try await value(for: key)?.boolValue ?? defaultValue
    }

    /// Convenience: get a string flag, returning a default if not found.
    public func stringValue(for key: String, default defaultValue: String = "") async throws -> String {
        try await value(for: key)?.stringValue ?? defaultValue
    }

    /// Convenience: get an integer flag, returning a default if not found.
    public func intValue(for key: String, default defaultValue: Int = 0) async throws -> Int {
        try await value(for: key)?.intValue ?? defaultValue
    }

    /// Convenience: get a double flag, returning a default if not found.
    public func doubleValue(for key: String, default defaultValue: Double = 0.0) async throws -> Double {
        try await value(for: key)?.doubleValue ?? defaultValue
    }

    /// Force refresh the flag cache on the next fetch.
    public func refresh() {
        cachedFlags = nil
        cacheExpiry = nil
    }

    /// Clear all cached flag data. Called internally when identity changes.
    public func clearCache() {
        cachedFlags = nil
        cacheExpiry = nil
    }
}
