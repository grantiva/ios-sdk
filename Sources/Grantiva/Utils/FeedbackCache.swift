import Foundation

/// Thread-safe in-memory cache for feedback data with TTL-based expiration.
internal final class FeedbackCache: @unchecked Sendable {

    private struct CacheEntry<T> {
        let value: T
        let expiresAt: Date

        var isExpired: Bool {
            Date() > expiresAt
        }
    }

    private var featureRequests: CacheEntry<[FeatureRequest]>?
    private var featureDetails: [UUID: CacheEntry<FeatureRequest>] = [:]
    private var comments: [UUID: CacheEntry<[FeatureComment]>] = [:]
    private var tickets: CacheEntry<[SupportTicket]>?

    private let queue = DispatchQueue(label: "com.grantiva.feedback.cache", attributes: .concurrent)

    /// Default TTL for list data (2 minutes)
    private let listTTL: TimeInterval = 120

    /// Default TTL for detail data (5 minutes)
    private let detailTTL: TimeInterval = 300

    // MARK: - Feature Requests

    func getCachedFeatureRequests() -> [FeatureRequest]? {
        queue.sync {
            guard let entry = featureRequests, !entry.isExpired else {
                return nil
            }
            return entry.value
        }
    }

    func cacheFeatureRequests(_ requests: [FeatureRequest]) {
        queue.async(flags: .barrier) {
            self.featureRequests = CacheEntry(value: requests, expiresAt: Date().addingTimeInterval(self.listTTL))
        }
    }

    func getCachedFeatureRequest(id: UUID) -> FeatureRequest? {
        queue.sync {
            guard let entry = featureDetails[id], !entry.isExpired else {
                return nil
            }
            return entry.value
        }
    }

    func cacheFeatureRequest(_ request: FeatureRequest) {
        queue.async(flags: .barrier) {
            self.featureDetails[request.id] = CacheEntry(value: request, expiresAt: Date().addingTimeInterval(self.detailTTL))
        }
    }

    // MARK: - Comments

    func getCachedComments(featureId: UUID) -> [FeatureComment]? {
        queue.sync {
            guard let entry = comments[featureId], !entry.isExpired else {
                return nil
            }
            return entry.value
        }
    }

    func cacheComments(_ commentList: [FeatureComment], featureId: UUID) {
        queue.async(flags: .barrier) {
            self.comments[featureId] = CacheEntry(value: commentList, expiresAt: Date().addingTimeInterval(self.listTTL))
        }
    }

    // MARK: - Tickets

    func getCachedTickets() -> [SupportTicket]? {
        queue.sync {
            guard let entry = tickets, !entry.isExpired else {
                return nil
            }
            return entry.value
        }
    }

    func cacheTickets(_ ticketList: [SupportTicket]) {
        queue.async(flags: .barrier) {
            self.tickets = CacheEntry(value: ticketList, expiresAt: Date().addingTimeInterval(self.listTTL))
        }
    }

    // MARK: - Invalidation

    /// Invalidate all cached feature request data (call after vote, create, etc.)
    func invalidateFeatureRequests() {
        queue.async(flags: .barrier) {
            self.featureRequests = nil
            self.featureDetails.removeAll()
            self.comments.removeAll()
        }
    }

    /// Invalidate all cached ticket data (call after create, reply, etc.)
    func invalidateTickets() {
        queue.async(flags: .barrier) {
            self.tickets = nil
        }
    }

    /// Clear all cached data
    func clearAll() {
        queue.async(flags: .barrier) {
            self.featureRequests = nil
            self.featureDetails.removeAll()
            self.comments.removeAll()
            self.tickets = nil
        }
    }
}
