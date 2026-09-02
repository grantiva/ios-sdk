import Foundation

/// Parses the `{ "flags": { "key": typedValue, ... } }` payload shared by the flag
/// REST endpoint and the SSE `flags` event into `[String: FlagValue]`.
///
/// The payload is not Codable-friendly because values are heterogeneous (bool,
/// int, double, string, object), so it goes through `JSONSerialization`.
internal enum FlagPayloadParser {

    /// Returns `nil` when `data` is not a JSON object with a `flags` object.
    static func parse(_ data: Data) -> [String: FlagValue]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let flagsDict = json["flags"] as? [String: Any] else {
            return nil
        }

        var result: [String: FlagValue] = [:]
        for (key, value) in flagsDict {
            let (rawValue, valueType) = classify(value)
            result[key] = FlagValue(rawValue: rawValue, valueType: valueType)
        }
        return result
    }

    /// Classifies a JSON value into a raw string + type pair.
    static func classify(_ value: Any) -> (String, FlagValueType) {
        // JSONSerialization represents JSON booleans as NSNumber; the CFBoolean type
        // check distinguishes true booleans from numeric 0/1, so it must run first.
        if let nsNumber = value as? NSNumber {
            if CFGetTypeID(nsNumber) == CFBooleanGetTypeID() {
                return (nsNumber.boolValue ? "true" : "false", .boolean)
            }
            if nsNumber.doubleValue == Double(nsNumber.intValue) {
                return ("\(nsNumber.intValue)", .integer)
            }
            return ("\(nsNumber.doubleValue)", .double)
        }
        if let str = value as? String {
            return (str, .string)
        }
        if let data = try? JSONSerialization.data(withJSONObject: value),
           let jsonStr = String(data: data, encoding: .utf8) {
            return (jsonStr, .json)
        }
        return ("\(value)", .string)
    }
}
