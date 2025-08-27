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
    
    func testDeviceIntelligenceExtraction() {
        let riskScore = 75
        let riskLevel = DeviceIntelligenceExtractor.analyzeRiskScore(riskScore)
        XCTAssertEqual(riskLevel, "High Risk")
        
        let securityFeatures = DeviceIntelligenceExtractor.getDeviceSecurityFeatures()
        XCTAssertNotNil(securityFeatures["appAttestSupported"])
    }
}