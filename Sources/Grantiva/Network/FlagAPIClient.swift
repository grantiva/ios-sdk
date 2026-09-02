import Foundation

/// Handles all feature flag API calls.
internal final class FlagAPIClient: @unchecked Sendable {
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

    /// Fetch all flags for the current tenant and environment.
    ///
    /// The backend returns `{ "flags": { "key": typedValue, ... } }` where values are
    /// natively typed (bools, ints, doubles, strings, objects); see `FlagPayloadParser`.
    func fetchFlags(environment: FlagEnvironment) async throws -> [String: FlagValue] {
        var components = URLComponents(string: "\(configuration.baseURL)/api/v1/flags")!
        components.queryItems = [
            URLQueryItem(name: "environment", value: environment.rawValue)
        ]

        let request = transport.request(url: components.url!, method: "GET")
        let data = try await transport.send(request)

        guard let flags = FlagPayloadParser.parse(data) else {
            throw GrantivaError.invalidResponse
        }
        return flags
    }
}
