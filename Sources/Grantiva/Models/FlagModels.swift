import Foundation

/// A single feature flag value resolved for the current environment.
///
/// Flag values are natively typed — use the accessor matching the flag's declared type:
/// ```swift
/// if flags["dark_mode"]?.boolValue == true { ... }
/// let limit = flags["upload_limit"]?.intValue ?? 10
/// ```
public struct FlagValue: Sendable, Equatable {
    /// The raw string representation of the value as returned by the server.
    public let rawValue: String

    /// The server-declared value type for this flag.
    public let valueType: FlagValueType

    /// Boolean interpretation. Returns `nil` if the raw value is not `"true"` / `"false"`.
    public var boolValue: Bool? {
        switch rawValue.lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    /// Integer interpretation. Returns `nil` if the raw value is not a valid integer string.
    public var intValue: Int? { Int(rawValue) }

    /// Double interpretation. Returns `nil` if the raw value is not a valid double string.
    public var doubleValue: Double? { Double(rawValue) }

    /// String value. Always succeeds since the raw value is already a string.
    public var stringValue: String { rawValue }

    /// Parses the raw value as a JSON object and returns the result.
    /// Returns `nil` if the raw value is not valid JSON.
    public var jsonValue: Any? {
        guard let data = rawValue.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}

/// Declared value types for feature flags (mirrors backend `FlagValueType`).
public enum FlagValueType: String, Sendable, Codable {
    case boolean
    case integer
    case double
    case string
    case json
}

/// The environment to evaluate flags against.
public enum FlagEnvironment: String, Sendable {
    case development
    case staging
    case production
}
