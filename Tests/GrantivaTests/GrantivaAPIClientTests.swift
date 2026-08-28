import XCTest
@testable import Grantiva

/// Tests for `GrantivaAPIClient` — the attestation HTTP client.
///
/// Network is stubbed with `StubURLProtocol` (no external dependencies); the
/// client is constructed with the internal `session:` seam.
final class GrantivaAPIClientTests: XCTestCase {

    private let baseURL = "https://test.grantiva.invalid"

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeClient(apiKey: String? = nil, teamId: String = "TEAM123") -> GrantivaAPIClient {
        let config = GrantivaConfiguration(baseURL: baseURL, apiKey: apiKey)
        return GrantivaAPIClient(configuration: config, teamId: teamId, session: StubURLProtocol.makeSession())
    }

    private func makeAttestationRequest() -> AttestationRequest {
        AttestationRequest(
            bundleId: "io.grantiva.test",
            teamId: "TEAM123",
            keyId: "KEY-1",
            attestationObject: "b64-attestation",
            clientDataHash: "b64-hash",
            challenge: "challenge-value",
            deviceModel: "iPhone17,1",
            osVersion: "18.0",
            appVersion: "1.2.3",
            appBuildNumber: "42",
            platform: "iOS",
            deviceFingerprint: "fingerprint",
            subjectId: nil
        )
    }

    private var successAttestationBody: String {
        """
        {
          "isValid": true,
          "token": "jwt.token.value",
          "expiresAt": "2026-01-01T00:00:00Z",
          "deviceIntelligence": {
            "deviceId": "device-1",
            "riskScore": 12,
            "riskCategory": "trusted",
            "deviceIntegrity": "intact",
            "jailbreakDetected": false,
            "attestationCount": 3,
            "lastAttestationDate": "2025-12-31T00:00:00Z"
          },
          "customClaims": {"tier": "pro"}
        }
        """
    }

    // MARK: - requestChallenge: happy path

