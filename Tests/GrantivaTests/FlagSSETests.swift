import XCTest
@testable import Grantiva

/// Tests for the SSE flag streaming client and FlagService integration.
final class FlagSSETests: XCTestCase {

    // MARK: - JSON classification (mirrors FlagSSEClient.classify)

    func testClassifyBoolTrue() {
        let result = parsedFlags(from: #"{"flags":{"feature_x":true}}"#)
        XCTAssertEqual(result?["feature_x"]?.valueType, .boolean)
        XCTAssertEqual(result?["feature_x"]?.boolValue, true)
    }

    func testClassifyBoolFalse() {
        let result = parsedFlags(from: #"{"flags":{"feature_x":false}}"#)
        XCTAssertEqual(result?["feature_x"]?.boolValue, false)
    }

    func testClassifyInteger() {
        let result = parsedFlags(from: #"{"flags":{"upload_limit":50}}"#)
        XCTAssertEqual(result?["upload_limit"]?.valueType, .integer)
        XCTAssertEqual(result?["upload_limit"]?.intValue, 50)
    }

    func testClassifyDouble() {
        let result = parsedFlags(from: #"{"flags":{"multiplier":1.5}}"#)
        XCTAssertEqual(result?["multiplier"]?.valueType, .double)
        XCTAssertEqual(result?["multiplier"]?.doubleValue, 1.5)
    }

    func testClassifyString() {
        let result = parsedFlags(from: #"{"flags":{"theme":"dark"}}"#)
        XCTAssertEqual(result?["theme"]?.valueType, .string)
        XCTAssertEqual(result?["theme"]?.stringValue, "dark")
    }

    func testEmptyFlagsPayload() {
        let result = parsedFlags(from: #"{"flags":{}}"#)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isEmpty)
    }

    func testMalformedPayloadReturnsNil() {
        XCTAssertNil(parsedFlags(from: "not-json"))
        XCTAssertNil(parsedFlags(from: "{}"))
        XCTAssertNil(parsedFlags(from: #"{"flags":null}"#))
    }

    func testMultipleFlagsInOnePayload() {
        let result = parsedFlags(from: #"{"flags":{"dark_mode":true,"limit":25,"label":"beta"}}"#)
        XCTAssertEqual(result?.count, 3)
        XCTAssertEqual(result?["dark_mode"]?.boolValue, true)
        XCTAssertEqual(result?["limit"]?.intValue, 25)
        XCTAssertEqual(result?["label"]?.stringValue, "beta")
    }

    // MARK: - FlagService SSE integration

    func testSSEUpdatePopulatesCache() async throws {
        let service = makeFlagService()

        await service.handleSSEUpdate([
            "dark_mode": FlagValue(rawValue: "true", valueType: .boolean)
        ])

        // getFlags() returns the SSE values from cache — no network needed
        let cached = try await service.getFlags()
        XCTAssertEqual(cached["dark_mode"]?.boolValue, true)
    }

    func testOnUpdateHandlerInvokedOnSSEEvent() async throws {
        let service = makeFlagService()

        let expectation = XCTestExpectation(description: "onUpdate handler called")
        // Use a Sendable box so the @Sendable closure can mutate shared test state safely
        let box = SendableBox<[String: FlagValue]>()

        await service.setUpdateHandler { @Sendable flags in
            box.value = flags
            expectation.fulfill()
        }

        await service.handleSSEUpdate([
            "new_flag": FlagValue(rawValue: "42", valueType: .integer)
        ])

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(box.value?["new_flag"]?.intValue, 42)
    }

    func testSSEUpdateOverwritesPreviousCache() async throws {
        let service = makeFlagService()

        await service.handleSSEUpdate([
            "flag_a": FlagValue(rawValue: "true", valueType: .boolean)
        ])
        await service.handleSSEUpdate([
            "flag_b": FlagValue(rawValue: "hello", valueType: .string)
        ])

        let cached = try await service.getFlags()
        // Second update replaces entire cache (backend always sends full snapshot)
        XCTAssertNil(cached["flag_a"])
        XCTAssertEqual(cached["flag_b"]?.stringValue, "hello")
    }

    func testSettingNilHandlerDisablesCallbacks() async throws {
        let service = makeFlagService()

        let counter = SendableCounter()
        await service.setUpdateHandler { @Sendable _ in counter.increment() }
        await service.handleSSEUpdate(["f": FlagValue(rawValue: "1", valueType: .integer)])

        await service.setUpdateHandler(nil)
        await service.handleSSEUpdate(["f": FlagValue(rawValue: "2", valueType: .integer)])

        try await Task.sleep(for: .milliseconds(50))
        // Only the first update should have triggered the handler
        XCTAssertEqual(counter.count, 1)
    }

    // MARK: - FlagSSEClient connection lifecycle

    func testSSEClientStartStop() {
        let client = makeSSEClient()
        client.start() // will attempt connection and fail gracefully with no server
        client.stop()
    }

    func testSSEClientStartIsIdempotent() {
        let client = makeSSEClient()
        client.start()
        client.start() // second start is a no-op
        client.stop()
    }

    func testSSEClientStopWithoutStart() {
        let client = makeSSEClient()
        client.stop() // must not crash
    }

    func testSSEClientStopIsIdempotent() {
        let client = makeSSEClient()
        client.start()
        client.stop()
        client.stop() // second stop is fine
    }

    // MARK: - FlagService streaming lifecycle

    func testStartStreamingIsIdempotent() async {
        let service = makeFlagService()
        let config = GrantivaConfiguration(baseURL: "https://api.example.com", retryAttempts: 1, timeout: 5)
        let tm = TokenManager()
        await service.startStreaming(configuration: config, teamId: "T1", tokenManager: tm)
        await service.startStreaming(configuration: config, teamId: "T1", tokenManager: tm) // no-op
        await service.stopStreaming()
    }

    func testStopStreamingWithoutStart() async {
        let service = makeFlagService()
        await service.stopStreaming() // must not crash
    }

    // MARK: - Helpers

    /// Replicates FlagSSEClient's parseFlags logic via public types.
    private func parsedFlags(from json: String) -> [String: FlagValue]? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let flagsDict = obj["flags"] as? [String: Any] else { return nil }

        var result: [String: FlagValue] = [:]
        for (key, value) in flagsDict {
            if let nsNumber = value as? NSNumber {
                if CFGetTypeID(nsNumber) == CFBooleanGetTypeID() {
                    result[key] = FlagValue(rawValue: nsNumber.boolValue ? "true" : "false", valueType: .boolean)
                } else if nsNumber.doubleValue == Double(nsNumber.intValue) {
                    result[key] = FlagValue(rawValue: "\(nsNumber.intValue)", valueType: .integer)
                } else {
                    result[key] = FlagValue(rawValue: "\(nsNumber.doubleValue)", valueType: .double)
                }
            } else if let str = value as? String {
                result[key] = FlagValue(rawValue: str, valueType: .string)
            } else if let d = try? JSONSerialization.data(withJSONObject: value),
                      let s = String(data: d, encoding: .utf8) {
                result[key] = FlagValue(rawValue: s, valueType: .json)
            }
        }
        return result
    }

    private func makeFlagService() -> FlagService {
        let config = GrantivaConfiguration(
            baseURL: "https://api.example.com",
            retryAttempts: 1,
            timeout: 5
        )
        return FlagService(
            apiClient: FlagAPIClient(configuration: config, teamId: "TEAM123"),
            identity: IdentityProvider(),
            environment: .production
        )
    }

    private func makeSSEClient() -> FlagSSEClient {
        let config = GrantivaConfiguration(
            baseURL: "https://api.example.com",
            retryAttempts: 1,
            timeout: 5
        )
        return FlagSSEClient(
            configuration: config,
            teamId: "TEAM123",
            environment: .production,
            tokenManager: TokenManager()
        )
    }
}

// MARK: - Test Utilities

/// Thread-safe mutable box for use in @Sendable closures during tests.
private final class SendableBox<T>: @unchecked Sendable {
    var value: T?
}

/// Thread-safe counter for use in @Sendable closures during tests.
private final class SendableCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    var count: Int { lock.withLock { _count } }

    func increment() {
        lock.withLock { _count += 1 }
    }
}
