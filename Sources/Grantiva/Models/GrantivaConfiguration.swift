import Foundation

internal struct GrantivaConfiguration {
    let baseURL: String
    let retryAttempts: Int
    let timeout: TimeInterval
    /// Optional API key for simulator / development use where App Attest is unavailable.
    let apiKey: String?

    static let `default` = GrantivaConfiguration(
        baseURL: "https://grantiva.io",
        retryAttempts: 3,
        timeout: 30.0,
        apiKey: nil
    )

    init(baseURL: String, retryAttempts: Int = 3, timeout: TimeInterval = 30.0, apiKey: String? = nil) {
        self.baseURL = baseURL
        self.retryAttempts = retryAttempts
        self.timeout = timeout
        self.apiKey = apiKey
    }
}
