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
}
