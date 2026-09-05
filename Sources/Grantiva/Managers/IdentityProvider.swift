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

    /// Wire names consumed by the backend's DeviceFlagContext.
    var flagHeaders: [String: String] {
        let names = [
            "device_model": "X-Device-Model", "os_version": "X-OS-Version",
            "app_version": "X-App-Version", "locale": "X-Locale",
            "country": "X-Country", "user_id": "X-User-ID",
            "risk_score": "X-Risk-Score", "attestation_status": "X-Attestation-Status"
        ]
        var headers = ["X-Device-ID": deviceHash]
        for (key, value) in allProperties {
            // Custom property names become HTTP field names. Reject controls or
            // separators instead of allowing a property to inject headers.
            guard !key.isEmpty, key.utf8.allSatisfy({
                (65...90).contains($0) || (97...122).contains($0)
                    || (48...57).contains($0) || $0 == 45 || $0 == 95
            }), !value.contains("\r"), !value.contains("\n") else { continue }
            headers[names[key] ?? "X-Custom-\(key)"] = value
        }
        return headers
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
