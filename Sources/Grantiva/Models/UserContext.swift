import Foundation

/// Rich context about the current user and their environment.
///
/// Combines a developer-provided user identifier and custom properties with
/// automatically collected device and app information. All Grantiva services
/// (feedback, flags, analytics) use this context for scoping, targeting, and reporting.
///
/// ```swift
/// grantiva.identify(UserContext(
///     userId: "user_123",
///     properties: [
///         "plan": "premium",
///         "state": "TX",
///         "beta_tester": "true"
///     ]
/// ))
/// ```
public struct UserContext {
    /// A stable, unique identifier for the user in your system.
    public let userId: String

    /// Custom key-value properties for targeting and segmentation.
    ///
    /// Use these for feature flag targeting rules, analytics segmentation,
    /// or any developer-defined attributes.
    ///
    /// Examples: `"plan": "premium"`, `"country": "US"`, `"beta_tester": "true"`
    public var properties: [String: String]

    /// Automatically collected device and app context.
    /// Populated at creation time — not settable by the developer.
    public let device: DeviceContext

    public init(userId: String, properties: [String: String] = [:]) {
        self.userId = userId
        self.properties = properties
        self.device = DeviceContext.current()
    }

    /// All context merged into a flat dictionary for API requests.
    /// Developer properties take precedence over auto-collected values.
    internal var allProperties: [String: String] {
        var merged = device.toDictionary()
        // Developer properties override auto-collected ones
        for (key, value) in properties {
            merged[key] = value
        }
        merged["user_id"] = userId
        return merged
    }
}

/// Automatically collected device and app information.
public struct DeviceContext {
    public let appBundleId: String
    public let appVersion: String
    public let appBuildNumber: String
    public let deviceModel: String
    public let osName: String
    public let osVersion: String
    public let locale: String
    public let timezone: String
    public let sdkVersion: String
    public let environment: String

    internal static func current() -> DeviceContext {
        let systemInfo = PlatformSupport.getSystemInfo()
        let bundle = Bundle.main

        return DeviceContext(
            appBundleId: bundle.bundleIdentifier ?? "unknown",
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            appBuildNumber: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            deviceModel: systemInfo["model"] ?? "unknown",
            osName: systemInfo["platform"] ?? "unknown",
            osVersion: systemInfo["systemVersion"] ?? "unknown",
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier,
            sdkVersion: "1.1.0",
            environment: systemInfo["environment"] ?? "unknown"
        )
    }

    internal func toDictionary() -> [String: String] {
        return [
            "app_bundle_id": appBundleId,
            "app_version": appVersion,
            "app_build_number": appBuildNumber,
            "device_model": deviceModel,
            "os_name": osName,
            "os_version": osVersion,
            "locale": locale,
            "timezone": timezone,
            "sdk_version": sdkVersion,
            "environment": environment
        ]
    }
}
