import Foundation

// MARK: - Feature Request API Models

internal struct CreateFeatureRequestBody: Codable {
    let title: String
    let description: String
    let submitterId: String
    let deviceHash: String
}

internal struct VoteRequestBody: Codable {
    let voterId: String
    let deviceHash: String
}

internal struct CreateCommentBody: Codable {
    let authorId: String
    let body: String
}

internal struct FeatureRequestResponse: Codable {
    let id: UUID
    let title: String
    let description: String
    let status: String
    let voteCount: Int
    let hasVoted: Bool
    let commentCount: Int
    let createdAt: String
    let updatedAt: String
}

internal struct VoteResponse: Codable {
    let id: UUID
    let featureRequestId: UUID
    let createdAt: String
}

internal struct CommentResponse: Codable {
    let id: UUID
    let featureRequestId: UUID
    let authorType: String
    let body: String
    let createdAt: String
}

internal struct PaginatedFeatureResponse: Codable {
    let items: [FeatureRequestResponse]
    let metadata: PaginationMetadata
}

internal struct PaginationMetadata: Codable {
    let page: Int
    let per: Int
    let total: Int
}

// MARK: - Support Ticket API Models

internal struct CreateTicketBody: Codable {
    let subject: String
    let body: String
    let submitterId: String
    let submitterEmail: String?
    let deviceHash: String
}

internal struct CreateTicketMessageBody: Codable {
    let authorId: String
    let body: String
}

internal struct SupportTicketResponse: Codable {
    let id: UUID
    let subject: String
    let status: String
    let priority: String
    let messageCount: Int
    let createdAt: String
    let updatedAt: String
}

internal struct TicketDetailResponse: Codable {
    let id: UUID
    let subject: String
    let status: String
    let priority: String
    let messages: [TicketMessageResponse]
    let createdAt: String
    let updatedAt: String
}

internal struct TicketMessageResponse: Codable {
    let id: UUID
    let ticketId: UUID
    let authorType: String
    let body: String
    let createdAt: String
}

// MARK: - Conversion Helpers

extension FeatureRequestResponse {
    func toModel(dateFormatter: ISO8601DateFormatter) -> FeatureRequest? {
        guard let createdAt = dateFormatter.date(from: createdAt),
              let updatedAt = dateFormatter.date(from: updatedAt),
              let status = FeatureRequestStatus(rawValue: status) else {
            return nil
        }
        return FeatureRequest(
            id: id,
            title: title,
            description: description,
            status: status,
            voteCount: voteCount,
            hasVoted: hasVoted,
            commentCount: commentCount,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension VoteResponse {
    func toModel(dateFormatter: ISO8601DateFormatter) -> Vote? {
        guard let createdAt = dateFormatter.date(from: createdAt) else { return nil }
        return Vote(id: id, featureRequestId: featureRequestId, createdAt: createdAt)
    }
}

extension CommentResponse {
    func toModel(dateFormatter: ISO8601DateFormatter) -> FeatureComment? {
        guard let createdAt = dateFormatter.date(from: createdAt),
              let authorType = CommentAuthorType(rawValue: authorType) else {
            return nil
        }
        return FeatureComment(
            id: id,
            featureRequestId: featureRequestId,
            authorType: authorType,
            body: body,
            createdAt: createdAt
        )
    }
}

extension SupportTicketResponse {
    func toModel(dateFormatter: ISO8601DateFormatter) -> SupportTicket? {
        guard let createdAt = dateFormatter.date(from: createdAt),
              let updatedAt = dateFormatter.date(from: updatedAt),
              let status = TicketStatus(rawValue: status),
              let priority = TicketPriority(rawValue: priority) else {
            return nil
        }
        return SupportTicket(
            id: id,
            subject: subject,
            status: status,
            priority: priority,
            messageCount: messageCount,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension TicketMessageResponse {
    func toModel(dateFormatter: ISO8601DateFormatter) -> TicketMessage? {
        guard let createdAt = dateFormatter.date(from: createdAt),
              let authorType = CommentAuthorType(rawValue: authorType) else {
            return nil
        }
        return TicketMessage(
            id: id,
            ticketId: ticketId,
            authorType: authorType,
            body: body,
            createdAt: createdAt
        )
    }
}
