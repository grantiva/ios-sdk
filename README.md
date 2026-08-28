# Grantiva iOS SDK

Device attestation, in-app feedback, support tickets, and feature flags for iOS apps. Built on Apple's App Attest — tenants are identified automatically by Bundle ID + Team ID, no API keys needed for attestation.

## Requirements

- iOS 18.0+ / macOS 15.0+
- Xcode 16.0+
- Swift 6.0+

## Installation

### Swift Package Manager

In Xcode: **File > Add Package Dependencies** and enter `https://github.com/grantiva/ios-sdk.git`

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/grantiva/ios-sdk.git", from: "1.0.0")
]
```

## Quick Start

```swift
import Grantiva

let grantiva = Grantiva(teamId: "YOUR_TEAM_ID")

// Attest the device — returns a JWT + device intelligence
let result = try await grantiva.validateAttestation()
print(result.token)                                    // JWT for your API calls
print(result.deviceIntelligence.riskScore ?? 0)       // 0–100 (nil in simulator/API key mode)
print(result.deviceIntelligence.riskCategory)         // .trusted / .suspicious / .blocked

// Identify the user (optional — scopes feedback and flag targeting)
await grantiva.identify("user_123")

// Feature requests
let features = try await grantiva.feedback.getFeatureRequests()
try await grantiva.feedback.vote(for: features[0].id)

// Support tickets
let ticket = try await grantiva.feedback.submitTicket(
    subject: "Can't login",
    body: "Getting error 403 on launch"
)

// Feature flags
if try await grantiva.flags.boolValue(for: "dark_mode") {
    enableDarkMode()
}
```

> **Simulator / CI:** App Attest is unavailable in the iOS Simulator. Pass an `apiKey`:
> ```swift
> let grantiva = Grantiva(teamId: "YOUR_TEAM_ID", apiKey: "your-dev-api-key")
> ```
> In this mode `riskScore` is `nil` and no attestation record appears in the dashboard.

## Attestation

```swift
// Token is cached automatically — subsequent calls return the cached value
if grantiva.isTokenValid() {
    let token = grantiva.getCurrentToken()
}

// Force a fresh attestation (re-runs full App Attest flow)
let fresh = try await grantiva.refreshToken()

// Clear stored keys and tokens (useful for testing fresh flows)
grantiva.clearStoredData()
```

### DeviceIntelligence

```swift
public struct DeviceIntelligence {
    public let deviceId: String
    public let riskScore: Int?             // nil in simulator/API key mode
    public let riskCategory: RiskCategory  // available on all tiers
    public let deviceIntegrity: String
    public let jailbreakDetected: Bool
    public let attestationCount: Int
    public let lastAttestationDate: Date?
}

public enum RiskCategory: String {
    case trusted     // score 0–20
    case suspicious  // score 21–75
    case blocked     // score 76–100
}
```

### What your backend receives

`DeviceIntelligence` above is the **HTTP response body** the SDK decodes. Separately, the SDK holds an
RS256-signed **JWT** — forward that as `Authorization: Bearer <token>` and your backend verifies it
against `https://api.grantiva.io/.well-known/jwks.json`.

The two are not the same shape. The JWT is flat and `snake_case`, and on paid plans it carries signed
device intelligence:

```json
{
  "sub": "<App Attest key id>",
  "iat": 1772107200,
  "exp": 1772110800,
  "iss": "<your organization's issuer>",
  "aud": "<your organization's audience>",
  "team_id": "ABBM6U9RM5",
  "bundle_id": "com.acme.app",
  "risk_score": 12,
  "device_integrity": "high",
  "jailbreak_detected": false,
  "attestation_count": 47,
  "custom_claims": { "user_tier": "premium" }
}
```

Three things to know before you write the verification code:

- There is **no `risk_category` claim in the JWT** — that field exists only in the response body above.
- `risk_score` is a **snapshot from when the token was issued**, and tokens live 1 hour by default. Treat
  it as advisory; re-attest before high-stakes actions.
- Which claims are present depends on your plan. The Free plan token carries no device intelligence.

Full per-plan claim table, decoded examples, and Node/Python verification code:
**https://docs.grantiva.io/concepts/jwt-claims**

## Subscriptions

Grantiva can attach a subscription entitlement to a **sharing unit** (e.g. a family/household)
and surface it in the attestation JWT as `custom_claims.subscription`. One paying member can
entitle every device in the unit.

Set the sharing-unit id **before attesting**, on **every** member's device:

