import Foundation

/// Shared identity state accessible by all Grantiva services.
///
/// When a user context is set via `grantiva.identify(...)`, all services
/// use it for scoping requests. When no user is identified, services fall back
/// to device-based identity.
internal final class IdentityProvider: @unchecked Sendable {
    /// The full user context, or `nil` if not identified.
    private(set) var userContext: UserContext?

    /// The entitlement sharing-unit id (e.g. a family/household id), or `nil` if unset.
    ///
    /// Distinct from `userId`: a sharing unit can contain several users (e.g. a family where
    /// one member pays and everyone is entitled). Sent to Grantiva at attest/refresh so the
    /// device links to its `Subject` and inherits the subscription claim. The host app must use
    /// the SAME value as the Apple StoreKit `appAccountToken` and the Stripe Checkout
    /// `client_reference_id`.
    private(set) var subjectId: String?

    /// The developer-provided user ID, or `nil` if not identified.
    var userId: String? {
        userContext?.userId
    }

    /// Whether a user has been identified.
    var isIdentified: Bool {
        userContext != nil
    }

    /// The effective submitter ID: user ID if identified, otherwise device hash.
    var effectiveSubmitterId: String {
        userId ?? DeviceHasher.generateSubmitterId()
    }

    /// The effective voter ID: user ID if identified, otherwise device-based voter hash.
    var effectiveVoterId: String {
        userId ?? DeviceHasher.generateVoterId()
    }

    /// The device hash (always device-based, used for spam prevention regardless of identity).
    var deviceHash: String {
        DeviceHasher.generateDeviceHash()
    }

    /// All context properties merged (device + user properties + user_id).
    /// Returns device-only context when no user is identified.
    var allProperties: [String: String] {
        if let context = userContext {
            return context.allProperties
        }
        // Device-only context when not identified
        return DeviceContext.current().toDictionary()
    }

    func identify(_ context: UserContext) {
        self.userContext = context
        Logger.info("User identified: \(context.userId) with \(context.properties.count) custom properties")
    }

    func clearIdentity() {
        let previous = userId
        userContext = nil
        if let previous = previous {
            Logger.info("Identity cleared (was: \(previous))")
        }
    }

    func setSubjectId(_ subjectId: String?) {
        self.subjectId = subjectId
        if let subjectId {
            Logger.info("Subject id set: \(subjectId)")
        } else {
            Logger.info("Subject id cleared")
        }
    }
}
