import Foundation

/// Holds the device's current APNs push token so services that subscribe a device
/// to server-side push channels (currently feedback threads) can attach it to their
/// requests.
///
/// The token is supplied by the host app via `grantiva.setPushToken(_:environment:)`
/// — it arrives in `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`,
/// which only the app's `UIApplicationDelegate` receives, so the SDK can't capture it
/// on its own. Held in memory only; APNs reissues the token on each launch, so there's
/// nothing worth persisting.
internal final class PushTokenStore: @unchecked Sendable {
    private let lock = NSLock()
    private var _token: String?
    private var _environment: PushEnvironment?

    /// The current hex-encoded APNs device token, or `nil` if none has been set.
    var token: String? {
        lock.lock(); defer { lock.unlock() }
        return _token
    }

    /// The environment the current token was minted for, or `nil` if none has been set.
    var environment: PushEnvironment? {
        lock.lock(); defer { lock.unlock() }
        return _environment
    }

    /// Stores a hex-encoded token + environment.
    func set(token: String, environment: PushEnvironment) {
        lock.lock(); defer { lock.unlock() }
        _token = token
        _environment = environment
    }

    /// Clears the stored token (e.g. after the app unregisters for remote notifications).
    func clear() {
        lock.lock(); defer { lock.unlock() }
        _token = nil
        _environment = nil
    }
}
