import Foundation

/// Handles all feedback-related API calls (feature requests + support tickets)
internal final class FeedbackAPIClient: @unchecked Sendable {
    private let configuration: GrantivaConfiguration
    private let transport: AuthenticatedTransport
    private let dateFormatter = ISO8601DateFormatter()

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

    // MARK: - Feature Requests

    func listFeatureRequests(status: FeatureRequestStatus? = nil, sort: String = "votes", page: Int = 1, per: Int = 20, voterId: String?) async throws -> [FeatureRequest] {
        var components = URLComponents(string: "\(configuration.baseURL)/api/v1/feedback/features")!
        var queryItems = [
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per", value: "\(per)")
        ]
        if let status = status {
            queryItems.append(URLQueryItem(name: "status", value: status.rawValue))
        }
        if let voterId = voterId {
            queryItems.append(URLQueryItem(name: "voter_id", value: voterId))
        }
        components.queryItems = queryItems

        let request = transport.request(url: components.url!, method: "GET")
        let data = try await transport.send(request)
        let response = try JSONDecoder().decode(PaginatedFeatureResponse.self, from: data)
        return response.items.compactMap { $0.toModel(dateFormatter: dateFormatter) }
    }

    func getFeatureRequest(id: UUID, voterId: String?) async throws -> FeatureRequest {
        var components = URLComponents(string: "\(configuration.baseURL)/api/v1/feedback/features/\(id)")!
        if let voterId = voterId {
            components.queryItems = [URLQueryItem(name: "voter_id", value: voterId)]
        }

        let request = transport.request(url: components.url!, method: "GET")
        let data = try await transport.send(request)
        let response = try JSONDecoder().decode(FeatureRequestResponse.self, from: data)
        guard let model = response.toModel(dateFormatter: dateFormatter) else {
            throw GrantivaError.invalidResponse
        }
        return model
    }

    func createFeatureRequest(title: String, description: String, submitterId: String, deviceHash: String, pushToken: String? = nil, pushEnvironment: String? = nil) async throws -> FeatureRequest {
        let url = URL(string: "\(configuration.baseURL)/api/v1/feedback/features")!
        let body = CreateFeatureRequestBody(title: title, description: description, submitterId: submitterId, deviceHash: deviceHash, pushToken: pushToken, pushEnvironment: pushEnvironment)
        let request = try transport.request(url: url, method: "POST", body: body)
        let data = try await transport.send(request)
        let response = try JSONDecoder().decode(FeatureRequestResponse.self, from: data)
        guard let model = response.toModel(dateFormatter: dateFormatter) else {
            throw GrantivaError.invalidResponse
        }
        return model
    }

    func vote(featureId: UUID, voterId: String, deviceHash: String) async throws -> Vote {
        let url = URL(string: "\(configuration.baseURL)/api/v1/feedback/features/\(featureId)/vote")!
        let body = VoteRequestBody(voterId: voterId, deviceHash: deviceHash)
        let request = try transport.request(url: url, method: "POST", body: body)
        let data = try await transport.send(request)
        let response = try JSONDecoder().decode(VoteResponse.self, from: data)
        guard let model = response.toModel(dateFormatter: dateFormatter) else {
            throw GrantivaError.invalidResponse
        }
        return model
    }

    func removeVote(featureId: UUID, voterId: String) async throws {
        var components = URLComponents(string: "\(configuration.baseURL)/api/v1/feedback/features/\(featureId)/vote")!
        components.queryItems = [URLQueryItem(name: "voter_id", value: voterId)]
        let request = transport.request(url: components.url!, method: "DELETE")
        _ = try await transport.send(request)
    }

    func listComments(featureId: UUID) async throws -> [FeatureComment] {
        let url = URL(string: "\(configuration.baseURL)/api/v1/feedback/features/\(featureId)/comments")!
        let request = transport.request(url: url, method: "GET")
        let data = try await transport.send(request)
        let responses = try JSONDecoder().decode([CommentResponse].self, from: data)
        return responses.compactMap { $0.toModel(dateFormatter: dateFormatter) }
    }

    func addComment(featureId: UUID, authorId: String, body: String, pushToken: String? = nil, pushEnvironment: String? = nil) async throws -> FeatureComment {
        let url = URL(string: "\(configuration.baseURL)/api/v1/feedback/features/\(featureId)/comments")!
        let commentBody = CreateCommentBody(authorId: authorId, body: body, pushToken: pushToken, pushEnvironment: pushEnvironment)
        let request = try transport.request(url: url, method: "POST", body: commentBody)
        let data = try await transport.send(request)
        let response = try JSONDecoder().decode(CommentResponse.self, from: data)
        guard let model = response.toModel(dateFormatter: dateFormatter) else {
            throw GrantivaError.invalidResponse
        }
        return model
    }

    // MARK: - Support Tickets

    func createTicket(subject: String, body: String, submitterId: String, submitterEmail: String?, deviceHash: String) async throws -> SupportTicket {
        let url = URL(string: "\(configuration.baseURL)/api/v1/support/tickets")!
        let ticketBody = CreateTicketBody(subject: subject, body: body, submitterId: submitterId, submitterEmail: submitterEmail, deviceHash: deviceHash)
        let request = try transport.request(url: url, method: "POST", body: ticketBody)
        let data = try await transport.send(request)
        let response = try JSONDecoder().decode(SupportTicketResponse.self, from: data)
        guard let model = response.toModel(dateFormatter: dateFormatter) else {
            throw GrantivaError.invalidResponse
        }
        return model
    }

    func listTickets(submitterId: String) async throws -> [SupportTicket] {
        var components = URLComponents(string: "\(configuration.baseURL)/api/v1/support/tickets")!
        components.queryItems = [URLQueryItem(name: "submitter_id", value: submitterId)]
        let request = transport.request(url: components.url!, method: "GET")
        let data = try await transport.send(request)
        let responses = try JSONDecoder().decode([SupportTicketResponse].self, from: data)
        return responses.compactMap { $0.toModel(dateFormatter: dateFormatter) }
    }

    func getTicket(id: UUID) async throws -> (SupportTicket, [TicketMessage]) {
        let url = URL(string: "\(configuration.baseURL)/api/v1/support/tickets/\(id)")!
        let request = transport.request(url: url, method: "GET")
        let data = try await transport.send(request)
        let response = try JSONDecoder().decode(TicketDetailResponse.self, from: data)
        guard let status = TicketStatus(rawValue: response.status),
              let priority = TicketPriority(rawValue: response.priority),
              let createdAt = dateFormatter.date(from: response.createdAt),
              let updatedAt = dateFormatter.date(from: response.updatedAt) else {
            throw GrantivaError.invalidResponse
        }
        let ticket = SupportTicket(
            id: response.id,
            subject: response.subject,
            status: status,
            priority: priority,
            messageCount: response.messages.count,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let messages = response.messages.compactMap { $0.toModel(dateFormatter: dateFormatter) }
        return (ticket, messages)
    }

    func addTicketMessage(ticketId: UUID, authorId: String, body: String) async throws -> TicketMessage {
        let url = URL(string: "\(configuration.baseURL)/api/v1/support/tickets/\(ticketId)/messages")!
        let messageBody = CreateTicketMessageBody(authorId: authorId, body: body)
        let request = try transport.request(url: url, method: "POST", body: messageBody)
        let data = try await transport.send(request)
        let response = try JSONDecoder().decode(TicketMessageResponse.self, from: data)
        guard let model = response.toModel(dateFormatter: dateFormatter) else {
            throw GrantivaError.invalidResponse
        }
        return model
    }
}
