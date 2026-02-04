import Foundation

/// Handles all feedback-related API calls (feature requests + support tickets)
internal final class FeedbackAPIClient: @unchecked Sendable {
    private let configuration: GrantivaConfiguration
    private let session: URLSession
    private let teamId: String
    private let dateFormatter: ISO8601DateFormatter

    init(configuration: GrantivaConfiguration, teamId: String) {
        self.configuration = configuration
        self.teamId = teamId
        self.dateFormatter = ISO8601DateFormatter()

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        sessionConfig.timeoutIntervalForResource = configuration.timeout
        self.session = URLSession(configuration: sessionConfig)
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

        let request = makeRequest(url: components.url!, method: "GET")
        let data = try await perform(request)
        let response = try JSONDecoder().decode(PaginatedFeatureResponse.self, from: data)
        return response.items.compactMap { $0.toModel(dateFormatter: dateFormatter) }
    }

    func getFeatureRequest(id: UUID, voterId: String?) async throws -> FeatureRequest {
        var components = URLComponents(string: "\(configuration.baseURL)/api/v1/feedback/features/\(id)")!
        if let voterId = voterId {
            components.queryItems = [URLQueryItem(name: "voter_id", value: voterId)]
        }

        let request = makeRequest(url: components.url!, method: "GET")
        let data = try await perform(request)
        let response = try JSONDecoder().decode(FeatureRequestResponse.self, from: data)
        guard let model = response.toModel(dateFormatter: dateFormatter) else {
            throw GrantivaError.invalidResponse
        }
        return model
    }

    func createFeatureRequest(title: String, description: String, submitterId: String, deviceHash: String) async throws -> FeatureRequest {
        let url = URL(string: "\(configuration.baseURL)/api/v1/feedback/features")!
        let body = CreateFeatureRequestBody(title: title, description: description, submitterId: submitterId, deviceHash: deviceHash)
        let request = try makeRequest(url: url, method: "POST", body: body)
        let data = try await perform(request)
        let response = try JSONDecoder().decode(FeatureRequestResponse.self, from: data)
        guard let model = response.toModel(dateFormatter: dateFormatter) else {
            throw GrantivaError.invalidResponse
        }
        return model
    }

    func vote(featureId: UUID, voterId: String, deviceHash: String) async throws -> Vote {
        let url = URL(string: "\(configuration.baseURL)/api/v1/feedback/features/\(featureId)/vote")!
        let body = VoteRequestBody(voterId: voterId, deviceHash: deviceHash)
        let request = try makeRequest(url: url, method: "POST", body: body)
        let data = try await perform(request)
        let response = try JSONDecoder().decode(VoteResponse.self, from: data)
        guard let model = response.toModel(dateFormatter: dateFormatter) else {
            throw GrantivaError.invalidResponse
        }
        return model
    }

    func removeVote(featureId: UUID, voterId: String) async throws {
        var components = URLComponents(string: "\(configuration.baseURL)/api/v1/feedback/features/\(featureId)/vote")!
        components.queryItems = [URLQueryItem(name: "voter_id", value: voterId)]
        let request = makeRequest(url: components.url!, method: "DELETE")
        _ = try await perform(request)
    }

    func listComments(featureId: UUID) async throws -> [FeatureComment] {
        let url = URL(string: "\(configuration.baseURL)/api/v1/feedback/features/\(featureId)/comments")!
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request)
        let responses = try JSONDecoder().decode([CommentResponse].self, from: data)
        return responses.compactMap { $0.toModel(dateFormatter: dateFormatter) }
    }

    func addComment(featureId: UUID, authorId: String, body: String) async throws -> FeatureComment {
        let url = URL(string: "\(configuration.baseURL)/api/v1/feedback/features/\(featureId)/comments")!
        let commentBody = CreateCommentBody(authorId: authorId, body: body)
        let request = try makeRequest(url: url, method: "POST", body: commentBody)
        let data = try await perform(request)
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
        let request = try makeRequest(url: url, method: "POST", body: ticketBody)
        let data = try await perform(request)
        let response = try JSONDecoder().decode(SupportTicketResponse.self, from: data)
        guard let model = response.toModel(dateFormatter: dateFormatter) else {
            throw GrantivaError.invalidResponse
        }
        return model
    }

    func listTickets(submitterId: String) async throws -> [SupportTicket] {
        var components = URLComponents(string: "\(configuration.baseURL)/api/v1/support/tickets")!
        components.queryItems = [URLQueryItem(name: "submitter_id", value: submitterId)]
        let request = makeRequest(url: components.url!, method: "GET")
        let data = try await perform(request)
        let responses = try JSONDecoder().decode([SupportTicketResponse].self, from: data)
        return responses.compactMap { $0.toModel(dateFormatter: dateFormatter) }
    }

    func getTicket(id: UUID) async throws -> (SupportTicket, [TicketMessage]) {
        let url = URL(string: "\(configuration.baseURL)/api/v1/support/tickets/\(id)")!
        let request = makeRequest(url: url, method: "GET")
        let data = try await perform(request)
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
        let request = try makeRequest(url: url, method: "POST", body: messageBody)
        let data = try await perform(request)
        let response = try JSONDecoder().decode(TicketMessageResponse.self, from: data)
        guard let model = response.toModel(dateFormatter: dateFormatter) else {
            throw GrantivaError.invalidResponse
        }
        return model
    }

    // MARK: - Request Helpers

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = configuration.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue(getBundleId(), forHTTPHeaderField: "X-Bundle-ID")
            request.setValue(teamId, forHTTPHeaderField: "X-Team-ID")
        }
        return request
    }

    private func makeRequest<T: Encodable>(url: URL, method: String, body: T) throws -> URLRequest {
        var request = makeRequest(url: url, method: method)
        request.httpBody = try JSONEncoder().encode(body)
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
            if error is GrantivaError {
                throw error
            }
            throw GrantivaError.networkError(error)
        }
    }

    private func getBundleId() -> String {
        Bundle.main.bundleIdentifier ?? ""
    }
}
