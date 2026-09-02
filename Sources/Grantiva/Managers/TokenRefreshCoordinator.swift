import Foundation

/// Collapses concurrent token refresh requests into a single in-flight operation.
///
/// The heartbeat timer and the flag SSE stream can both notice an expired token at
/// the same moment. Without coordination each would run its own attestation refresh,
/// burning two challenges and racing the App Attest assertion counter. The first
/// caller runs `operation`; everyone who arrives while it is in flight waits for
/// that same result.
internal final class TokenRefreshCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var isRefreshing = false
    private var waiters: [CheckedContinuation<Bool?, Never>] = []

    /// Runs `operation` unless a refresh is already in flight, in which case the
    /// caller suspends until that refresh finishes and receives its result.
    func refresh(_ operation: () async -> Bool) async -> Bool {
        if let sharedResult = await joinInFlightRefresh() {
            return sharedResult
        }

        let result = await operation()

        let pending: [CheckedContinuation<Bool?, Never>] = lock.withLock {
            isRefreshing = false
            let pending = waiters
            waiters.removeAll()
            return pending
        }
        for waiter in pending {
            waiter.resume(returning: result)
        }
        return result
    }

    /// Returns `nil` when the caller has claimed the refresh slot and must run the
    /// operation itself, or the shared result once an in-flight refresh completes.
    private func joinInFlightRefresh() async -> Bool? {
        await withCheckedContinuation { continuation in
            let claimed: Bool = lock.withLock {
                if isRefreshing {
                    waiters.append(continuation)
                    return false
                }
                isRefreshing = true
                return true
            }
            if claimed {
                continuation.resume(returning: nil)
            }
        }
    }
}

/// Lets background clients (heartbeat, flag stream) ask the SDK for a fresh token
/// without holding a strong reference to `Grantiva` or capturing it in `@Sendable`
/// closures. `Grantiva` sets `owner` at the end of its initializer.
internal final class BackgroundTokenRefresher: @unchecked Sendable {
    private let lock = NSLock()
    private let coordinator = TokenRefreshCoordinator()
    private weak var _owner: Grantiva?

    var owner: Grantiva? {
        get { lock.withLock { _owner } }
        set { lock.withLock { _owner = newValue } }
    }

    /// Refreshes the token through the normal attestation path. Returns `true` when a
    /// usable token is now stored, `false` when the refresh failed or the SDK is gone.
    func refresh() async -> Bool {
        guard let owner else { return false }
        return await coordinator.refresh {
            do {
                _ = try await owner.validateAttestation()
                return true
            } catch {
                Logger.warning("[Grantiva] Background token refresh failed: \(error)")
                return false
            }
        }
    }
}
