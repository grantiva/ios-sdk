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
    private let tokenManager: TokenManager

    /// Invoked on every successfully parsed `flags` SSE event.
    var onFlagsUpdate: ((FlagsUpdate) -> Void)?

    private var streamTask: Task<Void, Never>?
    private let lock = NSLock()
    private var _isRunning = false

    // Exponential backoff
    private let minBackoff: TimeInterval = 1.0
    private let maxBackoff: TimeInterval = 30.0

    // MARK: - Init

    init(
        configuration: GrantivaConfiguration,
        teamId: String,
        environment: FlagEnvironment,
        tokenManager: TokenManager
    ) {
        self.configuration = configuration
        self.teamId = teamId
        self.environment = environment
        self.tokenManager = tokenManager
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

            do {
                try await connect()
                // Clean disconnect — reset backoff and reconnect immediately
                backoff = minBackoff
                Logger.debug("[Grantiva] SSE stream closed cleanly. Reconnecting…")
            } catch is CancellationError {
                return
            } catch {
                Logger.debug("[Grantiva] SSE disconnected (\(error.localizedDescription)). Reconnecting in \(Int(backoff))s")
            }

            guard !Task.isCancelled else { return }

            try? await Task.sleep(for: .seconds(backoff))
            backoff = min(backoff * 2, maxBackoff)
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
        applyAuth(to: &request)

        // Use a URLSession that never times out on the resource so the stream can
        // stay open indefinitely. The request itself still has a connect timeout.
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.timeoutIntervalForResource = .infinity
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }

        let (asyncBytes, response) = try await session.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GrantivaError.invalidResponse
        }

        switch http.statusCode {
        case 200...299: break
        case 401: throw GrantivaError.validationFailed
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

    private func applyAuth(to request: inout URLRequest) {
        if let token = tokenManager.getStoredToken()?.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let apiKey = configuration.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue(Bundle.main.bundleIdentifier ?? "", forHTTPHeaderField: "X-Bundle-ID")
            request.setValue(teamId, forHTTPHeaderField: "X-Team-ID")
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
