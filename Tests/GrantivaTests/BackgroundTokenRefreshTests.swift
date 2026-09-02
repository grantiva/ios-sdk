import XCTest
@testable import Grantiva

/// Covers how the heartbeat and flag stream behave when the stored JWT has expired
/// or the server rejects it: they renew the token through the refresh hook instead
/// of retrying a dead token until the host app happens to re-attest.
final class BackgroundTokenRefreshTests: XCTestCase {

    private let baseURL = "https://test.grantiva.invalid"

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    @discardableResult
    private func waitUntil(
        timeout: TimeInterval = 2.0,
        _ condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    // MARK: - TokenRefreshCoordinator

    func testConcurrentRefreshesRunTheOperationOnce() async {
        let coordinator = TokenRefreshCoordinator()
        let runs = Counter()

        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<5 {
                group.addTask {
                    await coordinator.refresh {
                        runs.increment()
                        try? await Task.sleep(for: .milliseconds(100))
                        return true
                    }
                }
            }
            var collected: [Bool] = []
            for await result in group { collected.append(result) }
            return collected
        }

        XCTAssertEqual(runs.value, 1, "callers arriving mid-refresh must share the in-flight result")
        XCTAssertEqual(results, [true, true, true, true, true])
    }

    func testSequentialRefreshesRunAgain() async {
        let coordinator = TokenRefreshCoordinator()
        let runs = Counter()

        let first = await coordinator.refresh { runs.increment(); return false }
        let second = await coordinator.refresh { runs.increment(); return true }

        XCTAssertFalse(first)
        XCTAssertTrue(second)
        XCTAssertEqual(runs.value, 2)
    }

    // MARK: - Heartbeat

    private func makeHeartbeat(
        apiKey: String? = nil,
        token: Box<String?>,
        refreshToken: (() async -> Bool)?
    ) -> HeartbeatManager {
        HeartbeatManager(
            apiClient: HeartbeatAPIClient(
                configuration: GrantivaConfiguration(baseURL: baseURL, apiKey: apiKey),
                teamId: "TEAM123",
                session: StubURLProtocol.makeSession()
            ),
            getToken: { token.value },
            getDeviceId: { nil },
            refreshToken: refreshToken,
            interval: 3600
        )
    }

