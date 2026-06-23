import XCTest
@testable import Grantiva

final class GrantivaPushTests: XCTestCase {

    // MARK: - Token registration on the Grantiva facade

    func testSetPushTokenFromDataConvertsToLowercaseHex() {
        let grantiva = Grantiva(teamId: "TEAM123")
        XCTAssertNil(grantiva.pushToken)

        // 0x00 0xab 0xff 0x10 → "00abff10"
        let data = Data([0x00, 0xab, 0xff, 0x10])
        grantiva.setPushToken(data, environment: .sandbox)

        XCTAssertEqual(grantiva.pushToken, "00abff10")
    }

    func testSetPushTokenFromStringNormalizes() {
        let grantiva = Grantiva(teamId: "TEAM123")
        grantiva.setPushToken("  AABBCCDD  ", environment: .production)
        XCTAssertEqual(grantiva.pushToken, "aabbccdd")
    }

    func testSetPushTokenIgnoresEmptyToken() {
        let grantiva = Grantiva(teamId: "TEAM123")
        grantiva.setPushToken("   ", environment: .sandbox)
        XCTAssertNil(grantiva.pushToken)
    }

    func testClearPushToken() {
        let grantiva = Grantiva(teamId: "TEAM123")
        grantiva.setPushToken("aabb", environment: .sandbox)
        XCTAssertNotNil(grantiva.pushToken)

        grantiva.clearPushToken()
        XCTAssertNil(grantiva.pushToken)
    }

    // MARK: - PushEnvironment

    func testPushEnvironmentRawValuesMatchServerContract() {
        // The backend's `pushEnvironment` field accepts exactly these strings.
        XCTAssertEqual(PushEnvironment.sandbox.rawValue, "sandbox")
        XCTAssertEqual(PushEnvironment.production.rawValue, "production")
    }

    func testPushEnvironmentDetectedReturnsAValue() {
        // No provisioning profile in the test bundle, so this falls back to the build
        // configuration. Just assert it resolves to one of the two valid cases.
        let detected = PushEnvironment.detected
        XCTAssertTrue(detected == .sandbox || detected == .production)
    }

    // MARK: - PushTokenStore

    func testPushTokenStoreSetAndClear() {
        let store = PushTokenStore()
        XCTAssertNil(store.token)
        XCTAssertNil(store.environment)

        store.set(token: "deadbeef", environment: .production)
        XCTAssertEqual(store.token, "deadbeef")
        XCTAssertEqual(store.environment, .production)

        store.clear()
        XCTAssertNil(store.token)
        XCTAssertNil(store.environment)
    }

    // MARK: - Wire format

    func testCreateFeatureRequestBodyOmitsPushFieldsWhenNil() throws {
        let body = CreateFeatureRequestBody(
            title: "t", description: "d", submitterId: "s", deviceHash: "h",
            pushToken: nil, pushEnvironment: nil
        )
        let json = try jsonObject(body)
        // Optionals synthesize `encodeIfPresent`, so nil fields must not appear —
        // keeps requests byte-for-byte compatible with pre-push clients.
        XCTAssertNil(json["pushToken"])
        XCTAssertNil(json["pushEnvironment"])
    }

    func testCreateFeatureRequestBodyUsesCamelCaseKeys() throws {
        let body = CreateFeatureRequestBody(
            title: "t", description: "d", submitterId: "s", deviceHash: "h",
            pushToken: "aabb", pushEnvironment: "sandbox"
        )
        let json = try jsonObject(body)
        // Server uses the default JSONDecoder (no snake_case strategy) — keys must be
        // exactly `pushToken` / `pushEnvironment`.
        XCTAssertEqual(json["pushToken"] as? String, "aabb")
        XCTAssertEqual(json["pushEnvironment"] as? String, "sandbox")
    }

    func testCreateCommentBodyCarriesPushFields() throws {
        let body = CreateCommentBody(authorId: "a", body: "hi", pushToken: "ff00", pushEnvironment: "production")
        let json = try jsonObject(body)
        XCTAssertEqual(json["pushToken"] as? String, "ff00")
        XCTAssertEqual(json["pushEnvironment"] as? String, "production")
    }

    // MARK: - Helpers

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
