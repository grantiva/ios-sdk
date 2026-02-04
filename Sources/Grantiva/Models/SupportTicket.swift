import Foundation

/// Represents a private support ticket
public struct SupportTicket: Sendable, Codable, Identifiable {
    public let id: UUID
    public let subject: String
    public let status: TicketStatus
    public let priority: TicketPriority
    public let messageCount: Int
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: UUID, subject: String, status: TicketStatus, priority: TicketPriority, messageCount: Int, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.subject = subject
        self.status = status
        self.priority = priority
        self.messageCount = messageCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// The status of a support ticket
public enum TicketStatus: String, Sendable, Codable, CaseIterable {
    case open
    case awaitingReply = "awaiting_reply"
    case resolved
    case closed
}

/// The priority level of a support ticket
public enum TicketPriority: String, Sendable, Codable, CaseIterable {
    case low
    case normal
    case high
    case urgent
}

/// A message within a support ticket conversation
public struct TicketMessage: Sendable, Codable, Identifiable {
    public let id: UUID
    public let ticketId: UUID
    public let authorType: CommentAuthorType
    public let body: String
    public let createdAt: Date

    public init(id: UUID, ticketId: UUID, authorType: CommentAuthorType, body: String, createdAt: Date) {
        self.id = id
        self.ticketId = ticketId
        self.authorType = authorType
        self.body = body
        self.createdAt = createdAt
    }
}
