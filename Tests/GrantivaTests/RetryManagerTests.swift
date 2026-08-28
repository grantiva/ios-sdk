import XCTest
@testable import Grantiva

/// Tests for `RetryManager` — the SDK's retry/backoff policy.
///
/// NOTE: as of 2.1.0 `RetryManager.executeWithRetry` has no call sites in
/// `Sources/`, and `GrantivaConfiguration.retryAttempts` is stored but never read.
/// These tests pin the policy's behaviour so the contract is defined when it is
/// wired up (and so a regression in it is visible).
final class RetryManagerTests: XCTestCase {

    /// Counts invocations across concurrency domains without a mocking framework.
    private actor CallCounter {
        private(set) var count = 0
        func increment() -> Int {
            count += 1
            return count
        }
    }

    // Keep the suite fast: backoff is exponential, so the base must be tiny.
    private let fastBase: TimeInterval = 0.001

    // MARK: - shouldRetry: which errors are retryable

    func testShouldRetryTransientGrantivaErrors() {
        XCTAssertTrue(RetryManager.shouldRetry(error: GrantivaError.networkError(URLError(.timedOut))))
        XCTAssertTrue(RetryManager.shouldRetry(error: GrantivaError.challengeExpired))
    }

    func testShouldNotRetryTerminalGrantivaErrors() {
        // Retrying these can only burn attempts — the outcome is deterministic.
        XCTAssertFalse(RetryManager.shouldRetry(error: GrantivaError.validationFailed))
        XCTAssertFalse(RetryManager.shouldRetry(error: GrantivaError.deviceNotSupported))
        XCTAssertFalse(RetryManager.shouldRetry(error: GrantivaError.attestationNotAvailable))
        XCTAssertFalse(RetryManager.shouldRetry(error: GrantivaError.keyGenerationFailed))
        XCTAssertFalse(RetryManager.shouldRetry(error: GrantivaError.tokenExpired))
        XCTAssertFalse(RetryManager.shouldRetry(error: GrantivaError.configurationError))
        XCTAssertFalse(RetryManager.shouldRetry(error: GrantivaError.invalidResponse))
        XCTAssertFalse(RetryManager.shouldRetry(error: GrantivaError.reattestRequired))
        XCTAssertFalse(RetryManager.shouldRetry(error: GrantivaError.assertionKeyInvalid))
        XCTAssertFalse(RetryManager.shouldRetry(error: GrantivaError.keyAlreadyAttested))
        XCTAssertFalse(RetryManager.shouldRetry(error: GrantivaError.simulatorAPIKeyRequired))
        XCTAssertFalse(RetryManager.shouldRetry(error: GrantivaError.serverError(reason: "nope")))
    }

    func testShouldNotRetryLimitExceeded() {
        // A MAD ceiling does not clear itself within a retry window; hammering it
        // would only inflate the tenant's request count.
        XCTAssertFalse(RetryManager.shouldRetry(error: GrantivaError.limitExceeded(limit: 1000, current: 1001)))
    }

    func testShouldRetryRateLimited() {
        // 429 is transient by definition and the caller backs off exponentially, so it is
        // retryable — deliberately distinct from `.limitExceeded` (the monthly MAD quota),
        // which is exhausted for the billing period and is asserted non-retryable above.
        XCTAssertTrue(RetryManager.shouldRetry(error: GrantivaError.rateLimited))
    }

    func testShouldRetryTransientURLErrors() {
        for code: URLError.Code in [.timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet] {
            XCTAssertTrue(
                RetryManager.shouldRetry(error: URLError(code)),
                "URLError \(code.rawValue) should be retryable"
            )
        }
    }

    func testShouldNotRetryTerminalURLErrors() {
        for code: URLError.Code in [.badURL, .unsupportedURL, .cancelled, .userAuthenticationRequired, .badServerResponse] {
            XCTAssertFalse(
                RetryManager.shouldRetry(error: URLError(code)),
                "URLError \(code.rawValue) should not be retryable"
            )
        }
    }

    func testShouldNotRetryUnknownErrors() {
        XCTAssertFalse(RetryManager.shouldRetry(error: NSError(domain: "Whatever", code: 1)))
        struct Custom: Error {}
        XCTAssertFalse(RetryManager.shouldRetry(error: Custom()))
    }

    // MARK: - calculateDelay: backoff progression

    func testDelayGrowsExponentiallyFromBase() {
        let base: TimeInterval = 1.0
        // delay = base * 2^(attempt-1), plus 0–10% jitter.
        for (attempt, expected) in [(1, 1.0), (2, 2.0), (3, 4.0), (4, 8.0)] {
            let delay = RetryManager.calculateDelay(attempt: attempt, baseDelay: base)
            XCTAssertGreaterThanOrEqual(delay, expected, "attempt \(attempt) must be at least the exponential term")
            XCTAssertLessThanOrEqual(delay, expected * 1.1, "attempt \(attempt) jitter must not exceed 10%")
        }
    }

