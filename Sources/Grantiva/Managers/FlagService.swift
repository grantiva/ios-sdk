import Foundation

/// Provides access to remotely-configured feature flags with optional real-time SSE updates.
///
/// Access via `grantiva.flags`:
/// ```swift
/// let flags = try await grantiva.flags.getFlags()
/// if flags["dark_mode"]?.boolValue == true { ... }
/// let limit = try await grantiva.flags.value(for: "upload_limit")?.intValue ?? 10
/// ```
///
/// ### Real-time Updates
///
/// Subscribe to live flag changes via ``setUpdateHandler(_:)``:
/// ```swift
/// await grantiva.flags.setUpdateHandler { flags in
///     DispatchQueue.main.async { self.applyFlags(flags) }
/// }
/// ```
/// Real-time streaming starts automatically after a successful attestation on Pro+ plans.
/// If the SSE endpoint is unavailable the SDK falls back silently to polling.
///
/// Flags are cached in-memory with a configurable TTL (default: 5 minutes).
/// Call ``refresh()`` to force a fresh fetch.
public actor FlagService {
    private let apiClient: FlagAPIClient
    private let identity: IdentityProvider

    /// Default environment used for flag evaluation.
    public var environment: FlagEnvironment

    /// Cache TTL in seconds. Defaults to 5 minutes.
    public var cacheTTL: TimeInterval = 300

    // In-memory cache
    private var cachedFlags: [String: FlagValue]?
    private var cacheExpiry: Date?

    // SSE streaming
    private var sseClient: FlagSSEClient?
    private var updateHandler: (@Sendable ([String: FlagValue]) -> Void)?

    internal init(apiClient: FlagAPIClient, identity: IdentityProvider, environment: FlagEnvironment = .production) {
        self.apiClient = apiClient
        self.identity = identity
        self.environment = environment
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

        let flags = try await apiClient.fetchFlags(environment: environment)
        cachedFlags = flags
        cacheExpiry = Date().addingTimeInterval(cacheTTL)
        return flags
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

    // MARK: - Real-time Update Handler

    /// Register a handler that is invoked whenever the SSE stream delivers a flag update.
    ///
    /// The handler is called off the main thread. Dispatch to the main queue inside
    /// the closure if you need to update UI:
    /// ```swift
    /// await grantiva.flags.setUpdateHandler { flags in
    ///     DispatchQueue.main.async { self.applyFlags(flags) }
    /// }
    /// ```
    ///
    /// Pass `nil` to remove the handler.
    public func setUpdateHandler(_ handler: (@Sendable ([String: FlagValue]) -> Void)?) {
        updateHandler = handler
    }

    // MARK: - SSE Streaming (internal)

    /// Start receiving real-time flag updates over SSE.
    ///
    /// Called by the `Grantiva` class after a successful attestation.
    /// Calling this again while already streaming is a no-op.
    internal func startStreaming(
        configuration: GrantivaConfiguration,
        teamId: String,
        tokenManager: TokenManager
    ) {
        guard sseClient == nil else { return }

        let client = FlagSSEClient(
            configuration: configuration,
            teamId: teamId,
            environment: environment,
            tokenManager: tokenManager
        )
        client.onFlagsUpdate = { [weak self] flags in
            guard let self else { return }
            Task { await self.handleSSEUpdate(flags) }
        }
        sseClient = client
        client.start()
        Logger.debug("[Grantiva] SSE flag streaming started")
    }

    /// Stop receiving real-time flag updates.
    ///
    /// Called on background transitions and when `clearStoredData()` is invoked.
    internal func stopStreaming() {
        sseClient?.stop()
        sseClient = nil
        Logger.debug("[Grantiva] SSE flag streaming stopped")
    }

    // MARK: - Private

    internal func handleSSEUpdate(_ flags: [String: FlagValue]) {
        // Update cache so getFlags() immediately reflects the live values
        cachedFlags = flags
        cacheExpiry = Date().addingTimeInterval(cacheTTL)
        updateHandler?(flags)
    }
}
