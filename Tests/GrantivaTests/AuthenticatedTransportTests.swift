import XCTest
@testable import Grantiva

/// Covers the request plumbing shared by the feedback, flag and what's-new clients:
/// tenant headers, credential precedence, and renewing an expired or rejected JWT
/// instead of sending a token the server will reject.
final class AuthenticatedTransportTests: XCTestCase {

    private let baseURL = "https://test.grantiva.invalid"

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeTransport(
        apiKey: String? = nil,
        token: Box<String?>,
        refreshToken: (@Sendable () async -> Bool)? = nil
    ) -> AuthenticatedTransport {
        AuthenticatedTransport(
            configuration: GrantivaConfiguration(baseURL: baseURL, apiKey: apiKey),
            teamId: "TEAM123",
            getToken: { token.value },
            refreshToken: refreshToken,
            session: StubURLProtocol.makeSession()
        )
    }

    private func get(_ transport: AuthenticatedTransport) async throws -> Data {
        try await transport.send(transport.request(url: URL(string: "\(baseURL)/api/v1/thing")!, method: "GET"))
    }

    // MARK: - Headers and credentials

    func testAlwaysSendsTenantHeaders() async throws {
        StubURLProtocol.enqueue(.status(200))
        _ = try await get(makeTransport(token: Box("jwt")))

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertNotNil(request.header("X-Bundle-ID"))
        XCTAssertEqual(request.header("X-Team-ID"), "TEAM123")
        XCTAssertEqual(request.header("Content-Type"), "application/json")
    }

    func testJWTWinsOverAPIKey() async throws {
        StubURLProtocol.enqueue(.status(200))
        _ = try await get(makeTransport(apiKey: "gdev_key", token: Box("jwt")))
        XCTAssertEqual(StubURLProtocol.requests.first?.header("Authorization"), "Bearer jwt")
    }

    func testFallsBackToAPIKeyWithoutAToken() async throws {
        StubURLProtocol.enqueue(.status(200))
        _ = try await get(makeTransport(apiKey: "gdev_key", token: Box(nil)))
        XCTAssertEqual(StubURLProtocol.requests.first?.header("Authorization"), "Bearer gdev_key")
    }

    // MARK: - Expired token

    func testRefreshesAnExpiredTokenBeforeSending() async throws {
        StubURLProtocol.enqueue(.status(200))
        let token = Box<String?>(nil)
        let refreshes = Counter()

        _ = try await get(makeTransport(token: token, refreshToken: {
            refreshes.increment()
            token.value = "fresh-jwt"
            return true
        }))

        XCTAssertEqual(refreshes.value, 1)
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
        XCTAssertEqual(StubURLProtocol.requests.first?.header("Authorization"), "Bearer fresh-jwt")
    }

    func testSendsWithoutAuthWhenRefreshFails() async throws {
        // The server decides what an unauthenticated request means; the SDK does
        // not pre-empt it, so an app with neither credential still gets a real answer.
        StubURLProtocol.enqueue(.status(200))
        _ = try await get(makeTransport(token: Box(nil), refreshToken: { false }))
        XCTAssertNil(StubURLProtocol.requests.first?.header("Authorization"))
    }

    // MARK: - 401 recovery