```swift
grantiva.setSubjectId(familyId.uuidString)   // call before validateAttestation()
let result = try await grantiva.validateAttestation()
// result.token now carries custom_claims.subscription when an entitlement exists
```

The id is opaque and stable. Use the **same value** in all three places:

| Where | What |
| --- | --- |
| Grantiva SDK | `grantiva.setSubjectId(familyId)` |
| Apple purchase | `Product.PurchaseOption.appAccountToken(familyId)` |
| Stripe Checkout | `client_reference_id = familyId` |

Apple requires `appAccountToken` to be a `UUID`, so use a UUID string. Call `clearSubjectId()`
on sign-out / when leaving the unit. `setSubjectId` is distinct from `identify(_:)` — the latter
sets the individual user for feedback/flag scoping; the former sets the entitlement sharing unit.

Your **own backend** reads the entitlement by verifying the JWT against Grantiva's public JWKS
(`/.well-known/jwks.json`, RS256) and reading `custom_claims.subscription` — no API key required.

## Push Notifications

Register the device's APNs token so the backend can subscribe it to feedback threads
and push it when an admin replies to a feature you submitted or commented on.

Apple delivers the token to your `UIApplicationDelegate` — forward it to the SDK:

```swift
func application(_ app: UIApplication, didFinishLaunchingWithOptions opts: ...) -> Bool {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
        guard granted else { return }
        DispatchQueue.main.async { app.registerForRemoteNotifications() }
    }
    return true
}

func application(_ app: UIApplication,
                 didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    grantiva.setPushToken(deviceToken)            // environment auto-detected
}
```

Once a token is set, it's attached automatically to `feedback.submitFeatureRequest(...)`
and `feedback.addComment(...)` — the server subscribes the device to that feature's
thread. Nothing else to call.

```swift
grantiva.setPushToken(deviceToken, environment: .production)  // override detection
let token = grantiva.pushToken                                // currently registered token
grantiva.clearPushToken()                                     // on opt-out / unregister
```

The APNs environment defaults to `PushEnvironment.detected` (reads the provisioning
profile, falls back to the build configuration). Thread subscriptions require the org to
have a linked push app in the dashboard; without one the token is ignored server-side.

## Error Handling

```swift
do {
    let result = try await grantiva.validateAttestation()
} catch GrantivaError.deviceNotSupported {
    // App Attest unavailable (simulator, old device)
} catch GrantivaError.networkError(let underlying) {
    // Network issue
} catch GrantivaError.limitExceeded(let limit, let current) {
    // Tenant's Monthly Active Device limit reached
    // error.localizedDescription = "Monthly attestation limit reached (current/limit MAD). Upgrade at grantiva.io/upgrade."
    showUpgradePrompt()
} catch GrantivaError.rateLimited {
    // Too many requests
} catch GrantivaError.serverError(let reason) {
    // Server rejected the attestation
} catch {
    // Other errors
}
```

All error cases:

```swift
public enum GrantivaError: LocalizedError {
    case deviceNotSupported
    case attestationNotAvailable
    case networkError(Error)
    case validationFailed
    case tokenExpired
    case configurationError
    case keyGenerationFailed
    case challengeExpired
    case invalidResponse
    case rateLimited
    case feedbackNotAvailable
    case serverError(reason: String)
    /// Tenant's Monthly Active Device quota was exhausted.
    /// `localizedDescription` includes the current/limit counts and an upgrade URL.
    case limitExceeded(limit: Int, current: Int)
    case simulatorAPIKeyRequired
    case keyAlreadyAttested
    case assertionKeyInvalid
}
```

## Security

- Keys and tokens stored in Keychain with device-only accessibility
- JWT tokens cached until near expiration, refreshed automatically
- App Attest keys are per-device, non-exportable
- No sensitive data in logs; all communication over TLS

## Pricing

| Plan | MAD / month | Apps | Custom Claims | Support |
|------|-------------|------|---------------|---------|
| **Free** | 1,000 | 2 | — | Community |
| **Pro** | 25,000 | 3 | 5 | Email |
| **Business** | 250,000 | 10 | 10 | Priority |
| **Enterprise** | Unlimited | Unlimited | 20 | Dedicated + SLA |

Full pricing at [grantiva.io/pricing](https://grantiva.io/pricing).

## Support

- [Full documentation](https://docs.grantiva.io)
- [GitHub Issues](https://github.com/grantiva/ios-sdk/issues)
- Email: support@grantiva.com

## License

MIT License. See [LICENSE](LICENSE) for details.
