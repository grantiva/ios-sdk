import Foundation

/// A "What's New" release note authored in the Grantiva dashboard and delivered
/// to this device on upgrade.
///
/// Notes are written per app version. The backend only returns a note to a device
/// that actually upgraded *past* the note's version and has not marked it seen, so
/// a fresh install never receives a backlog.
///
/// - Note: `body` is Markdown. Render it with `AttributedString(markdown:)` or a
///   Markdown view of your choosing — the SDK does not render it for you.
public struct ReleaseNote: Codable, Sendable, Identifiable {
    /// Server-assigned identifier. Pass this to ``WhatsNewService/markSeen(_:)``.
    public let id: UUID

    /// The app version this note announces, e.g. `"2.1.0"`, exactly as authored.
    public let version: String

    public let title: String

    /// Markdown body.
    public let body: String

    /// When the note was first published, or `nil` if the server did not record one.
    public let publishedAt: Date?

    public init(id: UUID, version: String, title: String, body: String, publishedAt: Date?) {
        self.id = id
        self.version = version
        self.title = title
        self.body = body
        self.publishedAt = publishedAt
    }
}
