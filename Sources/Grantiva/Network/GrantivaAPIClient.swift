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
        request.setValue(getBundleId(), forHTTPHeaderField: "X-Bundle-ID")
        request.setValue(teamId, forHTTPHeaderField: "X-Team-ID")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GrantivaError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw GrantivaError.networkError(NSError(domain: "HTTPError", code: httpResponse.statusCode))
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
        httpRequest.setValue(getBundleId(), forHTTPHeaderField: "X-Bundle-ID")
        httpRequest.setValue(teamId, forHTTPHeaderField: "X-Team-ID")
        
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
            
            if httpResponse.statusCode != 200 {
                let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                print("[Grantiva API] Error response body: \(responseBody)")
                
                // Try to decode error response
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    print("[Grantiva API] Server error: \(errorResponse.reason)")
                }
            }
            
            guard httpResponse.statusCode == 200 else {
                throw GrantivaError.validationFailed
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
    
    private func getBundleId() -> String {
        return Bundle.main.bundleIdentifier ?? ""
    }
    
}
