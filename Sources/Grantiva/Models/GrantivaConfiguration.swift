import Foundation

internal struct GrantivaConfiguration {
    let baseURL: String
    /// Maximum number of attempts (not extra retries) for retry-safe requests.
    let retryAttempts: Int
    /// Base delay for the exponential backoff used between retry attempts.
    let retryBaseDelay: TimeInterval
    let timeout: TimeInterval
    /// Optional API key for simulator / development use where App Attest is unavailable.
    let apiKey: String?

    static let `default` = GrantivaConfiguration(
        baseURL: "https://api.grantiva.io",
        retryAttempts: 3,
        retryBaseDelay: 1.0,
        timeout: 30.0,
        apiKey: nil
    )

    init(baseURL: String, retryAttempts: Int = 3, retryBaseDelay: TimeInterval = 1.0, timeout: TimeInterval = 30.0, apiKey: String? = nil) {
        self.baseURL = baseURL
        self.retryAttempts = retryAttempts
        self.retryBaseDelay = retryBaseDelay
        self.timeout = timeout
        self.apiKey = apiKey
    }
}