    func testRequestChallengeDecodesSuccessResponse() async throws {
        StubURLProtocol.enqueue(.json(#"{"challenge":"abc123","expiresAt":"2026-01-01T00:00:00Z"}"#))

        let response = try await makeClient().requestChallenge()

        XCTAssertEqual(response.challenge, "abc123")
        XCTAssertEqual(response.expiresAt, "2026-01-01T00:00:00Z")
    }

    func testRequestChallengeUsesGetOnTheChallengeEndpoint() async throws {
        StubURLProtocol.enqueue(.json(#"{"challenge":"abc","expiresAt":"x"}"#))

        _ = try await makeClient().requestChallenge()

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url?.absoluteString, "\(baseURL)/api/v1/attestation/challenge")
    }

    // MARK: - Auth headers

    func testTenantHeadersArePresentWithoutAnAPIKey() async throws {
        StubURLProtocol.enqueue(.json(#"{"challenge":"abc","expiresAt":"x"}"#))

        _ = try await makeClient(teamId: "TEAM999").requestChallenge()

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        // Bundle ID comes from Bundle.main; in the test host it may be empty, but the
        // header itself must be sent or the backend can't identify the tenant.
        XCTAssertNotNil(request.header("X-Bundle-ID"), "X-Bundle-ID must be sent for tenant identification")
        XCTAssertEqual(request.header("X-Team-ID"), "TEAM999")
        XCTAssertEqual(request.header("Content-Type"), "application/json")
        XCTAssertNil(request.header("Authorization"), "no API key configured — no bearer token expected")
    }

    func testAPIKeyIsSentAsBearerToken() async throws {
        StubURLProtocol.enqueue(.json(#"{"challenge":"abc","expiresAt":"x"}"#))

        _ = try await makeClient(apiKey: "gdev_secret").requestChallenge()

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.header("Authorization"), "Bearer gdev_secret")
    }

    /// Pins current `applyAuth` behaviour: API-key mode is *exclusive* — the tenant
    /// headers are dropped, so the API key alone must identify the tenant server-side.
    /// (`HeartbeatAPIClient` by contrast always sends both.) If this ever changes,
    /// this test should be updated deliberately, not silently.
    func testAPIKeyModeOmitsTenantHeaders() async throws {
        StubURLProtocol.enqueue(.json(#"{"challenge":"abc","expiresAt":"x"}"#))

        _ = try await makeClient(apiKey: "gdev_secret").requestChallenge()

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertNil(request.header("X-Bundle-ID"))
        XCTAssertNil(request.header("X-Team-ID"))
    }

    // MARK: - requestChallenge: error mapping

    func testChallengeMapsVaporErrorBodyToServerError() async {
        StubURLProtocol.enqueue(.json(#"{"error":true,"reason":"unknown bundle id"}"#, status: 404))

        do {
            _ = try await makeClient().requestChallenge()
            XCTFail("Expected a thrown error")
        } catch {
            guard case GrantivaError.serverError(let reason) = error else {
                return XCTFail("Expected .serverError, got \(error)")
            }
            XCTAssertEqual(reason, "unknown bundle id")
        }
    }

    func testChallengeMapsMADLimitTo429LimitExceeded() async {
        StubURLProtocol.enqueue(.json(#"{"error":"mad_limit_exceeded","limit":1000,"current":1001}"#, status: 429))

        do {
            _ = try await makeClient().requestChallenge()
            XCTFail("Expected a thrown error")
        } catch {
            guard case GrantivaError.limitExceeded(let limit, let current) = error else {
                return XCTFail("Expected .limitExceeded, got \(error)")
            }
            XCTAssertEqual(limit, 1000)
            XCTAssertEqual(current, 1001)
        }
    }

    func testChallengeMapsServerFailureToValidationFailed() async {
        StubURLProtocol.enqueue(.status(500))

        do {
            _ = try await makeClient().requestChallenge()
            XCTFail("Expected a thrown error")
        } catch {
            guard case GrantivaError.validationFailed = error else {
                return XCTFail("Expected .validationFailed for 5xx, got \(error)")
            }
        }
    }

    func testChallengeMalformedJSONSurfacesAsDecodingErrorNotACrash() async {
        StubURLProtocol.enqueue(.json(#"{"challenge":"abc"}"#)) // `expiresAt` missing

        do {
            _ = try await makeClient().requestChallenge()
            XCTFail("Expected a thrown error")
        } catch {
            guard case GrantivaError.networkError(let underlying) = error else {
                return XCTFail("Expected .networkError wrapping a decode failure, got \(error)")
            }
            XCTAssertTrue(underlying is DecodingError, "Expected DecodingError, got \(underlying)")
        }
    }

    func testChallengeGarbageBodySurfacesAsDecodingError() async {
        StubURLProtocol.enqueue(.http(status: 200, body: Data("<html>not json</html>".utf8), headers: [:]))

        do {
            _ = try await makeClient().requestChallenge()
            XCTFail("Expected a thrown error")
        } catch {
            guard case GrantivaError.networkError(let underlying) = error else {
                return XCTFail("Expected .networkError, got \(error)")
            }
            XCTAssertTrue(underlying is DecodingError)
        }
    }

    func testChallengeTransportFailureMapsToNetworkError() async {
        StubURLProtocol.enqueue(.failure(URLError(.notConnectedToInternet)))

        do {
            _ = try await makeClient().requestChallenge()
            XCTFail("Expected a thrown error")
        } catch {
            guard case GrantivaError.networkError(let underlying) = error else {
                return XCTFail("Expected .networkError, got \(error)")
            }
            XCTAssertEqual((underlying as? URLError)?.code, .notConnectedToInternet)
        }
    }

    func testChallengeNonHTTPResponseMapsToInvalidResponse() async {
        StubURLProtocol.enqueue(.nonHTTPResponse)

        do {
            _ = try await makeClient().requestChallenge()
            XCTFail("Expected a thrown error")
        } catch {
            guard case GrantivaError.invalidResponse = error else {
                return XCTFail("Expected .invalidResponse, got \(error)")
            }
        }
    }

    // MARK: - No retry (documents current behaviour)

    /// `GrantivaAPIClient` does **not** wrap its calls in `RetryManager`, so a
    /// retryable transport failure results in exactly one network round trip.
    /// This pins the current contract; if retry is wired up, this test must change
    /// alongside it (and would otherwise catch an accidental request amplification).
    func testRetryableTransportFailureIssuesExactlyOneRequest() async {
        StubURLProtocol.setFallback(.failure(URLError(.timedOut)))

        _ = try? await makeClient().requestChallenge()

        XCTAssertEqual(StubURLProtocol.requestCount, 1, "client currently performs no retries")
    }

    func testTerminalServerErrorIssuesExactlyOneRequest() async {
        StubURLProtocol.setFallback(.json(#"{"error":true,"reason":"bad key"}"#, status: 400))

        _ = try? await makeClient().requestChallenge()

        XCTAssertEqual(StubURLProtocol.requestCount, 1, "a terminal 4xx must never be re-issued")
    }

    // MARK: - validateAttestation

    func testValidateAttestationDecodesSuccessResponse() async throws {
        StubURLProtocol.enqueue(.json(successAttestationBody))

        let response = try await makeClient().validateAttestation(makeAttestationRequest())

        XCTAssertTrue(response.isValid)
        XCTAssertEqual(response.token, "jwt.token.value")
        XCTAssertEqual(response.deviceIntelligence.deviceId, "device-1")
        XCTAssertEqual(response.deviceIntelligence.riskScore, 12)
        XCTAssertEqual(response.deviceIntelligence.riskCategory, "trusted")
        XCTAssertFalse(response.deviceIntelligence.jailbreakDetected)
        XCTAssertEqual(response.customClaims["tier"], "pro")
    }

    func testValidateAttestationPostsEncodedRequestBody() async throws {
        StubURLProtocol.enqueue(.json(successAttestationBody))

        _ = try await makeClient().validateAttestation(makeAttestationRequest())

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url?.absoluteString, "\(baseURL)/api/v1/attestation/validate")

        let body = try XCTUnwrap(request.bodyJSON)
        XCTAssertEqual(body["keyId"] as? String, "KEY-1")
        XCTAssertEqual(body["challenge"] as? String, "challenge-value")
        XCTAssertEqual(body["attestationObject"] as? String, "b64-attestation")
        XCTAssertEqual(body["clientDataHash"] as? String, "b64-hash")
        XCTAssertEqual(body["teamId"] as? String, "TEAM123")
    }

    func testValidateAttestationRiskScoreMayBeAbsentOnFreeTier() async throws {
        StubURLProtocol.enqueue(.json("""
        {
          "isValid": true,
          "token": "t",
          "expiresAt": "2026-01-01T00:00:00Z",
          "deviceIntelligence": {
            "deviceId": "device-1",
            "riskCategory": "trusted",
            "deviceIntegrity": "intact",
            "jailbreakDetected": false,
            "attestationCount": 1,
            "lastAttestationDate": null
          },
          "customClaims": {}
        }
        """))

        let response = try await makeClient().validateAttestation(makeAttestationRequest())

        XCTAssertNil(response.deviceIntelligence.riskScore, "free tier omits riskScore")
        XCTAssertNil(response.deviceIntelligence.lastAttestationDate)
        XCTAssertTrue(response.customClaims.isEmpty)
    }

    func testValidateAttestationMapsServerError() async {
        StubURLProtocol.enqueue(.json(#"{"error":true,"reason":"attestation rejected"}"#, status: 403))

        do {
            _ = try await makeClient().validateAttestation(makeAttestationRequest())
            XCTFail("Expected a thrown error")
        } catch {
            guard case GrantivaError.serverError(let reason) = error else {
                return XCTFail("Expected .serverError, got \(error)")
            }
            XCTAssertEqual(reason, "attestation rejected")
        }
    }

    func testValidateAttestationMapsMADLimit() async {
        StubURLProtocol.enqueue(.json(#"{"error":"mad_limit_exceeded","limit":25000,"current":25001}"#, status: 429))

        do {
            _ = try await makeClient().validateAttestation(makeAttestationRequest())
            XCTFail("Expected a thrown error")
        } catch {
            guard case GrantivaError.limitExceeded(let limit, _) = error else {
                return XCTFail("Expected .limitExceeded, got \(error)")
            }
            XCTAssertEqual(limit, 25000)
        }
    }

    func testValidateAttestationMalformedJSONDoesNotCrash() async {
        StubURLProtocol.enqueue(.json(#"{"isValid":true}"#)) // missing everything else

        do {
            _ = try await makeClient().validateAttestation(makeAttestationRequest())
            XCTFail("Expected a thrown error")
        } catch {
            guard case GrantivaError.networkError(let underlying) = error else {
                return XCTFail("Expected .networkError, got \(error)")
            }
            XCTAssertTrue(underlying is DecodingError)
        }
    }

    // MARK: - refreshWithAssertion

    private func makeRefreshRequest() -> AssertionRefreshRequest {
        AssertionRefreshRequest(
            keyId: "KEY-1",
            assertion: "b64-assertion",
            clientDataHash: "b64-hash",
            challenge: "challenge-value",
            subjectId: "subject-1"
        )
    }

    func testRefreshWithAssertionDecodesSuccessResponse() async throws {
        StubURLProtocol.enqueue(.json(#"{"token":"new.jwt","expiresAt":"2026-02-01T00:00:00Z"}"#))

        let response = try await makeClient().refreshWithAssertion(makeRefreshRequest())

        XCTAssertEqual(response.token, "new.jwt")
        XCTAssertEqual(response.expiresAt, "2026-02-01T00:00:00Z")

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url?.absoluteString, "\(baseURL)/api/v1/attestation/refresh")
        XCTAssertEqual(request.bodyJSON?["subjectId"] as? String, "subject-1")
    }

    /// 409 is the backend telling the SDK to self-heal by re-attesting; it must not
    /// be flattened into the generic `.validationFailed`.
    func testRefreshWithAssertion409MapsToReattestRequired() async {
        StubURLProtocol.enqueue(.status(409))

        do {
            _ = try await makeClient().refreshWithAssertion(makeRefreshRequest())
            XCTFail("Expected a thrown error")
        } catch {
            guard case GrantivaError.reattestRequired = error else {
                return XCTFail("Expected .reattestRequired, got \(error)")
            }
        }
    }

    func testRefreshWithAssertionOtherFailuresMapToValidationFailed() async {
        for status in [400, 401, 403, 500] {
            StubURLProtocol.reset()
            StubURLProtocol.enqueue(.status(status))
            do {
                _ = try await makeClient().refreshWithAssertion(makeRefreshRequest())
                XCTFail("Expected a thrown error for \(status)")
            } catch {
                guard case GrantivaError.validationFailed = error else {
                    return XCTFail("Expected .validationFailed for \(status), got \(error)")
                }
            }
        }
    }

    func testRefreshWithAssertionTransportFailureMapsToNetworkError() async {
        StubURLProtocol.enqueue(.failure(URLError(.networkConnectionLost)))

        do {
            _ = try await makeClient().refreshWithAssertion(makeRefreshRequest())
            XCTFail("Expected a thrown error")
        } catch {
            guard case GrantivaError.networkError = error else {
                return XCTFail("Expected .networkError, got \(error)")
            }
        }
    }

    // MARK: - parseServerError edge cases

    func testParseServerErrorEmptyReasonFallsBackToValidationFailed() {
        let client = makeClient()
        let result = client.parseServerError(from: Data(#"{"error":true,"reason":""}"#.utf8), statusCode: 400)
        guard case .validationFailed = result else {
            return XCTFail("An empty reason must not produce an empty .serverError message, got \(result)")
        }
    }

    func testParseServerError429NonLimitBodyStillReadsVaporReason() {
        let client = makeClient()
        let result = client.parseServerError(from: Data(#"{"error":true,"reason":"slow down"}"#.utf8), statusCode: 429)
        guard case .serverError(let reason) = result else {
            return XCTFail("Expected .serverError, got \(result)")
        }
        XCTAssertEqual(reason, "slow down")
    }

    func testParseServerError3xxFallsBackToValidationFailed() {
        let client = makeClient()
        guard case .validationFailed = client.parseServerError(from: Data(), statusCode: 302) else {
            return XCTFail("Expected .validationFailed for a non-4xx status")
        }
    }
}
