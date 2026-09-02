import Foundation

/// Manages a persistent Server-Sent Events (SSE) connection to the Grantiva flag stream endpoint.
///
/// On each received `flags` event the parsed flag dictionary is delivered to the
/// `onFlagsUpdate` closure. The client reconnects automatically with exponential
/// backoff whenever the connection drops.
internal final class FlagSSEClient: @unchecked Sendable {

    // MARK: - Types

    typealias FlagsUpdate = [String: FlagValue]

    // MARK: - Properties

    private let configuration: GrantivaConfiguration
    private let teamId: String
    private let environment: FlagEnvironment
    /// Returns the current non-expired JWT, or `nil` when there is none.
    private let getToken: @Sendable () -> String?
    /// Refreshes the JWT through the SDK's attestation path. `nil` in API key mode.
    private let refreshToken: (@Sendable () async -> Bool)?
    /// Test seam: `URLProtocol` subclasses installed on the streaming session.
    private let protocolClasses: [AnyClass]?

    /// Invoked on every successfully parsed `flags` SSE event.
    var onFlagsUpdate: ((FlagsUpdate) -> Void)?

    private var streamTask: Task<Void, Never>?
    private let lock = NSLock()
    private var _isRunning = false

    // Exponential backoff
    private let minBackoff: TimeInterval = 1.0
    private let maxBackoff: TimeInterval = 30.0

    /// A connection that survived at least this long before dropping counts as
    /// "healthy" — its failure resets the backoff to `minBackoff` instead of
    /// continuing to grow it. Without this, a device on flaky wifi creeps to a
    /// permanent `maxBackoff` reconnect delay even when connections last hours
    /// between drops.
    static let healthyConnectionThreshold: TimeInterval = 60

    /// Idle timeout for the stream. This is `timeoutIntervalForRequest`, which
    /// fires whenever no bytes arrive for this long — NOT a connect timeout.
    /// The backend sends a `: keepalive` comment every ~20s, so 75s of silence
    /// (~3 missed keepalives) genuinely means a dead connection and we *want*
    /// the timeout to fire and trigger a reconnect. Must comfortably exceed the
    /// server keepalive interval or the stream churns on every quiet period.
    static let idleTimeout: TimeInterval = 75

    /// Delay before retrying after the token could not be refreshed (or the server
    /// rejected it and no refresh is possible). This is not a transient transport
    /// failure, so it does not use the reconnect backoff: a device whose token
    /// cannot be renewed should try again occasionally, not every few seconds.
    static let authRetryDelay: TimeInterval = 300

    /// Outcomes of the auth handshake that the run loop schedules differently from
    /// ordinary transport failures.
    private enum AuthEvent: Error {
        /// A 401 was answered by a successful refresh; reconnect promptly.
        case tokenRefreshed
        /// No usable token and no way to get one right now.
        case tokenUnavailable
    }

    // MARK: - Init

    init(
        configuration: GrantivaConfiguration,
        teamId: String,
        environment: FlagEnvironment,
        getToken: @escaping @Sendable () -> String?,
        refreshToken: (@Sendable () async -> Bool)? = nil,
        protocolClasses: [AnyClass]? = nil
    ) {
        self.configuration = configuration
        self.teamId = teamId
        self.environment = environment
        self.getToken = getToken
        self.refreshToken = refreshToken
        self.protocolClasses = protocolClasses
    }

    // MARK: - Lifecycle

    /// Start the SSE connection. No-op if already running.
    func start() {
        lock.withLock {
            guard !_isRunning else { return }
            _isRunning = true
        }

        streamTask = Task { [weak self] in
            guard let self else { return }
            await self.runLoop()
        }
    }

    /// Stop the SSE connection and cancel any pending reconnect.
    func stop() {
        lock.withLock { _isRunning = false }
        streamTask?.cancel()
        streamTask = nil
    }

    // MARK: - Run Loop

    private func runLoop() async {
        var backoff = minBackoff

        while !Task.isCancelled {
            guard lock.withLock({ _isRunning }) else { return }

            let connectedAt = ContinuousClock.now
            var delay = backoff
            do {
                try await connect()
                // Clean disconnect — reset backoff and reconnect immediately
                backoff = minBackoff
                delay = backoff
                Logger.debug("[Grantiva] SSE stream closed cleanly. Reconnecting…")
            } catch is CancellationError {
                return
            } catch AuthEvent.tokenRefreshed {
                backoff = minBackoff
                delay = backoff
                Logger.debug("[Grantiva] SSE token refreshed after 401. Reconnecting…")
            } catch AuthEvent.tokenUnavailable {
                delay = Self.authRetryDelay
                Logger.debug("[Grantiva] SSE has no usable token. Retrying in \(Int(delay))s")
            } catch {
                // A long-lived connection that eventually dropped is not a sign of
                // a failing endpoint — start the backoff over instead of compounding
                // delays from failures that happened hours apart.
                if connectedAt.duration(to: .now) > .seconds(Self.healthyConnectionThreshold) {
                    backoff = minBackoff
                }
                delay = backoff
                backoff = min(backoff * 2, maxBackoff)
                Logger.debug("[Grantiva] SSE disconnected (\(error.localizedDescription)). Reconnecting in \(Int(delay))s")
            }

            guard !Task.isCancelled else { return }

            try? await Task.sleep(for: .seconds(delay))
        }
    }

