import XCTest
@testable import Grantiva

final class GrantivaTests: XCTestCase {
    
    func testDeviceCompatibilityCheck() {
        let isSupported = DeviceCompatibility.isDeviceSupported()
        
        #if targetEnvironment(simulator)
        XCTAssertFalse(isSupported, "App Attest should not be supported in simulator")
        #else
        #if os(iOS)
        if #available(iOS 14.0, *) {
            XCTAssertTrue(isSupported, "App Attest should be supported on iOS 14+")
        } else {
            XCTAssertFalse(isSupported, "App Attest should not be supported on iOS < 14")
        }
        #endif
        #endif
    }
    
    func testTokenManagerStorage() {
        let tokenManager = TokenManager()
        let testToken = "test.jwt.token"
        let expiresAt = Date().addingTimeInterval(3600)
        
        tokenManager.saveToken(testToken, expiresAt: expiresAt)
        
        let storedToken = tokenManager.getStoredToken()
        XCTAssertNotNil(storedToken)
        XCTAssertEqual(storedToken?.token, testToken)
        
        tokenManager.clearTokens()
        
        let clearedToken = tokenManager.getStoredToken()
        XCTAssertNil(clearedToken)
    }
    
    func testTokenExpiration() {
        let tokenManager = TokenManager()
        let pastDate = Date().addingTimeInterval(-3600)
        let futureDate = Date().addingTimeInterval(3600)
        
        XCTAssertTrue(tokenManager.isTokenExpired(pastDate))
        XCTAssertFalse(tokenManager.isTokenExpired(futureDate))
    }
    
    func testPlatformSupport() {
        let deviceId = PlatformSupport.getDeviceIdentifier()
        XCTAssertFalse(deviceId.isEmpty)
        
        let systemInfo = PlatformSupport.getSystemInfo()
        XCTAssertNotNil(systemInfo["platform"])
        XCTAssertNotNil(systemInfo["systemVersion"])
    }
    
    func testErrorHandling() {
        let error = GrantivaError.deviceNotSupported
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotNil(error.failureReason)
    }

    // MARK: - limitExceeded error

    func testLimitExceededErrorDescription() {
        let error = GrantivaError.limitExceeded(limit: 1000, current: 1001)
        XCTAssertEqual(
            error.errorDescription,
            "Monthly attestation limit reached (1001/1000 MAD). Upgrade at grantiva.io/upgrade."
        )
        XCTAssertNotNil(error.failureReason)
    }

    func testParseServerError_429_madLimitExceeded_returnsLimitExceeded() {
        let client = GrantivaAPIClient(teamId: "TEAM123")
        let body = """
        {"error":"mad_limit_exceeded","limit":1000,"current":1001}
        """.data(using: .utf8)!

        let result = client.parseServerError(from: body, statusCode: 429)

        if case .limitExceeded(let limit, let current) = result {
            XCTAssertEqual(limit, 1000)
            XCTAssertEqual(current, 1001)
        } else {
            XCTFail("Expected .limitExceeded, got \(result)")
        }
    }

    func testParseServerError_429_unknownBody_returnsValidationFailed() {
        let client = GrantivaAPIClient(teamId: "TEAM123")
        let body = Data() // empty body

        let result = client.parseServerError(from: body, statusCode: 429)

        if case .validationFailed = result {
            // correct — unknown 429 body falls back to validationFailed
        } else {
            XCTFail("Expected .validationFailed for unrecognised 429 body, got \(result)")
        }
    }

    func testParseServerError_4xx_returnsServerError() {
        let client = GrantivaAPIClient(teamId: "TEAM123")
        let body = """
        {"error":true,"reason":"No attestation found for key ID"}
        """.data(using: .utf8)!

        let result = client.parseServerError(from: body, statusCode: 404)

        if case .serverError(let reason) = result {
            XCTAssertEqual(reason, "No attestation found for key ID")
        } else {
            XCTFail("Expected .serverError, got \(result)")
        }
    }

    func testParseServerError_5xx_returnsValidationFailed() {
        let client = GrantivaAPIClient(teamId: "TEAM123")
        let result = client.parseServerError(from: Data(), statusCode: 500)
        if case .validationFailed = result { } else {
            XCTFail("Expected .validationFailed for 5xx, got \(result)")
        }
    }

    func testAssertionKeyInvalidErrorMessages() {
        let error = GrantivaError.assertionKeyInvalid
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotNil(error.failureReason)
    }

    // Regression test for the assertion-path self-heal: DCError invalidInput (2) and
    // invalidKey (3) from generateAssertion must map to `assertionKeyInvalid` so
    // validateAttestation() clears local key state and re-attests, instead of
    // surfacing a permanent `validationFailed` on every launch.
    func testAssertionErrorMappingTriggersSelfHeal() {
        let dcDomain = "com.apple.devicecheck.error"

        guard case .assertionKeyInvalid = AttestationManager.mapAssertionError(NSError(domain: dcDomain, code: 2)) else {
            return XCTFail("DCError invalidInput (2) should map to assertionKeyInvalid")
        }
        guard case .assertionKeyInvalid = AttestationManager.mapAssertionError(NSError(domain: dcDomain, code: 3)) else {
            return XCTFail("DCError invalidKey (3) should map to assertionKeyInvalid")
        }
    }

    func testAssertionErrorMappingLeavesTransientErrorsAlone() {
        let dcDomain = "com.apple.devicecheck.error"

        // serverUnavailable (4) is transient — re-attesting would burn the key for nothing,
        // so it surfaces as a network error the app can simply retry.
        guard case .networkError = AttestationManager.mapAssertionError(NSError(domain: dcDomain, code: 4)) else {
            return XCTFail("DCError serverUnavailable (4) should map to networkError")
        }
        // Same codes from a different domain (e.g. NSURLErrorDomain) must not trigger self-heal.
        guard case .validationFailed = AttestationManager.mapAssertionError(NSError(domain: NSURLErrorDomain, code: 2)) else {
            return XCTFail("Non-DeviceCheck domains should stay validationFailed")
        }
    }
    
    func testAttestationErrorMapping() {
        let dcDomain = "com.apple.devicecheck.error"

        guard case .keyAlreadyAttested = AttestationManager.mapAttestationError(NSError(domain: dcDomain, code: 2)) else {
            return XCTFail("DCError invalidInput (2) should map to keyAlreadyAttested")
        }
        guard case .networkError = AttestationManager.mapAttestationError(NSError(domain: dcDomain, code: 4)) else {
            return XCTFail("DCError serverUnavailable (4) should map to networkError")
        }
        guard case .validationFailed = AttestationManager.mapAttestationError(NSError(domain: dcDomain, code: 3)) else {
            return XCTFail("DCError invalidKey (3) should stay validationFailed")
        }
        guard case .validationFailed = AttestationManager.mapAttestationError(NSError(domain: NSURLErrorDomain, code: 2)) else {
            return XCTFail("Non-DeviceCheck domains should stay validationFailed")
        }
    }

    func testDeviceIntelligenceExtraction() {
        let response = DeviceIntelligenceResponse(
            deviceId: "dev-1",
            riskScore: 42,
            riskCategory: "suspicious",
            deviceIntegrity: "verified",
            jailbreakDetected: false,
            attestationCount: 3,
            lastAttestationDate: "2026-06-01T12:00:00Z"
        )
        let intelligence = DeviceIntelligenceExtractor.extractFromResponse(response)
        XCTAssertEqual(intelligence.deviceId, "dev-1")
        XCTAssertEqual(intelligence.riskScore, 42)
        XCTAssertEqual(intelligence.riskCategory, .suspicious)
        XCTAssertEqual(intelligence.attestationCount, 3)
        XCTAssertNotNil(intelligence.lastAttestationDate)

        let unknownCategory = DeviceIntelligenceResponse(
            deviceId: "dev-2", riskScore: nil, riskCategory: "???", deviceIntegrity: "x",
            jailbreakDetected: true, attestationCount: 0, lastAttestationDate: nil
        )
        let fallback = DeviceIntelligenceExtractor.extractFromResponse(unknownCategory)
        XCTAssertEqual(fallback.riskCategory, .trusted, "unknown categories fall back to trusted")
        XCTAssertNil(fallback.lastAttestationDate)
    }

    func testHardwareModelIsNeverEmpty() {
        XCTAssertFalse(PlatformSupport.getHardwareModel().isEmpty)
        XCTAssertNotEqual(PlatformSupport.getHardwareModel(), "unknown")
    }
}