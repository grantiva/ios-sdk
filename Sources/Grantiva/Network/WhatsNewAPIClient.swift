import Foundation

/// Handles all "What's New" API calls (release note delivery + seen-state).
internal final class WhatsNewAPIClient: @unchecked Sendable {
    private let configuration: GrantivaConfiguration
    private let transport: AuthenticatedTransport

    /// - Parameters:
    ///   - getToken: Returns the current non-expired attestation JWT, or `nil`.
    ///   - refreshToken: Renews the JWT when it has expired or been rejected. `nil` in API key mode.
    ///   - session: Internal seam so tests can install a stub `URLProtocol`.
    init(
        configuration: GrantivaConfiguration,
        teamId: String,
        getToken: @escaping @Sendable () -> String? = { nil },
        refreshToken: (@Sendable () async -> Bool)? = nil,
        session: URLSession? = nil
    ) {
        self.configuration = configuration
        self.transport = AuthenticatedTransport(
            configuration: configuration,
            teamId: teamId,
            getToken: getToken,
            refreshToken: refreshToken,
            session: session
        )
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
        let request = transport.request(url: url, method: "GET")

        let data = try await RetryManager.executeWithRetry(
            maxAttempts: max(1, configuration.retryAttempts),
            baseDelay: configuration.retryBaseDelay
        ) { [self] in
            try await transport.send(request)
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
        let request = transport.request(url: url, method: "POST")

        _ = try await RetryManager.executeWithRetry(
            maxAttempts: max(1, configuration.retryAttempts),
            baseDelay: configuration.retryBaseDelay
        ) { [self] in
            try await transport.send(request)
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
}
