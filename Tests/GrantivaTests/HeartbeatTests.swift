import XCTest
@testable import Grantiva

/// Tests for `HeartbeatAPIClient` and `HeartbeatManager`.
///
/// The manager's 120s production interval is overridden through the internal
/// `interval:` init parameter so scheduling can be observed in milliseconds.
final class HeartbeatTests: XCTestCase {

    private let baseURL = "https://test.grantiva.invalid"

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeAPIClient(apiKey: String? = nil, teamId: String = "TEAM123") -> HeartbeatAPIClient {
        HeartbeatAPIClient(
            configuration: GrantivaConfiguration(baseURL: baseURL, apiKey: apiKey),
            teamId: teamId,
            session: StubURLProtocol.makeSession()
        )
    }

    /// Polls until `condition` holds or the deadline passes. Returns whether it held.
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

    // MARK: - HeartbeatAPIClient

    func testHeartbeatPostsToTheHeartbeatEndpoint() async throws {
        StubURLProtocol.enqueue(.status(200))

        try await makeAPIClient().sendHeartbeat(token: "jwt", deviceId: "device-1", appState: "active")

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url?.absoluteString, "\(baseURL)/api/v1/heartbeat")
        XCTAssertEqual(request.header("Content-Type"), "application/json")
    }

    /// Unlike `GrantivaAPIClient`, the heartbeat endpoint always carries the tenant
    /// headers for app scoping, in addition to whatever auth is available.
    func testHeartbeatAlwaysSendsTenantHeaders() async throws {
        StubURLProtocol.enqueue(.status(200))

        try await makeAPIClient(apiKey: "gdev_secret", teamId: "TEAM777")
            .sendHeartbeat(token: "jwt", deviceId: nil, appState: nil)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertNotNil(request.header("X-Bundle-ID"))
        XCTAssertEqual(request.header("X-Team-ID"), "TEAM777")
    }

    func testHeartbeatPrefersTheAttestationJWTOverTheAPIKey() async throws {
        StubURLProtocol.enqueue(.status(200))

        try await makeAPIClient(apiKey: "gdev_secret")
            .sendHeartbeat(token: "jwt-token", deviceId: nil, appState: nil)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.header("Authorization"), "Bearer jwt-token", "the JWT must win over the API key")
    }

    func testHeartbeatFallsBackToTheAPIKeyWhenThereIsNoToken() async throws {
        StubURLProtocol.enqueue(.status(200))

        try await makeAPIClient(apiKey: "gdev_secret")
            .sendHeartbeat(token: nil, deviceId: "device-1", appState: nil)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.header("Authorization"), "Bearer gdev_secret")
    }

    func testHeartbeatSendsNoAuthorizationWhenNeitherIsAvailable() async throws {
        StubURLProtocol.enqueue(.status(200))

        try await makeAPIClient().sendHeartbeat(token: nil, deviceId: nil, appState: nil)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertNil(request.header("Authorization"))
    }

    func testHeartbeatBodyCarriesStateDeviceIdAndSDKVersion() async throws {
        StubURLProtocol.enqueue(.status(200))

        try await makeAPIClient().sendHeartbeat(token: "jwt", deviceId: "device-42", appState: "background")

        let body = try XCTUnwrap(StubURLProtocol.requests.first?.bodyJSON)
        XCTAssertEqual(body["appState"] as? String, "background")
        XCTAssertEqual(body["deviceId"] as? String, "device-42")
        XCTAssertNotNil(body["sdkVersion"])
    }

    func testHeartbeatOmitsNilBodyFields() async throws {
        StubURLProtocol.enqueue(.status(200))

        try await makeAPIClient().sendHeartbeat(token: "jwt", deviceId: nil, appState: nil)

        let body = try XCTUnwrap(StubURLProtocol.requests.first?.bodyJSON)
        XCTAssertNil(body["deviceId"])
        XCTAssertNil(body["appState"])
    }

    func testHeartbeatAcceptsAny2xx() async throws {
        for status in [200, 201, 202, 204] {
            StubURLProtocol.reset()
            StubURLProtocol.enqueue(.status(status))
            try await makeAPIClient().sendHeartbeat(token: "jwt", deviceId: nil, appState: nil)
        }
    }

    // These two use the fallback stub rather than the queue: a heartbeat still in
    // flight from the interval tests above can drain a queued stub after its own
    // test has returned, and then the request under test sees the default 200.
    func testHeartbeatThrowsNetworkErrorCarryingTheStatusCode() async {
        StubURLProtocol.setFallback(.status(401))

        do {
            try await makeAPIClient().sendHeartbeat(token: "jwt", deviceId: nil, appState: nil)
            XCTFail("Expected a thrown error for 401")
        } catch {
            guard case GrantivaError.networkError(let underlying) = error else {
                return XCTFail("Expected .networkError, got \(error)")
            }
            XCTAssertEqual((underlying as NSError).code, 401)
        }
    }

    func testHeartbeatThrowsOn5xx() async {
        StubURLProtocol.setFallback(.status(503))

        do {
            try await makeAPIClient().sendHeartbeat(token: "jwt", deviceId: nil, appState: nil)
            XCTFail("Expected a thrown error for 503")
        } catch {
            // expected
        }
    }

    // MARK: - HeartbeatManager

    private func makeManager(
        interval: TimeInterval,
        token: String? = "jwt",
        deviceId: String? = "device-1"
    ) -> HeartbeatManager {
        HeartbeatManager(
            apiClient: makeAPIClient(),
            getToken: { token },
            getDeviceId: { deviceId },
            interval: interval
        )
    }

    func testStartSendsAHeartbeatImmediately() async {
        StubURLProtocol.setFallback(.status(200))
        let manager = makeManager(interval: 60) // never reached within the test window
        defer { manager.stop() }

        manager.start()

        let fired = await waitUntil { StubURLProtocol.requestCount >= 1 }
        XCTAssertTrue(fired, "start() must send the first heartbeat without waiting for the interval")
    }

    func testHeartbeatsRepeatOnTheConfiguredInterval() async {
        StubURLProtocol.setFallback(.status(200))
        let manager = makeManager(interval: 0.02)
        defer { manager.stop() }

        manager.start()

        let repeated = await waitUntil { StubURLProtocol.requestCount >= 3 }
        XCTAssertTrue(repeated, "expected repeated heartbeats, saw \(StubURLProtocol.requestCount)")
    }

    func testStopCancelsScheduledHeartbeats() async {
        StubURLProtocol.setFallback(.status(200))
        let manager = makeManager(interval: 0.02)

        manager.start()
        _ = await waitUntil { StubURLProtocol.requestCount >= 2 }
        manager.stop()

        // A request already in flight when stop() lands may still complete, and that is
        // not the behaviour under test — what must not happen is a *new* heartbeat being
        // scheduled afterwards. Let in-flight work drain before taking the baseline;
        // reading it immediately after stop() races that request and fails on slower
        // machines (observed on CI: 3 != 2).
        try? await Task.sleep(for: .milliseconds(200))
        let countAfterDrain = StubURLProtocol.requestCount

        // 300ms spans ~15 intervals, so any continued scheduling shows up here.
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(
            StubURLProtocol.requestCount, countAfterDrain,
            "no heartbeat may be scheduled after stop()"
        )
    }

    func testStopBeforeStartIsSafe() async {
        StubURLProtocol.setFallback(.status(200))
        let manager = makeManager(interval: 0.02)

        manager.stop() // must not trap
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(StubURLProtocol.requestCount, 0)
    }

    func testCallingStartTwiceDoesNotDoubleSchedule() async {
        StubURLProtocol.setFallback(.status(200))
        let manager = makeManager(interval: 60) // only the immediate heartbeat can fire
        defer { manager.stop() }

        manager.start()
        manager.start()

        _ = await waitUntil { StubURLProtocol.requestCount >= 1 }
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(StubURLProtocol.requestCount, 1, "a second start() must not spawn a second timer task")
    }

    func testRestartAfterStopResumesHeartbeats() async {
        StubURLProtocol.setFallback(.status(200))
        let manager = makeManager(interval: 60)
        defer { manager.stop() }

        manager.start()
        _ = await waitUntil { StubURLProtocol.requestCount >= 1 }
        manager.stop()
        manager.start()

        let resumed = await waitUntil { StubURLProtocol.requestCount >= 2 }
        XCTAssertTrue(resumed, "stop() must leave the manager restartable")
    }

    /// Heartbeats are fire-and-forget: a failing server must not stop the loop or
    /// surface an error to the app.
    func testServerFailuresDoNotStopTheHeartbeatLoop() async {
        StubURLProtocol.setFallback(.status(500))
        let manager = makeManager(interval: 0.02)
        defer { manager.stop() }

        manager.start()

        let keptGoing = await waitUntil { StubURLProtocol.requestCount >= 3 }
        XCTAssertTrue(keptGoing, "failed heartbeats must be swallowed and the loop continue")
    }

    func testTransportFailuresDoNotStopTheHeartbeatLoop() async {
        StubURLProtocol.setFallback(.failure(URLError(.notConnectedToInternet)))
        let manager = makeManager(interval: 0.02)
        defer { manager.stop() }

        manager.start()

        let keptGoing = await waitUntil { StubURLProtocol.requestCount >= 3 }
        XCTAssertTrue(keptGoing, "offline devices must keep retrying on the next interval")
    }

    func testManagerReadsTokenAndDeviceIdLazilyAtSendTime() async throws {
        StubURLProtocol.setFallback(.status(200))
        let box = TokenBox()
        let manager = HeartbeatManager(
            apiClient: makeAPIClient(),
            getToken: { box.token },
            getDeviceId: { "device-1" },
            interval: 0.02
        )
        defer { manager.stop() }

        box.token = "first-token"
        manager.start()
        _ = await waitUntil { StubURLProtocol.requestCount >= 1 }

        // A token refresh mid-flight must be picked up by the next heartbeat.
        box.token = "second-token"
        let sawRotated = await waitUntil {
            StubURLProtocol.requests.contains { $0.header("Authorization") == "Bearer second-token" }
        }
        XCTAssertTrue(sawRotated, "the manager must re-read the token on every beat, not capture it once")
    }

    /// Minimal mutable holder for the closure-injection test.
    private final class TokenBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _token: String?
        var token: String? {
            get { lock.lock(); defer { lock.unlock() }; return _token }
            set { lock.lock(); defer { lock.unlock() }; _token = newValue }
        }
    }
}
