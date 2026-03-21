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
    
    func testDeviceIntelligenceExtraction() {
        let riskScore = 75
        let riskLevel = DeviceIntelligenceExtractor.analyzeRiskScore(riskScore)
        XCTAssertEqual(riskLevel, "High Risk")
        
        let securityFeatures = DeviceIntelligenceExtractor.getDeviceSecurityFeatures()
        XCTAssertNotNil(securityFeatures["appAttestSupported"])
    }
}