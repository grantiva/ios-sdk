import Foundation

internal class GrantivaAPIClient {
    private let configuration: GrantivaConfiguration
    private let session: URLSession
    private let teamId: String
    
    init(configuration: GrantivaConfiguration = .default, teamId: String) {
        self.configuration = configuration
        self.teamId = teamId
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        sessionConfig.timeoutIntervalForResource = configuration.timeout
        self.session = URLSession(configuration: sessionConfig)
    }
    
    func requestChallenge() async throws -> ChallengeResponse {
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
    
    func validateAttestation(_ request: AttestationRequest) async throws -> AttestationResponse {
        let url = URL(string: "\(configuration.baseURL)/api/v1/attestation/validate")!
        
        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &httpRequest)
        
        do {
            let jsonData = try JSONEncoder().encode(request)
            httpRequest.httpBody = jsonData
            
            print("[Grantiva API] Sending request to: \(url)")
            print("[Grantiva API] Headers: X-Bundle-ID=\(getBundleId()), X-Team-ID=\(teamId)")
            print("[Grantiva API] Request body size: \(jsonData.count) bytes")
            
            let (data, response) = try await session.data(for: httpRequest)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[Grantiva API] Invalid response - not HTTP")
                throw GrantivaError.invalidResponse
            }
            
            print("[Grantiva API] Response status code: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                throw parseServerError(from: data, statusCode: httpResponse.statusCode)
            }
            
            let attestationResponse = try JSONDecoder().decode(AttestationResponse.self, from: data)
            print("[Grantiva API] Successfully decoded attestation response")
            return attestationResponse
        } catch {
            print("[Grantiva API] Error: \(error)")
            if error is GrantivaError {
                throw error
            } else {
                throw GrantivaError.networkError(error)
            }
        }
    }
    
    /// Parses a Vapor-format error body `{"error":true,"reason":"..."}` for 4xx responses.
    /// 5xx responses never expose internals — falls back to `validationFailed`.
    private func parseServerError(from data: Data, statusCode: Int) -> GrantivaError {
        guard (400..<500).contains(statusCode) else {
            return .validationFailed
        }
        if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data),
           !errorResponse.reason.isEmpty {
            print("[Grantiva API] Server error (\(statusCode)): \(errorResponse.reason)")
            return .serverError(reason: errorResponse.reason)
        }
        return .validationFailed
    }

    /// Calls `POST /api/v1/attestation/refresh` with an assertion to get a new JWT.
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
                let body = String(data: data, encoding: .utf8) ?? ""
                print("[Grantiva API] Refresh failed (\(httpResponse.statusCode)): \(body)")
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