    func testDelayIsMonotonicAcrossAttempts() {
        let base: TimeInterval = 1.0
        // Even with worst-case jitter, attempt N+1 must exceed attempt N (1.1x < 2x).
        var previous = RetryManager.calculateDelay(attempt: 1, baseDelay: base)
        for attempt in 2...5 {
            let current = RetryManager.calculateDelay(attempt: attempt, baseDelay: base)
            XCTAssertGreaterThan(current, previous, "backoff must increase at attempt \(attempt)")
            previous = current
        }
    }

    func testDelayIsCappedAtThirtySeconds() {
        // Without the cap, attempt 20 would be ~500,000 seconds.
        for attempt in [10, 20, 40] {
            XCTAssertEqual(RetryManager.calculateDelay(attempt: attempt, baseDelay: 1.0), 30.0, accuracy: 0.0001)
        }
    }

    func testDelayScalesWithBaseDelay() {
        let small = RetryManager.calculateDelay(attempt: 1, baseDelay: 0.1)
        XCTAssertGreaterThanOrEqual(small, 0.1)
        XCTAssertLessThanOrEqual(small, 0.11)
    }

    // MARK: - executeWithRetry

    func testReturnsImmediatelyOnSuccess() async throws {
        let counter = CallCounter()
        let value = try await RetryManager.executeWithRetry(maxAttempts: 3, baseDelay: fastBase) {
            _ = await counter.increment()
            return "ok"
        }
        XCTAssertEqual(value, "ok")
        let count = await counter.count
        XCTAssertEqual(count, 1, "a succeeding operation must not be re-issued")
    }

    func testStopsRetryingOnceOperationSucceeds() async throws {
        let counter = CallCounter()
        let value = try await RetryManager.executeWithRetry(maxAttempts: 5, baseDelay: fastBase) {
            let attempt = await counter.increment()
            if attempt < 3 { throw GrantivaError.networkError(URLError(.timedOut)) }
            return attempt
        }
        XCTAssertEqual(value, 3)
        let count = await counter.count
        XCTAssertEqual(count, 3, "must stop at the first success, not run out the attempt budget")
    }

    func testRetriesRetryableErrorUpToMaxAttempts() async {
        let counter = CallCounter()
        do {
            _ = try await RetryManager.executeWithRetry(maxAttempts: 4, baseDelay: fastBase) {
                _ = await counter.increment()
                throw GrantivaError.networkError(URLError(.networkConnectionLost))
            }
            XCTFail("Expected the retry budget to be exhausted")
        } catch {
            guard case GrantivaError.networkError = error else {
                return XCTFail("Expected the last error to surface, got \(error)")
            }
        }
        let count = await counter.count
        XCTAssertEqual(count, 4, "maxAttempts is a total-attempt cap, not a retry-count cap")
    }

    func testDoesNotRetryTerminalError() async {
        let counter = CallCounter()
        do {
            _ = try await RetryManager.executeWithRetry(maxAttempts: 5, baseDelay: fastBase) {
                _ = await counter.increment()
                throw GrantivaError.validationFailed
            }
            XCTFail("Expected validationFailed to propagate")
        } catch {
            guard case GrantivaError.validationFailed = error else {
                return XCTFail("Expected .validationFailed, got \(error)")
            }
        }
        let count = await counter.count
        XCTAssertEqual(count, 1, "a terminal error must fail fast on the first attempt")
    }

    func testTerminalErrorAfterRetryableOnesStillFailsFast() async {
        let counter = CallCounter()
        do {
            _ = try await RetryManager.executeWithRetry(maxAttempts: 6, baseDelay: fastBase) {
                let attempt = await counter.increment()
                if attempt < 3 { throw GrantivaError.challengeExpired }
                throw GrantivaError.limitExceeded(limit: 10, current: 11)
            }
            XCTFail("Expected limitExceeded to propagate")
        } catch {
            guard case GrantivaError.limitExceeded(let limit, let current) = error else {
                return XCTFail("Expected .limitExceeded, got \(error)")
            }
            XCTAssertEqual(limit, 10)
            XCTAssertEqual(current, 11)
        }
        let count = await counter.count
        XCTAssertEqual(count, 3, "must stop the moment a terminal error appears")
    }

    func testMaxAttemptsOfOneRunsExactlyOnce() async {
        let counter = CallCounter()
        do {
            _ = try await RetryManager.executeWithRetry(maxAttempts: 1, baseDelay: fastBase) {
                _ = await counter.increment()
                throw GrantivaError.networkError(URLError(.timedOut))
            }
            XCTFail("Expected the error to propagate")
        } catch {
            // expected
        }
        let count = await counter.count
        XCTAssertEqual(count, 1)
    }

    func testUnretryableUnknownErrorPropagatesUnchanged() async {
        struct Sentinel: Error, Equatable {}
        let counter = CallCounter()
        do {
            _ = try await RetryManager.executeWithRetry(maxAttempts: 3, baseDelay: fastBase) {
                _ = await counter.increment()
                throw Sentinel()
            }
            XCTFail("Expected Sentinel to propagate")
        } catch {
            XCTAssertTrue(error is Sentinel, "the original error must not be wrapped, got \(error)")
        }
        let count = await counter.count
        XCTAssertEqual(count, 1)
    }
}