    func testHeartbeatRefreshesAnExpiredTokenBeforeSending() async throws {
        StubURLProtocol.enqueue(.status(200))
        let token = Box<String?>(nil)
        let refreshes = Counter()

        let manager = makeHeartbeat(token: token, refreshToken: {
            refreshes.increment()
            token.value = "fresh-jwt"
            return true
        })
        manager.start()
        defer { manager.stop() }

        await waitUntil { StubURLProtocol.requestCount == 1 }
        XCTAssertEqual(refreshes.value, 1)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.header("Authorization"), "Bearer fresh-jwt")
    }

    func testHeartbeatIsSkippedWhenRefreshFails() async {
        let token = Box<String?>(nil)
        let refreshes = Counter()

        let manager = makeHeartbeat(token: token, refreshToken: {
            refreshes.increment()
            return false
        })
        manager.start()
        defer { manager.stop() }

        await waitUntil(timeout: 0.5) { refreshes.value == 1 }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(StubURLProtocol.requestCount, 0, "no beat should be sent with a dead token")
    }

    func testHeartbeatRefreshesOnceAndRetriesAfter401() async throws {
        StubURLProtocol.enqueue(.status(401))
        StubURLProtocol.enqueue(.status(200))
        let token = Box<String?>("stale-jwt")
        let refreshes = Counter()

        let manager = makeHeartbeat(token: token, refreshToken: {
            refreshes.increment()
            token.value = "fresh-jwt"
            return true
        })
        manager.start()
        defer { manager.stop() }

        await waitUntil { StubURLProtocol.requestCount == 2 }
        XCTAssertEqual(refreshes.value, 1)
        let headers = StubURLProtocol.requests.map { $0.header("Authorization") }
        XCTAssertEqual(headers, ["Bearer stale-jwt", "Bearer fresh-jwt"])
    }

    func testHeartbeatGivesUpAfter401WhenRefreshFails() async {
        StubURLProtocol.enqueue(.status(401))
        let token = Box<String?>("stale-jwt")

        let manager = makeHeartbeat(token: token, refreshToken: { false })
        manager.start()
        defer { manager.stop() }

        await waitUntil { StubURLProtocol.requestCount == 1 }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(StubURLProtocol.requestCount, 1, "must not retry a 401 without a new token")
    }

    func testHeartbeatWithoutRefreshHookFallsBackToTheAPIKey() async throws {
        StubURLProtocol.enqueue(.status(200))
        let token = Box<String?>(nil)

        let manager = makeHeartbeat(apiKey: "gdev_key", token: token, refreshToken: nil)
        manager.start()
        defer { manager.stop() }

        await waitUntil { StubURLProtocol.requestCount == 1 }
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.header("Authorization"), "Bearer gdev_key")
    }

    // MARK: - Flag stream

    private func makeStream(
        apiKey: String? = nil,
        token: Box<String?>,
        refreshToken: (@Sendable () async -> Bool)?
    ) -> FlagSSEClient {
        FlagSSEClient(
            configuration: GrantivaConfiguration(baseURL: baseURL, apiKey: apiKey),
            teamId: "TEAM123",
            environment: .production,
            getToken: { token.value },
            refreshToken: refreshToken,
            protocolClasses: [StubURLProtocol.self]
        )
    }

    func testStreamRefreshesAnExpiredTokenBeforeConnecting() async throws {
        StubURLProtocol.setFallback(.status(200))
        let token = Box<String?>(nil)
        let refreshes = Counter()

        let client = makeStream(token: token, refreshToken: {
            refreshes.increment()
            token.value = "fresh-jwt"
            return true
        })
        client.start()
        defer { client.stop() }

        await waitUntil { StubURLProtocol.requestCount >= 1 }
        XCTAssertEqual(refreshes.value, 1)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.header("Authorization"), "Bearer fresh-jwt")
    }

    func testStreamDoesNotConnectWhenRefreshFails() async {
        StubURLProtocol.setFallback(.status(200))
        let token = Box<String?>(nil)
        let refreshes = Counter()

        let client = makeStream(token: token, refreshToken: {
            refreshes.increment()
            return false
        })
        client.start()
        defer { client.stop() }

        await waitUntil(timeout: 0.5) { refreshes.value == 1 }
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(StubURLProtocol.requestCount, 0, "a known-dead token must not be sent to the server")
        XCTAssertEqual(refreshes.value, 1, "a failed refresh waits authRetryDelay before trying again")
    }

    func testStreamRefreshesAndReconnectsAfter401() async throws {
        StubURLProtocol.enqueue(.status(401))
        StubURLProtocol.setFallback(.status(200))
        let token = Box<String?>("stale-jwt")
        let refreshes = Counter()

        let client = makeStream(token: token, refreshToken: {
            refreshes.increment()
            token.value = "fresh-jwt"
            return true
        })
        client.start()
        defer { client.stop() }

        // Reconnect after a refreshed 401 uses the minimum backoff (1s).
        await waitUntil(timeout: 3.0) { StubURLProtocol.requestCount >= 2 }
        XCTAssertEqual(refreshes.value, 1)
        let headers = StubURLProtocol.requests.prefix(2).map { $0.header("Authorization") }
        XCTAssertEqual(headers, ["Bearer stale-jwt", "Bearer fresh-jwt"])
    }

    func testStreamBacksOffLongAfter401WithoutRefresh() async {
        StubURLProtocol.setFallback(.status(401))
        let token = Box<String?>(nil)

        let client = makeStream(apiKey: "gdev_key", token: token, refreshToken: nil)
        client.start()
        defer { client.stop() }

        await waitUntil { StubURLProtocol.requestCount == 1 }
        try? await Task.sleep(for: .milliseconds(1500))
        XCTAssertEqual(StubURLProtocol.requestCount, 1, "an unrecoverable 401 must wait authRetryDelay, not the 1s backoff")
    }

    func testAuthRetryDelayIsMuchLongerThanReconnectBackoff() {
        XCTAssertGreaterThanOrEqual(FlagSSEClient.authRetryDelay, 60)
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
