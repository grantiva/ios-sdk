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
    
    func testCustomClaimsProcessing() {
        let testClaims = ["user_id": "123", "role": "admin"]
        let isValid = CustomClaimsProcessor.validateClaims(testClaims)
        XCTAssertTrue(isValid)
        
        let invalidClaims = ["iss": "invalid"]
        let isInvalid = CustomClaimsProcessor.validateClaims(invalidClaims)
        XCTAssertFalse(isInvalid)
    }
    
    func testErrorHandling() {
        let error = GrantivaError.deviceNotSupported
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotNil(error.failureReason)
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

        // serverUnavailable (4) is transient — re-attesting would burn the key for nothing.
        guard case .validationFailed = AttestationManager.mapAssertionError(NSError(domain: dcDomain, code: 4)) else {
            return XCTFail("DCError serverUnavailable (4) should stay validationFailed")
        }
        // Same codes from a different domain (e.g. NSURLErrorDomain) must not trigger self-heal.
        guard case .validationFailed = AttestationManager.mapAssertionError(NSError(domain: NSURLErrorDomain, code: 2)) else {
            return XCTFail("Non-DeviceCheck domains should stay validationFailed")
        }
    }
    
    func testDeviceIntelligenceExtraction() {
        let riskScore = 75
        let riskLevel = DeviceIntelligenceExtractor.analyzeRiskScore(riskScore)
        XCTAssertEqual(riskLevel, "High Risk")
        
        let securityFeatures = DeviceIntelligenceExtractor.getDeviceSecurityFeatures()
        XCTAssertNotNil(securityFeatures["appAttestSupported"])
    }
}