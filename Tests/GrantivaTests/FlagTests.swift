import XCTest
@testable import Grantiva

final class FlagTests: XCTestCase {

    // MARK: - FlagValueType

    func testFlagValueTypeRawValues() {
        XCTAssertEqual(FlagValueType.boolean.rawValue, "boolean")
        XCTAssertEqual(FlagValueType.integer.rawValue, "integer")
        XCTAssertEqual(FlagValueType.double.rawValue, "double")
        XCTAssertEqual(FlagValueType.string.rawValue, "string")
        XCTAssertEqual(FlagValueType.json.rawValue, "json")
    }

    func testFlagValueTypeDecodable() throws {
        let cases: [(String, FlagValueType)] = [
            ("boolean", .boolean),
            ("integer", .integer),
            ("double", .double),
            ("string", .string),
            ("json", .json),
        ]
        for (raw, expected) in cases {
            let data = "\"\(raw)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(FlagValueType.self, from: data)
            XCTAssertEqual(decoded, expected, "Failed for \(raw)")
        }
    }

    // MARK: - FlagValue.boolValue

    func testFlagValueBoolTrue() {
        let flag = FlagValue(rawValue: "true", valueType: .boolean)
        XCTAssertEqual(flag.boolValue, true)
    }

    func testFlagValueBoolFalse() {
        let flag = FlagValue(rawValue: "false", valueType: .boolean)
        XCTAssertEqual(flag.boolValue, false)
    }

    func testFlagValueBoolCaseInsensitive() {
        XCTAssertEqual(FlagValue(rawValue: "TRUE", valueType: .boolean).boolValue, true)
        XCTAssertEqual(FlagValue(rawValue: "False", valueType: .boolean).boolValue, false)
    }

    func testFlagValueBoolNilForNonBoolean() {
        XCTAssertNil(FlagValue(rawValue: "1", valueType: .integer).boolValue)
        XCTAssertNil(FlagValue(rawValue: "yes", valueType: .string).boolValue)
        XCTAssertNil(FlagValue(rawValue: "", valueType: .string).boolValue)
    }

    // MARK: - FlagValue.intValue

    func testFlagValueIntValid() {
        XCTAssertEqual(FlagValue(rawValue: "42", valueType: .integer).intValue, 42)
        XCTAssertEqual(FlagValue(rawValue: "0", valueType: .integer).intValue, 0)
        XCTAssertEqual(FlagValue(rawValue: "-10", valueType: .integer).intValue, -10)
    }

    func testFlagValueIntNilForNonInteger() {
        XCTAssertNil(FlagValue(rawValue: "abc", valueType: .string).intValue)
        XCTAssertNil(FlagValue(rawValue: "3.14", valueType: .double).intValue)
    }

    // MARK: - FlagValue.doubleValue

    func testFlagValueDoubleValid() {
        XCTAssertEqual(FlagValue(rawValue: "3.14", valueType: .double).doubleValue, 3.14)
        XCTAssertEqual(FlagValue(rawValue: "0.0", valueType: .double).doubleValue, 0.0)
        XCTAssertEqual(FlagValue(rawValue: "42", valueType: .integer).doubleValue, 42.0)
    }

    func testFlagValueDoubleNilForNonDouble() {
        XCTAssertNil(FlagValue(rawValue: "not-a-number", valueType: .string).doubleValue)
    }

    // MARK: - FlagValue.stringValue

    func testFlagValueStringAlwaysReturnsRaw() {
        let raw = "hello world"
        XCTAssertEqual(FlagValue(rawValue: raw, valueType: .string).stringValue, raw)
        XCTAssertEqual(FlagValue(rawValue: "true", valueType: .boolean).stringValue, "true")
        XCTAssertEqual(FlagValue(rawValue: "42", valueType: .integer).stringValue, "42")
    }

    // MARK: - FlagValue.jsonValue

    func testFlagValueJsonValidObject() {
        let flag = FlagValue(rawValue: "{\"key\":\"value\"}", valueType: .json)
        let json = flag.jsonValue as? [String: String]
        XCTAssertNotNil(json)
        XCTAssertEqual(json?["key"], "value")
    }

