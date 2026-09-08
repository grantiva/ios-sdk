import XCTest
@testable import Grantiva

final class FlagTargetingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        StubURLProtocol.setFallback(.json(#"{"flags":{"premium":true}}"#))
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func service(identity: IdentityProvider) -> FlagService {
        FlagService(apiClient: FlagAPIClient(
            configuration: GrantivaConfiguration(baseURL: "https://test.grantiva.invalid", apiKey: "test-key"),
            teamId: "TEAM", session: StubURLProtocol.makeSession()
        ), identity: identity)
    }

    func testRequestsCarryUserDeviceAndCustomTargeting() async throws {
        let identity = IdentityProvider()
        identity.identify(UserContext(userId: "alice", properties: ["plan": "premium", "country": "US"]))
        let flags = service(identity: identity)
        _ = try await flags.getFlags()
        let request = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(request.header("X-User-ID"), "alice")
        XCTAssertEqual(request.header("X-Custom-plan"), "premium")
        XCTAssertEqual(request.header("X-Country"), "US")
        XCTAssertEqual(request.header("X-Device-ID"), identity.deviceHash)
        XCTAssertNotNil(request.header("X-Device-Model"))
        XCTAssertNotNil(request.header("X-App-Version"))
        XCTAssertNotNil(request.header("X-OS-Version"))
        XCTAssertEqual(request.header("Authorization"), "Bearer test-key")
    }

    func testIdentityClearRemovesUserTargetingFromNextRequest() async throws {
        let identity = IdentityProvider()
        identity.identify(UserContext(userId: "alice", properties: ["plan": "premium"]))
        let flags = service(identity: identity)
        _ = try await flags.getFlags()
        identity.clearIdentity()
        await flags.clearCache()
        _ = try await flags.getFlags()
        let request = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertNil(request.header("X-User-ID"))
        XCTAssertNil(request.header("X-Custom-plan"))
        XCTAssertEqual(request.header("X-Device-ID"), identity.deviceHash)
    }

    func testStreamInvalidationReevaluatesCurrentUserInsteadOfCachingDefaults() async throws {
        let identity = IdentityProvider()
        let flags = service(identity: identity)
        _ = try await flags.getFlags()
        identity.identify(UserContext(userId: "bob"))
        StubURLProtocol.setFallback(.json(#"{"flags":{"premium":false}}"#))
        await flags.refreshAfterSSEUpdate()
        let result = try await flags.getFlags()
        XCTAssertEqual(result["premium"]?.boolValue, false)
        XCTAssertEqual(StubURLProtocol.requestCount, 2)
        XCTAssertEqual(StubURLProtocol.requests.last?.header("X-User-ID"), "bob")
    }

    func testMalformedCustomPropertiesCannotInjectHTTPHeaders() async throws {
        let identity = IdentityProvider()
        identity.identify(UserContext(userId: "alice", properties: [
            "bad\r\nInjected": "value", "plan": "premium\r\nInjected: true"
        ]))
        _ = try await service(identity: identity).getFlags()
        let request = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertNil(request.header("Injected"))
        XCTAssertNil(request.header("X-Custom-plan"))
        XCTAssertEqual(request.header("X-User-ID"), "alice")
    }

    func testOldUserResponseCannotOverwriteNewUserEvaluation() async throws {
        let identity = IdentityProvider()
        identity.identify(UserContext(userId: "alice"))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HeldFlagProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let flags = FlagService(apiClient: FlagAPIClient(
            configuration: GrantivaConfiguration(baseURL: "https://test.grantiva.invalid", apiKey: "key"),
            teamId: "TEAM", session: session
        ), identity: identity)
        let oldRequest = Task { await flags.refreshAfterSSEUpdate() }
        defer { HeldFlagProtocol.releaseAlice() }
        for _ in 0..<200 {
            if HeldFlagProtocol.hasAlice { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(HeldFlagProtocol.hasAlice)
        identity.identify(UserContext(userId: "bob"))
        await flags.refreshAfterSSEUpdate()
        HeldFlagProtocol.releaseAlice()
        await oldRequest.value
        let result = try await flags.getFlags()
        XCTAssertEqual(result["premium"]?.boolValue, false,
                       "Alice's delayed response must not replace Bob's evaluated flags")
    }
}

private final class HeldFlagProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var alice: HeldFlagProtocol?
    static var hasAlice: Bool { lock.withLock { alice != nil } }

    static func releaseAlice() {
        let held = lock.withLock { let held = alice; alice = nil; return held }
        held?.finish(premium: true)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.value(forHTTPHeaderField: "X-User-ID") == "alice" {
            Self.lock.withLock { Self.alice = self }
        } else {
            finish(premium: false)
        }
    }
    override func stopLoading() {}

    private func finish(premium: Bool) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"flags\":{\"premium\":\(premium)}}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
