import Foundation

/// Sends periodic heartbeats to the server to maintain live device presence.
///
/// Starts automatically after attestation succeeds. The server returns the
/// recommended interval (default 120s). Heartbeats are fire-and-forget —
/// failures are logged but don't propagate errors.
///
/// `getToken` must return `nil` for an expired token. When it does, or when the
/// server answers 401, the manager asks `refreshToken` for a new one before sending
/// (or resending) the beat, so an expired token never turns into a stream of 401s
/// while the host app happens not to be calling `validateAttestation()`.
internal final class HeartbeatManager: @unchecked Sendable {
    private let apiClient: HeartbeatAPIClient
    private let getToken: () -> String?
    private let getDeviceId: () -> String?
    private let refreshToken: (() async -> Bool)?

    private var timerTask: Task<Void, Never>?
    private let interval: TimeInterval

    /// - Parameter interval: seconds between heartbeats. Defaults to 120; overridable
    ///   at `internal` visibility only so tests don't have to wait two minutes.
    init(
        apiClient: HeartbeatAPIClient,
        getToken: @escaping () -> String?,
        getDeviceId: @escaping () -> String?,
        refreshToken: (() async -> Bool)? = nil,
        interval: TimeInterval = 120
    ) {
        self.apiClient = apiClient
        self.getToken = getToken
        self.getDeviceId = getDeviceId
        self.refreshToken = refreshToken
        self.interval = interval
    }

    /// Start sending periodic heartbeats.
    func start() {
        guard timerTask == nil else { return }
        timerTask = Task { [weak self] in
            // Send first heartbeat immediately
            await self?.sendHeartbeat()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.interval ?? 120))
                guard !Task.isCancelled else { break }
                await self?.sendHeartbeat()
            }
        }
    }

    /// Stop sending heartbeats.
    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func sendHeartbeat() async {
        var token = getToken()

        // Token missing or expired: refresh first rather than sending a beat the
        // server will reject. Without a refresh hook (API key mode) fall through and
        // let the client use the API key.
        if token == nil, let refreshToken {
            guard await refreshToken() else {
                Logger.debug("[Grantiva] Heartbeat skipped: token refresh failed")
                return
            }
            token = getToken()
        }

        do {
            try await send(token: token)
        } catch let error where Self.isUnauthorized(error) {
            // The server disagrees with our view of the token (revoked, clock skew,
            // rotated signing key). Refresh once and retry once; give up otherwise.
            guard let refreshToken, await refreshToken() else {
                Logger.debug("[Grantiva] Heartbeat rejected (401) and token refresh unavailable")
                return
            }
            do {
                try await send(token: getToken())
            } catch {
                Logger.debug("[Grantiva] Heartbeat failed after token refresh: \(error.localizedDescription)")
            }
        } catch {
            Logger.debug("[Grantiva] Heartbeat failed: \(error.localizedDescription)")
        }
    }

    private func send(token: String?) async throws {
        try await apiClient.sendHeartbeat(
            token: token,
            deviceId: getDeviceId(),
            appState: "active"
        )
    }

    private static func isUnauthorized(_ error: Error) -> Bool {
        if case GrantivaError.networkError(let underlying) = error {
            return (underlying as NSError).code == 401
        }
        return false
    }
}
