# Grantiva iOS SDK Development Notes

## Project Overview
This is a comprehensive iOS SDK for device attestation using Apple's App Attest framework. The SDK provides secure device attestation with automatic tenant identification via Bundle ID and Team ID. It also includes `FeedbackService` (feature requests + support tickets) and `FlagService` (remote feature flags) as lazy properties on the main `Grantiva` class.

## Architecture

### Core Components
- **Grantiva.swift**: Main SDK interface class
- **AttestationManager**: Handles App Attest operations
- **KeyManager**: Manages cryptographic keys in Keychain
- **TokenManager**: Handles JWT token storage and lifecycle
- **HeartbeatManager**: Sends periodic heartbeats after attestation
- **IdentityProvider**: Tracks optional user identity for flag targeting
- **GrantivaAPIClient**: Network layer for attestation API communication
- **FeedbackAPIClient**: Network layer for feedback/support API
- **FlagAPIClient**: Network layer for feature flag API
- **HeartbeatAPIClient**: Network layer for heartbeat API

### Key Features
1. Device attestation using Apple's App Attest
2. Secure token management with Keychain storage
3. Automatic token refresh
4. Device intelligence and risk scoring
5. Retry logic for network operations
6. Feature requests and support tickets via `FeedbackService`
7. Remote feature flags via `FlagService` with local caching
8. User identity for targeting via `identify()` / `clearIdentity()`

## Development Guidelines

### Code Style
- Swift 6 language mode (Package.swift `swift-tools-version: 6.0`, iOS 18+ / macOS 15+)
- Async/await pattern for asynchronous operations
- Comprehensive error handling with GrantivaError enum
- Platform-specific code using conditional compilation

### Testing
- Unit tests in Tests/GrantivaTests/
- Mock managers for testing
- Device compatibility checks

### Security Considerations
- All sensitive data stored in Keychain
- JWT tokens cached securely
- No sensitive information in logs
- Server-side validation of attestations

## API Structure

### Initialization
```swift
let grantiva = Grantiva(teamId: "YOUR_TEAM_ID")

// Simulator / CI — App Attest unavailable, falls back to API key auth
let grantiva = Grantiva(teamId: "YOUR_TEAM_ID", apiKey: "your-api-key")

// Flag cache TTL (default 300s; pass 0 to disable caching)
await grantiva.flags.setCacheTTL(60)
```

### Main Methods
- `validateAttestation()`: Performs full attestation flow, returns `AttestationResult`
- `refreshToken()`: Returns the current attestation, re-attesting first only if the stored token has expired (`nil` if never attested)
- `getCurrentToken()`: Returns cached token if valid
- `isTokenValid()`: Checks token validity
- `clearStoredData()`: Clears all stored attestation data (for testing)
- `identify(_ context: UserContext)`: Sets user identity for flag targeting
- `identify(_ userId: String)`: Sets user identity by ID only
- `clearIdentity()`: Clears current user identity
- `currentUserId`: Currently identified user ID (read-only)
- `currentUserContext`: Full user context (read-only)

### Services (Lazy Properties)

#### Feedback Service
```swift
// Feature requests
let features = try await grantiva.feedback.getFeatureRequests()
try await grantiva.feedback.vote(for: feature.id)

// Support tickets
let ticket = try await grantiva.feedback.submitTicket(subject: "Help", body: "Details...")
let tickets = try await grantiva.feedback.getUsersTickets()
```

#### Feature Flags Service
```swift
let flags = try await grantiva.flags.getFlags()
if flags["dark_mode"]?.boolValue == true { enableDarkMode() }
let limit = try await grantiva.flags.intValue(for: "upload_limit", default: 10)
```

#### What's New Service
```swift
for note in try await grantiva.whatsNew.getReleaseNotes() {
    show(note)
    try await grantiva.whatsNew.markSeen(note.id)
}
```

### Authenticated transport
`FeedbackAPIClient`, `FlagAPIClient` and `WhatsNewAPIClient` send requests through `AuthenticatedTransport`, which adds the tenant headers, prefers a non-expired JWT over the API key, renews an expired JWT via `BackgroundTokenRefresher` before sending, and answers a 401 with one refresh + one retry. `HeartbeatManager` and `FlagSSEClient` do the same on their own sessions. Concurrent refreshes are collapsed by `TokenRefreshCoordinator`.

