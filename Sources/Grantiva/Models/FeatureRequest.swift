import Foundation

/// Represents a feature request submitted by app users
public struct FeatureRequest: Sendable, Codable, Identifiable {
    public let id: UUID
    public let title: String
    public let description: String
    public let status: FeatureRequestStatus
    public let voteCount: Int
    public let hasVoted: Bool
    public let commentCount: Int
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: UUID, title: String, description: String, status: FeatureRequestStatus, voteCount: Int, hasVoted: Bool, commentCount: Int, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.voteCount = voteCount
        self.hasVoted = hasVoted
        self.commentCount = commentCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// The status of a feature request
public enum FeatureRequestStatus: String, Sendable, Codable, CaseIterable {
    case pending
    case open
    case planned
    case inProgress = "in_progress"
    case shipped
    case declined
    case duplicate
}

/// A vote on a feature request
public struct Vote: Sendable, Codable {
    public let id: UUID
    public let featureRequestId: UUID
    public let createdAt: Date

    public init(id: UUID, featureRequestId: UUID, createdAt: Date) {
        self.id = id
        self.featureRequestId = featureRequestId
        self.createdAt = createdAt
    }
}

/// A comment on a feature request
public struct FeatureComment: Sendable, Codable, Identifiable {
    public let id: UUID
    public let featureRequestId: UUID
    public let authorType: CommentAuthorType
    public let body: String
    public let createdAt: Date

    public init(id: UUID, featureRequestId: UUID, authorType: CommentAuthorType, body: String, createdAt: Date) {
        self.id = id
        self.featureRequestId = featureRequestId
        self.authorType = authorType
        self.body = body
        self.createdAt = createdAt
    }
}

/// Whether a comment was authored by a user or an admin
public enum CommentAuthorType: String, Sendable, Codable {
    case user
    case admin
}
