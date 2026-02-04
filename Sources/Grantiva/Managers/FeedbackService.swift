import Foundation

/// Provides access to feature requests and support tickets.
///
/// Access via `grantiva.feedback`:
/// ```swift
/// let features = try await grantiva.feedback.getFeatureRequests()
/// try await grantiva.feedback.vote(for: feature.id)
/// ```
public actor FeedbackService {
    private let apiClient: FeedbackAPIClient
    private let cache: FeedbackCache
    private let identity: IdentityProvider

    internal init(apiClient: FeedbackAPIClient, identity: IdentityProvider) {
        self.apiClient = apiClient
        self.cache = FeedbackCache()
        self.identity = identity
    }

    // MARK: - Feature Requests

    /// Fetch all visible feature requests, optionally filtered by status.
    ///
    /// Results are cached for 2 minutes. Use `refreshFeatureRequests()` to force a fresh fetch.
    ///
    /// - Parameters:
    ///   - status: Optional status filter. Pass `nil` for all statuses.
    ///   - sort: Sort order: `"votes"` (default), `"newest"`, or `"oldest"`.
    ///   - page: Page number (1-based). Defaults to 1.
    ///   - perPage: Results per page. Defaults to 20.
    /// - Returns: An array of feature requests.
    public func getFeatureRequests(
        status: FeatureRequestStatus? = nil,
        sort: String = "votes",
        page: Int = 1,
        perPage: Int = 20
    ) async throws -> [FeatureRequest] {
        // Return cached if available and no specific filters
        if status == nil && sort == "votes" && page == 1 && perPage == 20,
           let cached = cache.getCachedFeatureRequests() {
            return cached
        }

        let requests = try await apiClient.listFeatureRequests(
            status: status,
            sort: sort,
            page: page,
            per: perPage,
            voterId: identity.effectiveVoterId
        )

        // Cache default requests
        if status == nil && sort == "votes" && page == 1 && perPage == 20 {
            cache.cacheFeatureRequests(requests)
        }

        return requests
    }

    /// Fetch a single feature request by ID.
    ///
    /// - Parameter id: The feature request UUID.
    /// - Returns: The feature request with current vote/comment counts.
    public func getFeatureRequest(id: UUID) async throws -> FeatureRequest {
        if let cached = cache.getCachedFeatureRequest(id: id) {
            return cached
        }

        let request = try await apiClient.getFeatureRequest(id: id, voterId: identity.effectiveVoterId)
        cache.cacheFeatureRequest(request)
        return request
    }

    /// Submit a new feature request.
    ///
    /// - Parameters:
    ///   - title: Title of the feature request (3-200 characters).
    ///   - description: Detailed description (10-5000 characters).
    /// - Returns: The created feature request.
    public func submitFeatureRequest(title: String, description: String) async throws -> FeatureRequest {
        let result = try await apiClient.createFeatureRequest(
            title: title,
            description: description,
            submitterId: identity.effectiveSubmitterId,
            deviceHash: identity.deviceHash
        )
        cache.invalidateFeatureRequests()
        return result
    }

    /// Vote for a feature request. Each user/device can only vote once per feature.
    ///
    /// - Parameter featureId: The feature request UUID to vote for.
    /// - Returns: The vote confirmation.
    @discardableResult
    public func vote(for featureId: UUID) async throws -> Vote {
        let result = try await apiClient.vote(
            featureId: featureId,
            voterId: identity.effectiveVoterId,
            deviceHash: identity.deviceHash
        )
        cache.invalidateFeatureRequests()
        return result
    }

    /// Remove a previously cast vote from a feature request.
    ///
    /// - Parameter featureId: The feature request UUID to remove the vote from.
    public func removeVote(for featureId: UUID) async throws {
        try await apiClient.removeVote(featureId: featureId, voterId: identity.effectiveVoterId)
        cache.invalidateFeatureRequests()
    }

    /// Get comments for a feature request.
    ///
    /// - Parameter featureId: The feature request UUID.
    /// - Returns: An array of comments, newest first.
    public func getComments(for featureId: UUID) async throws -> [FeatureComment] {
        if let cached = cache.getCachedComments(featureId: featureId) {
            return cached
        }

        let comments = try await apiClient.listComments(featureId: featureId)
        cache.cacheComments(comments, featureId: featureId)
        return comments
    }

    /// Add a comment to a feature request.
    ///
    /// - Parameters:
    ///   - featureId: The feature request UUID.
    ///   - body: The comment text (1-2000 characters).
    /// - Returns: The created comment.
    @discardableResult
    public func addComment(to featureId: UUID, body: String) async throws -> FeatureComment {
        let result = try await apiClient.addComment(
            featureId: featureId,
            authorId: identity.effectiveSubmitterId,
            body: body
        )
        cache.invalidateFeatureRequests()
        return result
    }

    /// Force refresh feature request cache on next fetch.
    public func refreshFeatureRequests() {
        cache.invalidateFeatureRequests()
    }

    // MARK: - Support Tickets

    /// Submit a new support ticket.
    ///
    /// - Parameters:
    ///   - subject: Ticket subject (3-200 characters).
    ///   - body: Initial message body (10-5000 characters).
    ///   - email: Optional contact email for replies.
    /// - Returns: The created ticket.
    public func submitTicket(subject: String, body: String, email: String? = nil) async throws -> SupportTicket {
        let result = try await apiClient.createTicket(
            subject: subject,
            body: body,
            submitterId: identity.effectiveSubmitterId,
            submitterEmail: email,
            deviceHash: identity.deviceHash
        )
        cache.invalidateTickets()
        return result
    }

    /// Get all tickets submitted by the current user (or device if not identified).
    ///
    /// If `grantiva.identify("user_123")` has been called, returns tickets for that user
    /// across all their devices. Otherwise returns tickets from this device only.
    ///
    /// - Returns: An array of support tickets.
    public func getUsersTickets() async throws -> [SupportTicket] {
        if let cached = cache.getCachedTickets() {
            return cached
        }

        let tickets = try await apiClient.listTickets(submitterId: identity.effectiveSubmitterId)
        cache.cacheTickets(tickets)
        return tickets
    }

    /// Get a single ticket with its full conversation history.
    ///
    /// - Parameter id: The ticket UUID.
    /// - Returns: A tuple of the ticket and its messages.
    public func getTicket(id: UUID) async throws -> (ticket: SupportTicket, messages: [TicketMessage]) {
        return try await apiClient.getTicket(id: id)
    }

    /// Reply to a support ticket.
    ///
    /// - Parameters:
    ///   - ticketId: The ticket UUID.
    ///   - body: The reply message body.
    /// - Returns: The created message.
    @discardableResult
    public func reply(to ticketId: UUID, body: String) async throws -> TicketMessage {
        let result = try await apiClient.addTicketMessage(
            ticketId: ticketId,
            authorId: identity.effectiveSubmitterId,
            body: body
        )
        cache.invalidateTickets()
        return result
    }

    /// Force refresh ticket cache on next fetch.
    public func refreshTickets() {
        cache.invalidateTickets()
    }

    /// Clear all cached feedback data.
    public func clearCache() {
        cache.clearAll()
    }
}