    func testFlagValueJsonValidArray() {
        let flag = FlagValue(rawValue: "[1,2,3]", valueType: .json)
        let arr = flag.jsonValue as? [Int]
        XCTAssertNotNil(arr)
        XCTAssertEqual(arr?.count, 3)
    }

    func testFlagValueJsonNilForInvalidJson() {
        let flag = FlagValue(rawValue: "not json", valueType: .string)
        XCTAssertNil(flag.jsonValue)
    }

    // MARK: - FlagEnvironment

    func testFlagEnvironmentRawValues() {
        XCTAssertEqual(FlagEnvironment.development.rawValue, "development")
        XCTAssertEqual(FlagEnvironment.staging.rawValue, "staging")
        XCTAssertEqual(FlagEnvironment.production.rawValue, "production")
    }

    // MARK: - FlagService state

    func testFlagServiceDefaultCacheTTL() async {
        let config = GrantivaConfiguration(baseURL: "https://api.grantiva.io")
        let client = FlagAPIClient(configuration: config, teamId: "TEAM123")
        let service = FlagService(apiClient: client, identity: IdentityProvider())
        let ttl = await service.cacheTTL
        XCTAssertEqual(ttl, 300)
    }

    func testFlagServiceDefaultEnvironment() async {
        let config = GrantivaConfiguration(baseURL: "https://api.grantiva.io")
        let client = FlagAPIClient(configuration: config, teamId: "TEAM123")
        let service = FlagService(apiClient: client, identity: IdentityProvider())
        let env = await service.environment
        XCTAssertEqual(env, .production)
    }

    func testFlagServiceClearCacheDoesNotThrow() async {
        let config = GrantivaConfiguration(baseURL: "https://api.grantiva.io")
        let client = FlagAPIClient(configuration: config, teamId: "TEAM123")
        let service = FlagService(apiClient: client, identity: IdentityProvider())
        await service.clearCache()
        // Just verify it doesn't crash / throw
    }

    func testFlagServiceRefreshDoesNotThrow() async {
        let config = GrantivaConfiguration(baseURL: "https://api.grantiva.io")
        let client = FlagAPIClient(configuration: config, teamId: "TEAM123")
        let service = FlagService(apiClient: client, identity: IdentityProvider())
        await service.refresh()
    }

    func testFlagServiceCustomCacheTTL() async {
        let config = GrantivaConfiguration(baseURL: "https://api.grantiva.io")
        let client = FlagAPIClient(configuration: config, teamId: "TEAM123")
        let service = FlagService(apiClient: client, identity: IdentityProvider(), cacheTTL: 60)
        let ttl = await service.cacheTTL
        XCTAssertEqual(ttl, 60, "Custom TTL should be respected")
    }

    func testFlagServiceZeroCacheTTL() async {
        let config = GrantivaConfiguration(baseURL: "https://api.grantiva.io")
        let client = FlagAPIClient(configuration: config, teamId: "TEAM123")
        let service = FlagService(apiClient: client, identity: IdentityProvider(), cacheTTL: 0)
        let ttl = await service.cacheTTL
        XCTAssertEqual(ttl, 0, "Zero TTL disables caching")
    }

    // MARK: - Grantiva.flags integration

    func testGrantivaExposeFlagsProperty() {
        let grantiva = Grantiva(teamId: "TEAM123")
        _ = grantiva.flags
    }

    func testGrantivaFlagsPropertyIsStable() async {
        let grantiva = Grantiva(teamId: "TEAM123")
        let flags1 = grantiva.flags
        let flags2 = grantiva.flags
        // Both references should point to the same actor instance
        XCTAssertTrue(flags1 === flags2)
    }

    func testGrantivaFlagCacheTTLPassedToService() async {
        let grantiva = Grantiva(teamId: "TEAM123", flagCacheTTL: 30)
        let ttl = await grantiva.flags.cacheTTL
        XCTAssertEqual(ttl, 30, "flagCacheTTL from init should propagate to FlagService")
    }

    func testGrantivaDefaultFlagCacheTTLIs300() async {
        let grantiva = Grantiva(teamId: "TEAM123")
        let ttl = await grantiva.flags.cacheTTL
        XCTAssertEqual(ttl, 300, "Default flagCacheTTL should be 300 seconds")
    }
}
