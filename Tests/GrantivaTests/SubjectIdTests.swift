import XCTest
@testable import Grantiva

/// Tests for the entitlement sharing-unit id (`subjectId`) that links a device to its `Subject`
/// server-side so the attestation JWT carries `custom_claims.subscription`.
final class SubjectIdTests: XCTestCase {

    func testIdentityProviderStoresAndClearsSubjectId() {
        let identity = IdentityProvider()
        XCTAssertNil(identity.subjectId)

        identity.setSubjectId("fam-123")
        XCTAssertEqual(identity.subjectId, "fam-123")

        identity.setSubjectId(nil)
        XCTAssertNil(identity.subjectId)
    }

    func testSubjectIdIsIndependentOfUserIdentity() {
        let identity = IdentityProvider()
        identity.setSubjectId("fam-123")
        identity.identify(UserContext(userId: "user-789"))
        // The sharing unit and the individual user are distinct concepts.
        XCTAssertEqual(identity.subjectId, "fam-123")
        XCTAssertEqual(identity.userId, "user-789")

        identity.clearIdentity()
        XCTAssertNil(identity.userId)
        XCTAssertEqual(identity.subjectId, "fam-123", "clearing user identity must not clear the subject id")
    }

    func testAttestationRequestEncodesSubjectId() throws {
        let request = AttestationRequest(
            bundleId: "family.kin.com", teamId: "74F766FUVU", keyId: "key-1",
            attestationObject: "obj", clientDataHash: "hash", challenge: "chal",
            deviceModel: nil, osVersion: nil, appVersion: nil, appBuildNumber: nil,
            platform: "iOS", deviceFingerprint: nil, subjectId: "fam-123"
        )
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        XCTAssertEqual(json?["subjectId"] as? String, "fam-123")
    }

    func testAttestationRequestOmitsSubjectIdWhenNil() throws {
        let request = AttestationRequest(
            bundleId: "family.kin.com", teamId: "74F766FUVU", keyId: "key-1",
            attestationObject: "obj", clientDataHash: "hash", challenge: "chal",
            deviceModel: nil, osVersion: nil, appVersion: nil, appBuildNumber: nil,
            platform: "iOS", deviceFingerprint: nil, subjectId: nil
        )
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        XCTAssertNil(json?["subjectId"], "nil subjectId should not be encoded")
    }

    func testAssertionRefreshRequestEncodesSubjectId() throws {
        let request = AssertionRefreshRequest(
            keyId: "key-1", assertion: "a", clientDataHash: "h", challenge: "c", subjectId: "fam-123"
        )
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        XCTAssertEqual(json?["subjectId"] as? String, "fam-123")
    }
}
