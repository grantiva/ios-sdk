import Foundation

/// Sends periodic heartbeats to the server to maintain live device presence.
///
/// Starts automatically after attestation succeeds. The server returns the
/// recommended interval (default 120s). Heartbeats are fire-and-forget —
/// failures are logged but don't propagate errors.
internal final class HeartbeatManager: @unchecked Sendable {
    private let apiClient: HeartbeatAPIClient
    private let getToken: () -> String?
    private let getDeviceId: () -> String?

    private var timerTask: Task<Void, Never>?
    private let interval: TimeInterval

    /// - Parameter interval: seconds between heartbeats. Defaults to 120; overridable
    ///   at `internal` visibility only so tests don't have to wait two minutes.
    init(
        apiClient: HeartbeatAPIClient,
        getToken: @escaping () -> String?,
        getDeviceId: @escaping () -> String?,
        interval: TimeInterval = 120
    ) {
        self.apiClient = apiClient
        self.getToken = getToken
        self.getDeviceId = getDeviceId
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
        do {
            try await apiClient.sendHeartbeat(
                token: getToken(),
                deviceId: getDeviceId(),
                appState: "active"
            )
        } catch {
            Logger.debug("[Grantiva] Heartbeat failed: \(error.localizedDescription)")
        }
    }
}
