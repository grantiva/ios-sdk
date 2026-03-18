# Grantiva iOS SDK

The iOS developer platform for device attestation, in-app feedback, support tickets, and feature flags. One SDK, one line of setup.

Built on Apple's App Attest API. No API keys needed for device attestation — tenants are identified automatically by Bundle ID + Team ID.

## Requirements

- iOS 18.0+ / macOS 15.0+
- Xcode 16.0+
- Swift 6.0+

## Installation

### Swift Package Manager

Add the package in Xcode:

1. File > Add Package Dependencies
2. Enter: `https://github.com/grantiva/ios-sdk.git`
3. Select your version and add to your target

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

// Attest the device and get a JWT token
let result = try await grantiva.validateAttestation()
print(result.token)                          // JWT for your API calls
print(result.deviceIntelligence.riskScore)   // 0-100 risk score

// Identify the user (optional — enables per-user feedback, flags, etc.)
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

> App Attest is not available in the iOS Simulator. Pass an `apiKey` for development builds:
> ```swift
> let grantiva = Grantiva(teamId: "YOUR_TEAM_ID", apiKey: "your-dev-api-key")
> ```

## Simulator vs Device

App Attest is not available in the iOS Simulator. When running in the simulator:

- `riskScore` will be `nil` — always guard against nil before displaying
- No attestation record appears in the dashboard — this is expected
- The JWT issued is a synthetic fallback token (not cryptographically attested)

To test full attestation, run on a **real device** with your Team ID configured.

For CI/CD or server-to-server use cases where a real device is unavailable, initialise with an API key:

```swift
let grantiva = Grantiva(teamId: "YOUR_TEAM_ID", apiKey: "your-api-key")
```

## Attestation

```swift
let grantiva = Grantiva(teamId: "YOUR_TEAM_ID")

// Full attestation flow: challenge → App Attest → server validation → JWT
let result = try await grantiva.validateAttestation()

// Token is cached automatically — subsequent calls return the cache
if grantiva.isTokenValid() {
    let token = grantiva.getCurrentToken()
}

// Force a fresh attestation
let fresh = try await grantiva.refreshToken()

// Clear all stored keys and tokens (useful for testing)
grantiva.clearStoredData()
```

### AttestationResult

```swift
public struct AttestationResult {
    public let isValid: Bool
    public let token: String               // JWT for your API requests
    public let expiresAt: Date
    public let deviceIntelligence: DeviceIntelligence
    public let customClaims: [String: Any] // Tier-dependent custom claims
}
```

### DeviceIntelligence

```swift
public struct DeviceIntelligence {
    public let deviceId: String
    public let riskScore: Int              // 0-100
    public let deviceIntegrity: String
    public let jailbreakDetected: Bool
    public let attestationCount: Int
    public let lastAttestationDate: Date?
}
```

Risk score ranges: 0-20 (trusted), 21-50 (medium), 51-75 (high), 76-100 (block).

## Identity

Associate a user with the Grantiva instance. All services (feedback, flags) will scope to this user.

```swift
// Simple
await grantiva.identify("user_123")

// With properties (used for flag targeting, feedback context)
await grantiva.identify(UserContext(
    userId: "user_123",
    properties: [
        "plan": "premium",
        "country": "US"
    ]
))

// On logout
await grantiva.clearIdentity()

// Check current state
grantiva.currentUserId        // "user_123" or nil
grantiva.currentUserContext    // Full UserContext or nil
```

Device context (model, OS, app version, locale, etc.) is collected automatically.

## Feedback

### Feature Requests

```swift
// List feature requests (sorted by votes by default)
let features = try await grantiva.feedback.getFeatureRequests()
let planned = try await grantiva.feedback.getFeatureRequests(status: .planned)

// Get a single request with details
let feature = try await grantiva.feedback.getFeatureRequest(id: someId)

// Submit a new request
let newFeature = try await grantiva.feedback.submitFeatureRequest(
    title: "Dark mode support",
    description: "It would be great to have a dark theme option."
)

// Vote / unvote
try await grantiva.feedback.vote(for: feature.id)
try await grantiva.feedback.removeVote(for: feature.id)

// Comments
let comments = try await grantiva.feedback.getComments(for: feature.id)
try await grantiva.feedback.addComment(to: feature.id, body: "Great idea!")
```

### Support Tickets

```swift
// Submit a ticket
let ticket = try await grantiva.feedback.submitTicket(
    subject: "Payment issue",
    body: "I was charged twice this month.",
    email: "user@example.com"  // optional
)

// List the user's tickets
let tickets = try await grantiva.feedback.getUsersTickets()

// Get ticket with conversation
let (ticket, messages) = try await grantiva.feedback.getTicket(id: ticketId)

// Reply
try await grantiva.feedback.reply(to: ticketId, body: "Any update on this?")
```

### Statuses

Feature requests: `pending`, `open`, `planned`, `inProgress`, `shipped`, `declined`, `duplicate`

Tickets: `open`, `awaitingReply`, `resolved`, `closed`

## Feature Flags

```swift
// Get all flags
let flags = try await grantiva.flags.getFlags()

// Typed accessors with defaults
let darkMode = try await grantiva.flags.boolValue(for: "dark_mode", default: false)
let limit = try await grantiva.flags.intValue(for: "upload_limit", default: 10)
let ratio = try await grantiva.flags.doubleValue(for: "sample_rate", default: 0.5)
let banner = try await grantiva.flags.stringValue(for: "promo_banner", default: "")

// Raw flag value
if let flag = try await grantiva.flags.value(for: "dark_mode") {
    print(flag.boolValue)    // Optional<Bool>
    print(flag.rawValue)     // "true"
    print(flag.valueType)    // .boolean
}

// Force refresh (bypasses cache)
let fresh = try await grantiva.flags.getFlags(forceRefresh: true)

// Cache TTL defaults to 5 minutes
grantiva.flags.cacheTTL = 60  // 1 minute
```

Flag value types: `boolean`, `integer`, `double`, `string`, `json`.

## Error Handling

```swift
do {
    let result = try await grantiva.validateAttestation()
} catch GrantivaError.deviceNotSupported {
    // App Attest unavailable (simulator, old device)
} catch GrantivaError.networkError(let underlying) {
    // Network issue
} catch GrantivaError.rateLimited {
    // Too many requests
} catch GrantivaError.feedbackNotAvailable {
    // Feedback not enabled for this tier
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
}
```

## Security

- Attestation keys and tokens stored in Keychain with device-only accessibility
- JWT tokens cached until near expiration, refreshed automatically
- App Attest keys are per-device, non-exportable
- No sensitive data logged in production
- All communication over TLS

## Pricing

| Plan | MAD | Apps | Custom Claims | Support |
|------|-----|------|---------------|---------|
| **Free** | 1,000 | 1 | - | Community |
| **Pro** | 25,000 | 3 | 5 | Email |
| **Business** | 250,000 | 10 | 10 | Priority |
| **Enterprise** | Unlimited | Unlimited | 20 | Dedicated + SLA |

See [grantiva.io/pricing](https://grantiva.io/pricing) for current pricing.

## Support

- [Documentation](https://grantiva.io/documentation)
- [GitHub Issues](https://github.com/grantiva/ios-sdk/issues)
- Email: support@grantiva.com

## License

MIT License. See [LICENSE](LICENSE) for details.