    // MARK: - Connection

    private func connect() async throws {
        var components = URLComponents(string: "\(configuration.baseURL)/api/v1/flags/stream")!
        components.queryItems = [
            URLQueryItem(name: "environment", value: environment.rawValue)
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        try await applyAuth(to: &request)

        // `timeoutIntervalForResource` is the total lifetime — infinite so the
        // stream can stay open indefinitely. `timeoutIntervalForRequest` is an
        // IDLE timeout (time between received bytes), sized to ~3 server
        // keepalives — see `idleTimeout`.
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = Self.idleTimeout
        sessionConfig.timeoutIntervalForResource = .infinity
        if let protocolClasses {
            sessionConfig.protocolClasses = protocolClasses
        }
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }

        let (asyncBytes, response) = try await session.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GrantivaError.invalidResponse
        }

        switch http.statusCode {
        case 200...299: break
        case 401:
            // Our token looked valid but the server disagrees. Refresh once; the
            // run loop reconnects promptly on success and backs off for a long
            // time otherwise, so a rejected token never turns into a 401 storm.
            if let refreshToken, await refreshToken() {
                throw AuthEvent.tokenRefreshed
            }
            throw AuthEvent.tokenUnavailable
        case 429: throw GrantivaError.rateLimited
        default:
            throw GrantivaError.networkError(
                NSError(domain: "HTTPError", code: http.statusCode)
            )
        }

        Logger.debug("[Grantiva] SSE connected to flag stream (env: \(environment.rawValue))")
        try await parseSSEStream(asyncBytes)
    }

    // MARK: - Auth

    private func applyAuth(to request: inout URLRequest) async throws {
        // Always include Bundle ID + Team ID for app scoping. Auth precedence:
        // attestation JWT > API key. The backend rejects requests with neither.
        request.setValue(Bundle.main.bundleIdentifier ?? "", forHTTPHeaderField: "X-Bundle-ID")
        request.setValue(teamId, forHTTPHeaderField: "X-Team-ID")

        var token = getToken()
        if token == nil, let refreshToken {
            // Expired or missing token: renew it before connecting instead of
            // sending a request we already know the server will reject.
            guard await refreshToken(), let renewed = getToken() else {
                throw AuthEvent.tokenUnavailable
            }
            token = renewed
        }

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let apiKey = configuration.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
    }

    // MARK: - SSE Parsing

    /// Reads lines from the byte stream and dispatches complete SSE events.
    private func parseSSEStream(_ bytes: URLSession.AsyncBytes) async throws {
        var eventName: String?
        var dataLines: [String] = []

        for try await line in bytes.lines {
            if Task.isCancelled { throw CancellationError() }

            if line.hasPrefix("event:") {
                eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            } else if line.isEmpty {
                // Blank line = event boundary
                defer {
                    eventName = nil
                    dataLines.removeAll()
                }
                guard eventName == "flags", !dataLines.isEmpty else { continue }

                let payload = dataLines.joined(separator: "\n")
                if let flags = parseFlags(from: payload) {
                    onFlagsUpdate?(flags)
                }
            }
            // Ignore `id:` and `retry:` directives for now
        }
    }

    // MARK: - Flag Payload Parsing

    /// Parses `{"flags": {"key": value, ...}}` into `[String: FlagValue]`.
    private func parseFlags(from json: String) -> [String: FlagValue]? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let flagsDict = obj["flags"] as? [String: Any] else {
            Logger.debug("[Grantiva] SSE: could not parse flags payload")
            return nil
        }

        var result: [String: FlagValue] = [:]
        for (key, value) in flagsDict {
            let (rawValue, valueType) = Self.classify(value)
            result[key] = FlagValue(rawValue: rawValue, valueType: valueType)
        }
        return result
    }

    /// Mirrors `FlagAPIClient.classify` — classifies a JSON value into a raw string + type pair.
    private static func classify(_ value: Any) -> (String, FlagValueType) {
        if let nsNumber = value as? NSNumber {
            if CFGetTypeID(nsNumber) == CFBooleanGetTypeID() {
                return (nsNumber.boolValue ? "true" : "false", .boolean)
            }
            if nsNumber.doubleValue == Double(nsNumber.intValue) {
                return ("\(nsNumber.intValue)", .integer)
            }
            return ("\(nsNumber.doubleValue)", .double)
        }
        if let str = value as? String { return (str, .string) }
        if let data = try? JSONSerialization.data(withJSONObject: value),
           let jsonStr = String(data: data, encoding: .utf8) {
            return (jsonStr, .json)
        }
        return ("\(value)", .string)
    }
}
