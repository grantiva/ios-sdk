import Foundation

/// Handles heartbeat API calls to record device presence.
internal final class HeartbeatAPIClient: @unchecked Sendable {
    private let configuration: GrantivaConfiguration
    private let session: URLSession
    private let teamId: String

    init(configuration: GrantivaConfiguration, teamId: String) {
        self.configuration = configuration
        self.teamId = teamId

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15
        sessionConfig.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: sessionConfig)
    }

    /// Internal seam: injects a pre-built `URLSession` so tests can install a stub
    /// `URLProtocol`. Not part of the public API.
    init(configuration: GrantivaConfiguration, teamId: String, session: URLSession) {
        self.configuration = configuration
        self.teamId = teamId
        self.session = session
    }

    /// Send a heartbeat to the server.
    /// - Parameters:
    ///   - token: JWT token from attestation (nil in API key mode)
    ///   - deviceId: Device identifier for API key / simulator mode
    ///   - appState: Current app state (e.g. "active", "background")
    /// - Returns: The server's recommended delay before the next heartbeat, in
    ///   seconds, or `nil` when the response carries none.
    @discardableResult
    func sendHeartbeat(token: String?, deviceId: String?, appState: String?) async throws -> TimeInterval? {
        let url = URL(string: "\(configuration.baseURL)/api/v1/heartbeat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Always send Bundle ID + Team ID for app scoping. Auth precedence:
        // attestation JWT > API key. The backend rejects requests with neither.
        request.setValue(getBundleId(), forHTTPHeaderField: "X-Bundle-ID")
        request.setValue(teamId, forHTTPHeaderField: "X-Team-ID")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let apiKey = configuration.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: String] = [:]
        body["sdkVersion"] = GrantivaVersion.current
        if let appState { body["appState"] = appState }
        if let deviceId { body["deviceId"] = deviceId }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GrantivaError.networkError(
                NSError(domain: "HeartbeatError",
                        code: (response as? HTTPURLResponse)?.statusCode ?? 0)
            )
        }

        guard let payload = try? JSONDecoder().decode(HeartbeatResponse.self, from: data),
              let next = payload.nextHeartbeatSeconds, next > 0 else {
            return nil
        }
        return TimeInterval(next)
    }

    private struct HeartbeatResponse: Decodable {
        let nextHeartbeatSeconds: Int?
    }

    private func getBundleId() -> String {
        Bundle.main.bundleIdentifier ?? ""
    }
}
