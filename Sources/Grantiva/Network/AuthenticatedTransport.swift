import Foundation

/// Shared request plumbing for the JWT-authenticated feature clients (feedback,
/// flags, what's new).
///
/// Every request carries the tenant headers for app scoping, then the best
/// available credential: a non-expired attestation JWT, else the API key
/// (simulator / dev builds). When the stored JWT has expired and a refresh hook is
/// available, the transport renews it *before* sending rather than handing the
/// server a token it will reject. A 401 on a token the SDK believed valid is
/// answered the same way: refresh once, retry once, give up otherwise.
///
/// Without this, every feature call made after the hour-long JWT expired failed
/// with `validationFailed` until the host app happened to call
/// `validateAttestation()` again.
internal final class AuthenticatedTransport: @unchecked Sendable {
    private let configuration: GrantivaConfiguration
    private let teamId: String
    private let session: URLSession
    /// Returns the current non-expired JWT, or `nil` when there is none.
    private let getToken: @Sendable () -> String?
    /// Renews the JWT through the SDK's attestation path. `nil` in API key mode.
    private let refreshToken: (@Sendable () async -> Bool)?

    init(
        configuration: GrantivaConfiguration,
        teamId: String,
        getToken: @escaping @Sendable () -> String?,
        refreshToken: (@Sendable () async -> Bool)?,
        session: URLSession? = nil
    ) {
        self.configuration = configuration
        self.teamId = teamId
        self.getToken = getToken
        self.refreshToken = refreshToken
        if let session {
            self.session = session
        } else {
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.timeoutIntervalForRequest = configuration.timeout
            sessionConfig.timeoutIntervalForResource = configuration.timeout
            self.session = URLSession(configuration: sessionConfig)
        }
    }

    // MARK: - Request building

    func request(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    func request<T: Encodable>(url: URL, method: String, body: T) throws -> URLRequest {
        var request = request(url: url, method: method)
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    // MARK: - Sending

    /// Authorizes and sends `request`, returning the response body for any 2xx.
    ///
    /// - Throws: `GrantivaError.validationFailed` for a 401 that could not be
    ///   recovered by a token refresh, `.rateLimited` for 429, `.networkError` for
    ///   other non-2xx statuses and transport failures, `.invalidResponse` for a
    ///   non-HTTP response.
    func send(_ request: URLRequest) async throws -> Data {
        var authorized = request
        await applyAuth(to: &authorized)

        do {
            return try await perform(authorized)
        } catch GrantivaError.validationFailed {
            // The server rejected a token we believed valid (revoked, clock skew,
            // rotated signing key). Refresh once and retry once.
            guard let refreshToken, await refreshToken() else { throw GrantivaError.validationFailed }
            var retried = request
            await applyAuth(to: &retried)
            return try await perform(retried)
        }
    }

    private func applyAuth(to request: inout URLRequest) async {
        request.setValue(Bundle.main.bundleIdentifier ?? "", forHTTPHeaderField: "X-Bundle-ID")
        request.setValue(teamId, forHTTPHeaderField: "X-Team-ID")

        var token = getToken()
        if token == nil, let refreshToken, await refreshToken() {
            token = getToken()
        }

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let apiKey = configuration.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
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
                    Logger.error("Server error (\(httpResponse.statusCode)): \(errorResponse.reason)")
                }
                throw GrantivaError.networkError(NSError(domain: "HTTPError", code: httpResponse.statusCode))
            }
        } catch {
            if error is GrantivaError { throw error }
            throw GrantivaError.networkError(error)
        }
    }
}
