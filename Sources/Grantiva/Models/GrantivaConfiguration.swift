import Foundation

internal struct GrantivaConfiguration {
    let baseURL: String
    let retryAttempts: Int
    let timeout: TimeInterval
    
    static let `default` = GrantivaConfiguration(
        baseURL: "https://grantiva.io",
        retryAttempts: 3,
        timeout: 30.0
    )
    
    init(baseURL: String, retryAttempts: Int = 3, timeout: TimeInterval = 30.0) {
        self.baseURL = baseURL
        self.retryAttempts = retryAttempts
        self.timeout = timeout
    }
}
