import Foundation

internal class RetryManager {
    
    static func executeWithRetry<T>(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 1.0,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                if attempt == maxAttempts {
                    break
                }
                
                if !shouldRetry(error: error) {
                    throw error
                }
                
                let delay = calculateDelay(attempt: attempt, baseDelay: baseDelay)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        throw lastError ?? GrantivaError.networkError(NSError(domain: "RetryFailed", code: -1))
    }
    
    /// Classifies an error as retryable (transient) or terminal.
    ///
    /// `.rateLimited` (HTTP 429) is treated as **retryable**: throttling is transient by
    /// definition and the caller backs off exponentially with jitter before trying again.
    /// Note this is distinct from `.limitExceeded`, which is the tenant's monthly MAD
    /// quota — that is exhausted for the rest of the billing period, so it falls through
    /// to `default` and is never retried.
    ///
    /// Backoff is currently computed locally and does not honour a `Retry-After`
    /// response header; the header is not surfaced through `GrantivaError` today.
    ///
    /// Exposed at `internal` visibility (rather than `private`) so the retry policy can
    /// be unit-tested directly. Not part of the public API.
    internal static func shouldRetry(error: Error) -> Bool {
        if let grantivaError = error as? GrantivaError {
            switch grantivaError {
            case .networkError:
                return true
            case .challengeExpired:
                return true
            case .rateLimited:
                return true
            default:
                return false
            }
        }
        
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        
        return false
    }
    
    /// Exposed at `internal` visibility (rather than `private`) so backoff progression
    /// can be unit-tested directly. Not part of the public API.
    static func calculateDelay(attempt: Int, baseDelay: TimeInterval) -> TimeInterval {
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt - 1))
        let jitter = Double.random(in: 0.0...0.1) * exponentialDelay
        return min(exponentialDelay + jitter, 30.0)
    }
}