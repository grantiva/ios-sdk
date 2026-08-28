import Foundation

/// Handles all "What's New" API calls (release note delivery + seen-state).
internal final class WhatsNewAPIClient: @unchecked Sendable {
    private let configuration: GrantivaConfiguration
    private let session: URLSession
    private let teamId: String
    private let getToken: @Sendable () -> String?

    init(configuration: GrantivaConfiguration, teamId: String, getToken: @escaping @Sendable () -> String? = { nil }) {
        self.configuration = configuration
        self.teamId = teamId
        self.getToken = getToken

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        sessionConfig.timeoutIntervalForResource = configuration.timeout
        self.session = URLSession(configuration: sessionConfig)
    }

    /// Internal seam: injects a pre-built `URLSession` so tests can install a stub
    /// `URLProtocol`. Not part of the public API; production code uses the
    /// `init(configuration:teamId:getToken:)` overload.
    init(
        configuration: GrantivaConfiguration,
        teamId: String,
        getToken: @escaping @Sendable () -> String? = { nil },
        session: URLSession
    ) {
        self.configuration = configuration
        self.teamId = teamId
        self.getToken = getToken
        self.session = session
    }

    // MARK: - Release Notes

    /// Fetch the release notes this device should be shown, newest version first.
    ///
    /// Retried via `RetryManager`. This is a side-effect-free `GET` whose response is
    /// derived entirely from server state, so a duplicate request costs one extra read
    /// and nothing else — the same reasoning that makes the attestation challenge the
    /// one retried endpoint on `GrantivaAPIClient`.
    func fetchReleaseNotes() async throws -> [ReleaseNote] {
        let url = URL(string: "\(configuration.baseURL)/api/v1/whats-new")!
        let request = makeRequest(url: url, method: "GET")

        let data = try await RetryManager.executeWithRetry(
            maxAttempts: max(1, configuration.retryAttempts),
            baseDelay: configuration.retryBaseDelay
        ) { [self] in
            try await perform(request)
        }

        let response = try Self.makeDecoder().decode(WhatsNewResponse.self, from: data)
        return response.releaseNotes
    }

    /// Mark one release note as seen for this device.
    ///
    /// Retried via `RetryManager`. Unlike `validateAttestation`, this `POST` consumes no
    /// one-shot resource: the server upserts a single `(release_note_id, device_profile_id)`
    /// row behind a unique index and returns the *original* `seenAt` on a repeat, so a
    /// replayed request after an ambiguous transport failure is a genuine no-op. Not
    /// retrying would leave the note unmarked and re-shown on the next launch, which is
    /// the worse outcome of the two.
    func markSeen(_ id: UUID) async throws {
        let url = URL(string: "\(configuration.baseURL)/api/v1/whats-new/\(id.uuidString)/seen")!
        let request = makeRequest(url: url, method: "POST")

        _ = try await RetryManager.executeWithRetry(
            maxAttempts: max(1, configuration.retryAttempts),
            baseDelay: configuration.retryBaseDelay
        ) { [self] in
            try await perform(request)
        }
    }

    // MARK: - Decoding

    /// The backend encodes dates with Vapor's default JSON content configuration,
    /// which is `.iso8601` (internet date-time, no fractional seconds).
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Wire shape of `GET /api/v1/whats-new`.
    private struct WhatsNewResponse: Decodable {
        let releaseNotes: [ReleaseNote]
    }

    // MARK: - Request Helpers

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Always send Bundle ID + Team ID — release notes are authored per app, and the
        // backend rejects the request without them. Auth precedence: attestation JWT
        // (real device) > API key (simulator/dev). The backend rejects requests with neither.
        request.setValue(getBundleId(), forHTTPHeaderField: "X-Bundle-ID")
        request.setValue(teamId, forHTTPHeaderField: "X-Team-ID")
        if let token = getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let apiKey = configuration.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
