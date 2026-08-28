import Foundation

/// Delivers version-targeted "What's New" release notes to this device.
///
/// Access via `grantiva.whatsNew`:
/// ```swift
/// let notes = try await grantiva.whatsNew.getReleaseNotes()
/// for note in notes {
///     show(note)                                  // note.body is Markdown
///     try await grantiva.whatsNew.markSeen(note.id)
/// }
/// ```
///
/// ### What you get back
///
/// Only notes this device should actually see: published, for a version the device
/// **upgraded past**, and not yet marked seen. Newest version first. The device's app
/// version is read server-side from its attested device profile — the SDK does not
/// send it, and there is nothing to configure.
///
/// A fresh install therefore receives an empty list: with nothing to upgrade *from*,
/// there is no news to announce. Only an upgrade opens the window.
///
/// ### Simulator limitation
///
/// **This feature always returns an empty list in the iOS Simulator**, and on any other
/// unattested (API-key) client. Release notes are keyed to the attested device profile
/// that records which version the device installed at and which it runs now; a simulator
/// never attests, so no such profile exists and the server correctly has nothing to
/// deliver. This is not an error, and the SDK does not fabricate placeholder notes to
/// paper over it — an empty list is the honest answer. Exercise the feature on a real
/// device that has been upgraded across a published note's version.
///
/// Notes are cached in-memory with a configurable TTL (default: 5 minutes).
/// Pass `forceRefresh: true` to bypass the cache.
public actor WhatsNewService {
    private let apiClient: WhatsNewAPIClient

    /// Cache TTL in seconds. Defaults to 5 minutes.
    public var cacheTTL: TimeInterval = 300

    // In-memory cache
    private var cachedNotes: [ReleaseNote]?
    private var cacheExpiry: Date?

    internal init(apiClient: WhatsNewAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Public API

    /// Fetch the release notes this device should be shown, newest version first.
    ///
    /// Returns cached values if available and not expired.
    ///
    /// Returns an empty array whenever there is nothing to show — a fresh install, every
    /// note already seen, or an unattested client such as the iOS Simulator (see the type
    /// documentation). Empty is a normal result, not an error.
    ///
    /// - Parameter forceRefresh: Pass `true` to bypass the cache.
    /// - Returns: The unseen release notes for this device, newest version first.
    public func getReleaseNotes(forceRefresh: Bool = false) async throws -> [ReleaseNote] {
        if !forceRefresh, let cached = cachedNotes, let expiry = cacheExpiry, Date() < expiry {
            return cached
        }

        let notes = try await apiClient.fetchReleaseNotes()
        cachedNotes = notes
        cacheExpiry = Date().addingTimeInterval(cacheTTL)
        return notes
    }

    /// Mark a release note as seen for this device, so it is never delivered again.
    ///
    /// Idempotent — calling it twice for the same note is safe and leaves the original
    /// seen timestamp intact. The note is also dropped from the local cache so the next
    /// ``getReleaseNotes(forceRefresh:)`` no longer returns it, cached or not.
    ///
    /// - Parameter id: The ``ReleaseNote/id`` of the note the user has seen.
    public func markSeen(_ id: UUID) async throws {
        try await apiClient.markSeen(id)
        cachedNotes = cachedNotes?.filter { $0.id != id }
    }

    /// Clear all cached release notes.
    ///
    /// Rarely needed: seen-state lives server-side and is keyed to the attested device,
    /// not to the identified user, so release notes are unaffected by `identify(_:)`.
    public func clearCache() {
        cachedNotes = nil
        cacheExpiry = nil
    }

    // MARK: - Internal

    /// Internal seam: ``cacheTTL`` is actor-isolated and so cannot be assigned from
    /// outside the actor. Tests use this to exercise expiry deterministically.
    /// Not part of the public API.
    internal func setCacheTTL(_ ttl: TimeInterval) {
        cacheTTL = ttl
    }
}