    func testRefreshesOnceAndRetriesAfter401() async throws {
        StubURLProtocol.enqueue(.status(401))
        StubURLProtocol.enqueue(.json(#"{"ok":true}"#))
        let token = Box<String?>("stale-jwt")
        let refreshes = Counter()

        let data = try await get(makeTransport(token: token, refreshToken: {
            refreshes.increment()
            token.value = "fresh-jwt"
            return true
        }))

        XCTAssertEqual(refreshes.value, 1)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"ok":true}"#)
        XCTAssertEqual(
            StubURLProtocol.requests.map { $0.header("Authorization") },
            ["Bearer stale-jwt", "Bearer fresh-jwt"]
        )
    }

    func testRetriesAtMostOnceAfter401() async {
        StubURLProtocol.setFallback(.status(401))
        let refreshes = Counter()

        do {
            _ = try await get(makeTransport(token: Box("jwt"), refreshToken: {
                refreshes.increment()
                return true
            }))
            XCTFail("Expected validationFailed")
        } catch {
            guard case GrantivaError.validationFailed = error else {
                return XCTFail("Expected .validationFailed, got \(error)")
            }
        }
        XCTAssertEqual(refreshes.value, 1)
        XCTAssertEqual(StubURLProtocol.requestCount, 2, "one retry, never a 401 storm")
    }

    func testGivesUpAfter401WhenRefreshIsUnavailable() async {
        StubURLProtocol.enqueue(.status(401))

        do {
            _ = try await get(makeTransport(apiKey: "gdev_key", token: Box(nil)))
            XCTFail("Expected validationFailed")
        } catch {
            guard case GrantivaError.validationFailed = error else {
                return XCTFail("Expected .validationFailed, got \(error)")
            }
        }
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    // MARK: - Status mapping

    func testMaps429ToRateLimited() async {
        StubURLProtocol.enqueue(.status(429))
        do {
            _ = try await get(makeTransport(token: Box("jwt")))
            XCTFail("Expected rateLimited")
        } catch {
            guard case GrantivaError.rateLimited = error else {
                return XCTFail("Expected .rateLimited, got \(error)")
            }
        }
    }

    func testMapsOtherStatusesToNetworkErrorCarryingTheCode() async {
        StubURLProtocol.enqueue(.json(#"{"error":true,"reason":"nope"}"#, status: 503))
        do {
            _ = try await get(makeTransport(token: Box("jwt")))
            XCTFail("Expected networkError")
        } catch {
            guard case GrantivaError.networkError(let underlying) = error else {
                return XCTFail("Expected .networkError, got \(error)")
            }
            XCTAssertEqual((underlying as NSError).code, 503)
        }
    }

    func testWrapsTransportFailures() async {
        StubURLProtocol.enqueue(.failure(URLError(.notConnectedToInternet)))
        do {
            _ = try await get(makeTransport(token: Box("jwt")))
            XCTFail("Expected networkError")
        } catch {
            guard case GrantivaError.networkError(let underlying) = error else {
                return XCTFail("Expected .networkError, got \(error)")
            }
            XCTAssertEqual((underlying as? URLError)?.code, .notConnectedToInternet)
        }
    }

    func testNonHTTPResponseIsInvalidResponse() async {
        StubURLProtocol.enqueue(.nonHTTPResponse)
        do {
            _ = try await get(makeTransport(token: Box("jwt")))
            XCTFail("Expected invalidResponse")
        } catch {
            guard case GrantivaError.invalidResponse = error else {
                return XCTFail("Expected .invalidResponse, got \(error)")
            }
        }
    }

    // MARK: - Feature clients ride the transport

    func testFeedbackClientRefreshesAnExpiredTokenBeforeListing() async throws {
        StubURLProtocol.enqueue(.json(#"{"items":[],"metadata":{"page":1,"per":20,"total":0}}"#))
        let token = Box<String?>(nil)
        let client = FeedbackAPIClient(
            configuration: GrantivaConfiguration(baseURL: baseURL),
            teamId: "TEAM123",
            getToken: { token.value },
            refreshToken: { token.value = "fresh-jwt"; return true },
            session: StubURLProtocol.makeSession()
        )

        let items = try await client.listFeatureRequests(voterId: nil)

        XCTAssertTrue(items.isEmpty)
        XCTAssertEqual(StubURLProtocol.requests.first?.header("Authorization"), "Bearer fresh-jwt")
    }

    func testFlagClientRefreshesAnExpiredTokenBeforeFetching() async throws {
        StubURLProtocol.enqueue(.json(#"{"flags":{"dark_mode":true}}"#))
        let token = Box<String?>(nil)
        let client = FlagAPIClient(
            configuration: GrantivaConfiguration(baseURL: baseURL),
            teamId: "TEAM123",
            getToken: { token.value },
            refreshToken: { token.value = "fresh-jwt"; return true },
            session: StubURLProtocol.makeSession()
        )

        let flags = try await client.fetchFlags(environment: .production)

        XCTAssertEqual(flags["dark_mode"]?.boolValue, true)
        XCTAssertEqual(StubURLProtocol.requests.first?.header("Authorization"), "Bearer fresh-jwt")
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.query, "environment=production")
    }
}

// MARK: - Test Utilities

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.withLock { _value } }
    func increment() { lock.withLock { _value += 1 } }
}
