import Foundation

internal class GrantivaAPIClient {
    private let configuration: GrantivaConfiguration
    private let session: URLSession
    private let teamId: String
    
    /// - Parameter protocolClasses: Optional `URLProtocol` subclasses injected into the
    ///   session configuration. Used by tests to stub transport behaviour; `nil` in production.
    init(configuration: GrantivaConfiguration = .default, teamId: String, protocolClasses: [AnyClass]? = nil) {
        self.configuration = configuration
        self.teamId = teamId
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        sessionConfig.timeoutIntervalForResource = configuration.timeout
        if let protocolClasses {
            sessionConfig.protocolClasses = protocolClasses
        }
        self.session = URLSession(configuration: sessionConfig)
    }

    /// Internal seam: injects a pre-built `URLSession` so tests can install a stub
    /// `URLProtocol`. Not part of the public API; production code uses `init(configuration:teamId:)`.
    init(configuration: GrantivaConfiguration = .default, teamId: String, session: URLSession) {
        self.configuration = configuration
        self.teamId = teamId
        self.session = session
    }
    
    /// Requests a fresh attestation challenge.
    ///
    /// This is the only endpoint on this client that is retried. It is an idempotent
    /// `GET` that mints a brand-new challenge per call: a duplicate request costs one
    /// extra unused challenge and nothing else, so a transient transport failure is
    /// safe to retry. Retry policy comes from `configuration.retryAttempts` and is
    /// applied by `RetryManager` (exponential backoff + jitter, capped at 30s).
    func requestChallenge() async throws -> ChallengeResponse {
        try await RetryManager.executeWithRetry(
            maxAttempts: max(1, configuration.retryAttempts),
            baseDelay: configuration.retryBaseDelay
        ) { [self] in
            try await performChallengeRequest()
        }
    }

    private func performChallengeRequest() async throws -> ChallengeResponse {
        let url = URL(string: "\(configuration.baseURL)/api/v1/attestation/challenge")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GrantivaError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                throw parseServerError(from: data, statusCode: httpResponse.statusCode)
            }

            let challengeResponse = try JSONDecoder().decode(ChallengeResponse.self, from: data)
            return challengeResponse
        } catch {
            if error is GrantivaError {
                throw error
            } else {
                throw GrantivaError.networkError(error)
            }
        }
    }
    
    /// Submits an App Attest attestation object for server-side validation.
    ///
    /// Deliberately **not** retried. The request consumes a one-time server challenge
    /// and, on success, writes the device's attestation row (including the App Attest
    /// signature counter). If the response is lost after the server processed it, a
    /// retry would replay a spent challenge against an already-attested key — and App
    /// Attest permits exactly one attestation per key over its lifetime, so a wasted
    /// attempt is unrecoverable rather than merely wasteful. URLSession cannot tell us
    /// whether an in-flight POST reached the server (`.timedOut` and
    /// `.networkConnectionLost` are both ambiguous), so failing the call and letting
    /// the caller restart the flow from a fresh challenge is the safe behaviour.
    func validateAttestation(_ request: AttestationRequest) async throws -> AttestationResponse {
        let url = URL(string: "\(configuration.baseURL)/api/v1/attestation/validate")!
        
        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &httpRequest)
        
        do {
            let jsonData = try JSONEncoder().encode(request)
            httpRequest.httpBody = jsonData
            
            Logger.debug("[Grantiva API] Sending request to: \(url)")
            Logger.debug("[Grantiva API] Headers: X-Bundle-ID=\(getBundleId()), X-Team-ID=\(teamId)")
            Logger.debug("[Grantiva API] Request body size: \(jsonData.count) bytes")
            
            let (data, response) = try await session.data(for: httpRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.error("[Grantiva API] Invalid response — not an HTTP response")
                throw GrantivaError.invalidResponse
            }
            
            Logger.debug("[Grantiva API] Response status code: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                throw parseServerError(from: data, statusCode: httpResponse.statusCode)
            }
            
            let attestationResponse = try JSONDecoder().decode(AttestationResponse.self, from: data)
            Logger.debug("[Grantiva API] Successfully decoded attestation response")
            return attestationResponse
        } catch {
            Logger.error("[Grantiva API] Attestation validation failed: \(error)")
            if error is GrantivaError {
                throw error
            } else {
                throw GrantivaError.networkError(error)
            }
        }
    }
    
    /// Parses error responses for non-200 HTTP status codes.
    ///
    /// - 429 with `{"error":"mad_limit_exceeded","limit":X,"current":Y}` → `.limitExceeded(limit:current:)`
    /// - Other 4xx with `{"error":true,"reason":"..."}` (Vapor format) → `.serverError(reason:)`
    /// - 5xx or unrecognised bodies → `.validationFailed`
    func parseServerError(from data: Data, statusCode: Int) -> GrantivaError {
        if statusCode == 429 {
            if let limitResponse = try? JSONDecoder().decode(MADLimitResponse.self, from: data),
               limitResponse.error == "mad_limit_exceeded" {
                Logger.warning("[Grantiva API] MAD limit exceeded: \(limitResponse.current)/\(limitResponse.limit)")
                return .limitExceeded(limit: limitResponse.limit, current: limitResponse.current)
            }
        }
        guard (400..<500).contains(statusCode) else {
            return .validationFailed
        }
        if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           !errorResponse.reason.isEmpty {
            Logger.debug("[Grantiva API] Server error (\(statusCode)): \(errorResponse.reason)")
            return .serverError(reason: errorResponse.reason)
        }
        return .validationFailed
    }

    /// Calls `POST /api/v1/attestation/refresh` with an assertion to get a new JWT.
    ///
    /// Deliberately **not** retried. The assertion carries the App Attest signature
    /// counter, which the server validates as strictly increasing. Resending the same
    /// assertion after a partially-processed request is indistinguishable from a replay
    /// attack and is rejected by the server, so a retry cannot succeed — it can only
    /// turn a transient failure into a suspicious-looking counter conflict. Callers
    /// recover by generating a new assertion.
    func refreshWithAssertion(_ request: AssertionRefreshRequest) async throws -> AssertionRefreshResponse {
        let url = URL(string: "\(configuration.baseURL)/api/v1/attestation/refresh")!

        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &httpRequest)

        do {
            let jsonData = try JSONEncoder().encode(request)
            httpRequest.httpBody = jsonData

            let (data, response) = try await session.data(for: httpRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GrantivaError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                Logger.error("[Grantiva API] Refresh failed (\(httpResponse.statusCode))")
                if let body = String(data: data, encoding: .utf8), !body.isEmpty {
                    // Response bodies can echo request context; keep them at .debug only.
                    Logger.debug("[Grantiva API] Refresh error body: \(body)")
                }
                // 409 = backend has invalidated the stored attestation row and is asking
                // the SDK to re-attest. Surface a distinct error so the caller can self-heal.
                if httpResponse.statusCode == 409 {
                    throw GrantivaError.reattestRequired
                }
                throw GrantivaError.validationFailed
            }

            return try JSONDecoder().decode(AssertionRefreshResponse.self, from: data)
        } catch {
            if error is GrantivaError { throw error }
            throw GrantivaError.networkError(error)
        }
    }

    private func applyAuth(to request: inout URLRequest) {
        if let apiKey = configuration.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue(getBundleId(), forHTTPHeaderField: "X-Bundle-ID")
            request.setValue(teamId, forHTTPHeaderField: "X-Team-ID")
        }
    }

    private func getBundleId() -> String {
        return Bundle.main.bundleIdentifier ?? ""
    }

}
