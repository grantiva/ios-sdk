import XCTest
@testable import Grantiva

/// A `URLProtocol` stub that plays back a scripted list of outcomes and counts
/// how many requests the client actually issued. No external dependencies.
final class StubURLProtocol: URLProtocol {
    enum Outcome {
        case failure(URLError.Code)
        case response(statusCode: Int, body: Data)
    }

    private struct State {
        var outcomes: [Outcome] = []
        var requestCount = 0
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var state = State()

    /// Installs the given outcomes. The last outcome repeats if more requests arrive.
    static func setUp(outcomes: [Outcome]) {
        lock.lock()
        defer { lock.unlock() }
        state = State(outcomes: outcomes, requestCount: 0)
    }

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return state.requestCount
    }

    private static func nextOutcome() -> Outcome {
        lock.lock()
        defer { lock.unlock() }
        let index = min(state.requestCount, state.outcomes.count - 1)
        state.requestCount += 1
        return state.outcomes[index]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        switch StubURLProtocol.nextOutcome() {
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .response(let statusCode, let body):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

final class RetryWiringTests: XCTestCase {

    /// Fast backoff so retry tests don't sleep for seconds.
    private func makeClient(retryAttempts: Int = 3) -> GrantivaAPIClient {
        let config = GrantivaConfiguration(
            baseURL: "https://api.example.com",
            retryAttempts: retryAttempts,
            retryBaseDelay: 0.01,
            timeout: 5
        )
        return GrantivaAPIClient(
            configuration: config,
            teamId: "TEAM123",
            protocolClasses: [StubURLProtocol.self]
        )
    }

    private var challengeBody: Data {
        #"{"challenge":"abc123","expiresAt":"2026-01-01T00:00:00Z"}"#.data(using: .utf8)!
    }

    private func makeAttestationRequest() -> AttestationRequest {
        AttestationRequest(
            bundleId: "io.grantiva.test",
            teamId: "TEAM123",
            keyId: "KEY",
            attestationObject: "OBJ",
            clientDataHash: "HASH",
            challenge: "abc123",
            deviceModel: nil,
            osVersion: nil,
            appVersion: nil,
            appBuildNumber: nil,
            platform: nil,
            deviceFingerprint: nil,
            subjectId: nil
        )
    }

    // MARK: - Retry-safe endpoint

    /// The challenge GET is idempotent, so a transient transport failure is retried.
    func testRequestChallengeRetriesTransientTransportFailure() async throws {
        StubURLProtocol.setUp(outcomes: [
            .failure(.networkConnectionLost),
            .failure(.timedOut),
            .response(statusCode: 200, body: challengeBody)
        ])

        let response = try await makeClient().requestChallenge()

        XCTAssertEqual(response.challenge, "abc123")
        XCTAssertEqual(StubURLProtocol.requestCount, 3, "Expected two retries before success")
    }

    /// A terminal server error must fail on the first attempt — no retries.
    func testRequestChallengeDoesNotRetryTerminalServerError() async {
        let body = #"{"error":true,"reason":"invalid bundle id"}"#.data(using: .utf8)!
        StubURLProtocol.setUp(outcomes: [.response(statusCode: 400, body: body)])

        do {
            _ = try await makeClient().requestChallenge()
            XCTFail("Expected requestChallenge to throw")
        } catch let error as GrantivaError {
            guard case .serverError(let reason) = error else {
                return XCTFail("Expected .serverError, got \(error)")
            }
            XCTAssertEqual(reason, "invalid bundle id")
        } catch {
            XCTFail("Expected GrantivaError, got \(error)")
        }

        XCTAssertEqual(StubURLProtocol.requestCount, 1, "Terminal errors must not be retried")
    }

    /// Retries are bounded by `configuration.retryAttempts`.
    func testRequestChallengeStopsAfterConfiguredAttempts() async {
        StubURLProtocol.setUp(outcomes: [.failure(.notConnectedToInternet)])

        do {
            _ = try await makeClient(retryAttempts: 2).requestChallenge()
            XCTFail("Expected requestChallenge to throw")
        } catch {
            // expected
        }

        XCTAssertEqual(StubURLProtocol.requestCount, 2)
    }

    /// `retryAttempts: 1` means no retry at all.
    func testRequestChallengeWithSingleAttemptIssuesOneRequest() async {
        StubURLProtocol.setUp(outcomes: [.failure(.timedOut)])

        _ = try? await makeClient(retryAttempts: 1).requestChallenge()

        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    // MARK: - Retry classification

    /// 429 throttling is transient and is retried with backoff.
    func testRateLimitedIsRetryable() {
        XCTAssertTrue(RetryManager.shouldRetry(error: GrantivaError.rateLimited))
    }

    /// The monthly MAD quota is exhausted for the billing period — never retried.
    func testLimitExceededIsNotRetryable() {
        XCTAssertFalse(RetryManager.shouldRetry(error: GrantivaError.limitExceeded(limit: 1000, current: 1001)))
    }

    func testValidationFailedIsNotRetryable() {
        XCTAssertFalse(RetryManager.shouldRetry(error: GrantivaError.validationFailed))
    }

    // MARK: - Deliberately non-retried endpoints

    /// Attestation consumes a one-time challenge and a once-per-lifetime App Attest
    /// key, so it must issue exactly one request even for a retryable transport error.
    func testValidateAttestationIsNotRetried() async {
        StubURLProtocol.setUp(outcomes: [.failure(.networkConnectionLost)])

        _ = try? await makeClient().validateAttestation(makeAttestationRequest())

        XCTAssertEqual(StubURLProtocol.requestCount, 1, "Attestation must never be retried")
    }

    /// Assertion refresh carries a monotonic signature counter; a replay would be
    /// rejected server-side, so it must not be retried either.
    func testRefreshWithAssertionIsNotRetried() async {
        StubURLProtocol.setUp(outcomes: [.failure(.timedOut)])

        let request = AssertionRefreshRequest(
            keyId: "KEY",
            assertion: "ASSERTION",
            clientDataHash: "HASH",
            challenge: "abc123",
            subjectId: nil
        )
        _ = try? await makeClient().refreshWithAssertion(request)

        XCTAssertEqual(StubURLProtocol.requestCount, 1, "Assertion refresh must never be retried")
    }
}
