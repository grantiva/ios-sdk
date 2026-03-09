import Foundation

/// Handles all feature flag API calls.
internal final class FlagAPIClient: @unchecked Sendable {
    private let configuration: GrantivaConfiguration
    private let session: URLSession
    private let teamId: String

    init(configuration: GrantivaConfiguration, teamId: String) {
        self.configuration = configuration
        self.teamId = teamId

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        sessionConfig.timeoutIntervalForResource = configuration.timeout
        self.session = URLSession(configuration: sessionConfig)
    }

    /// Fetch all flags for the current tenant and environment.
    ///
    /// The backend returns `{ "flags": { "key": typedValue, ... } }` where values are
    /// natively typed via `JSONSerialization` (bools, ints, doubles, strings, objects).
    /// We parse them back into `[String: FlagValue]`.
    func fetchFlags(environment: FlagEnvironment) async throws -> [String: FlagValue] {
        var components = URLComponents(string: "\(configuration.baseURL)/api/v1/flags")!
        components.queryItems = [
            URLQueryItem(name: "environment", value: environment.rawValue)
        ]

        let request = makeRequest(url: components.url!, method: "GET")
        let data = try await perform(request)

        // The response is { "flags": { "key": typedValue } } — NOT Codable-friendly
        // because values are heterogeneous (bool, int, double, string, object).
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let flagsDict = json["flags"] as? [String: Any] else {
            throw GrantivaError.invalidResponse
        }

        var result: [String: FlagValue] = [:]
        for (key, value) in flagsDict {
            let (rawValue, valueType) = Self.classify(value)
            result[key] = FlagValue(rawValue: rawValue, valueType: valueType)
        }
        return result
    }

    // MARK: - Classification

    /// Classifies a JSON value into a raw string + type pair.
    private static func classify(_ value: Any) -> (String, FlagValueType) {
        // JSONSerialization represents JSON booleans as NSNumber with objCType 'c'.
        // We must check for Bool *before* numeric types to avoid misclassifying.
        if let nsNumber = value as? NSNumber {
            // CFBooleanGetTypeID check distinguishes true booleans from numeric 0/1.
            if CFGetTypeID(nsNumber) == CFBooleanGetTypeID() {
                return (nsNumber.boolValue ? "true" : "false", .boolean)
            }
            // Check if it's an integer (no fractional part)
            if nsNumber.doubleValue == Double(nsNumber.intValue) {
                return ("\(nsNumber.intValue)", .integer)
            }
            return ("\(nsNumber.doubleValue)", .double)
        }
        if let str = value as? String {
            return (str, .string)
        }
        // Fallback: encode as JSON string
        if let data = try? JSONSerialization.data(withJSONObject: value),
           let jsonStr = String(data: data, encoding: .utf8) {
            return (jsonStr, .json)
        }
        return ("\(value)", .string)
    }

    // MARK: - Request Helpers

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = configuration.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue(getBundleId(), forHTTPHeaderField: "X-Bundle-ID")
            request.setValue(teamId, forHTTPHeaderField: "X-Team-ID")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GrantivaError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200...299:
                return data
            case 401:
                throw GrantivaError.validationFailed
            case 429:
                throw GrantivaError.rateLimited
            default:
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    Logger.error("Server error: \(errorResponse.reason)")
                }
                throw GrantivaError.networkError(NSError(domain: "HTTPError", code: httpResponse.statusCode))
            }
        } catch {
            if error is GrantivaError { throw error }
            throw GrantivaError.networkError(error)
        }
    }

    private func getBundleId() -> String {
        Bundle.main.bundleIdentifier ?? ""
    }
}
