import XCTest
@testable import Grantiva

/// Tests for `GrantivaConfiguration` defaults.
final class GrantivaConfigurationTests: XCTestCase {

    func testDefaultConfigurationPointsAtProduction() {
        let config = GrantivaConfiguration.default
        XCTAssertEqual(config.baseURL, "https://api.grantiva.io")
        XCTAssertFalse(config.baseURL.hasSuffix("/"), "a trailing slash would produce '//api/v1/...' paths")
        XCTAssertTrue(config.baseURL.hasPrefix("https://"), "attestation traffic must never fall back to plaintext HTTP")
    }

    func testDefaultConfigurationHasNoAPIKey() {
        // The default (device) path authenticates with App Attest, not a shared secret.
        XCTAssertNil(GrantivaConfiguration.default.apiKey)
    }

    func testDefaultRetryAndTimeoutValues() {
        let config = GrantivaConfiguration.default
        XCTAssertEqual(config.retryAttempts, 3)
        XCTAssertEqual(config.timeout, 30.0)
    }

    func testInitAppliesTheSameDefaultsAsTheStaticDefault() {
        let config = GrantivaConfiguration(baseURL: "https://api.grantiva.io")
        XCTAssertEqual(config.retryAttempts, GrantivaConfiguration.default.retryAttempts)
        XCTAssertEqual(config.timeout, GrantivaConfiguration.default.timeout)
        XCTAssertNil(config.apiKey)
    }

    func testInitRetainsExplicitValues() {
        let config = GrantivaConfiguration(
            baseURL: "https://dev-api.grantiva.io",
            retryAttempts: 5,
            timeout: 7.5,
            apiKey: "gdev_key"
        )
        XCTAssertEqual(config.baseURL, "https://dev-api.grantiva.io")
        XCTAssertEqual(config.retryAttempts, 5)
        XCTAssertEqual(config.timeout, 7.5)
        XCTAssertEqual(config.apiKey, "gdev_key")
    }
}
