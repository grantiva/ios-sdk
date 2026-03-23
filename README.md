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
} catch GrantivaError.serverError(let reason) {
    // Server rejected the attestation
} catch {
    // See GrantivaError for all cases
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
| **Free** | 1,000 | 1 | — | Community |
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