## File Structure
```
GrantivaSDK/
├── Sources/Grantiva/
│   ├── Grantiva.swift (Main SDK class)
│   ├── Managers/
│   │   ├── AttestationManager.swift
│   │   ├── FeedbackService.swift
│   │   ├── FlagService.swift
│   │   ├── HeartbeatManager.swift
│   │   ├── IdentityProvider.swift
│   │   ├── KeyManager.swift
│   │   ├── PushTokenStore.swift
│   │   ├── TokenManager.swift
│   │   ├── TokenRefreshCoordinator.swift
│   │   └── WhatsNewService.swift
│   ├── Models/
│   │   ├── AttestationResult.swift
│   │   ├── DeviceIntelligence.swift
│   │   ├── FeatureRequest.swift
│   │   ├── FlagModels.swift
│   │   ├── GrantivaConfiguration.swift
│   │   ├── GrantivaError.swift
│   │   ├── PushEnvironment.swift
│   │   ├── ReleaseNote.swift
│   │   ├── SupportTicket.swift
│   │   └── UserContext.swift
│   ├── Network/
│   │   ├── AuthenticatedTransport.swift
│   │   ├── FeedbackAPIClient.swift
│   │   ├── FeedbackNetworkModels.swift
│   │   ├── FlagAPIClient.swift
│   │   ├── FlagPayloadParser.swift
│   │   ├── FlagSSEClient.swift
│   │   ├── GrantivaAPIClient.swift
│   │   ├── HeartbeatAPIClient.swift
│   │   ├── NetworkModels.swift
│   │   └── WhatsNewAPIClient.swift
│   └── Utils/
│       ├── DeviceCompatibility.swift
│       ├── DeviceHasher.swift
│       ├── DeviceIntelligenceExtractor.swift
│       ├── FeedbackCache.swift
│       ├── Logger.swift
│       ├── PlatformSupport.swift
│       └── RetryManager.swift
├── Tests/
├── Examples/
└── docs/ (Internal documentation)
```

## Current Implementation Status

### Completed
- ✅ Core attestation flow
- ✅ Token management with caching
- ✅ Keychain integration
- ✅ Device compatibility checks
- ✅ Error handling
- ✅ Basic example app
- ✅ Unit test structure
- ✅ FeedbackService (feature requests + support tickets)
- ✅ FlagService (remote feature flags with local cache)
- ✅ User identity for flag targeting

## Testing

### Running Tests
```bash
swift test
```

### Building
```bash
swift build
```

### Example App
Located in Examples/BasicIntegration/
- Demonstrates basic SDK integration
- SwiftUI-based interface
- Shows attestation flow and token management

## API Endpoints
The SDK communicates with the Grantiva backend:
- Challenge request: GET /api/v1/attestation/challenge
- Attestation validation: POST /api/v1/attestation/validate
- Assertion refresh: POST /api/v1/attestation/refresh
- Heartbeat: POST /api/v1/heartbeat
- Feature requests: GET/POST /api/v1/feedback/features
- Support tickets: GET/POST /api/v1/support/tickets
- Feature flags: GET /api/v1/flags, SSE GET /api/v1/flags/stream
- What's New: GET /api/v1/whats-new, POST /api/v1/whats-new/:id/seen

## Notes for Development
1. Always test attestation on real devices (App Attest not available in simulator)
2. Ensure Bundle ID and Team ID are correctly configured
3. Token expiration is handled automatically
4. Use `clearStoredData()` for testing fresh attestation flows
5. Check DeviceCompatibility before attestation attempts
6. `FeedbackService` and `FlagService` are lazily initialized on first access
7. User identity set via `identify()` persists until `clearIdentity()` is called

## Common Development Tasks

### Adding New Features
1. Update models if needed
2. Implement in appropriate manager class
3. Expose through main Grantiva class
4. Add unit tests
5. Update example app if applicable

### Debugging
- Use Console.app to view os_log output (subsystem `com.grantiva.sdk`)
- Check Keychain access for token storage issues
- Verify network requests in GrantivaAPIClient

### Release Checklist
- [ ] Run the **Release** workflow (bumps `Version.swift`, tags, publishes)
- [ ] Run all tests
- [ ] Test on various iOS versions
- [ ] Update README if API changes
- [ ] Tag release in git
- [ ] Update documentation
