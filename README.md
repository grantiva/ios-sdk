# Grantiva iOS SDK

A comprehensive iOS SDK for device attestation using Apple's App Attest framework. The SDK provides secure device attestation with automatic tenant identification via Bundle ID and Team ID.

## Features

- 🔒 **Simple Setup**: Team ID-based configuration
- 🛡️ **Security First**: Server-side validation with secure local storage
- 📱 **Cross-Platform**: Supports both iOS and macOS
- 🔄 **Intelligent Caching**: Automatic token management and refresh
- 🎯 **Error Resilience**: Graceful handling with retry logic
- 📊 **Device Intelligence**: Comprehensive device risk assessment

## Requirements

- iOS 14.0+ / macOS 11.0+
- Xcode 12.0+
- Swift 5.3+

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/grantiva/grantiva-ios-sdk.git", from: "1.0.0")
]
```

Or add it through Xcode:
1. File → Add Package Dependencies
2. Enter the repository URL
3. Select the version and add to your target

## Quick Start

```swift
import Grantiva

class SecurityManager {
    private let grantiva = Grantiva(teamId: "YOUR_TEAM_ID")
    
    func authenticateDevice() async {
        do {
            let result = try await grantiva.validateAttestation()
            
            if result.isValid {
                // Use the token for API requests
                let token = result.token
                
                // Check device risk
                if result.deviceIntelligence.riskScore > 50 {
                    // Handle high-risk device
                    handleHighRiskDevice()
                }
                
                // Make authenticated API calls
                await makeAuthenticatedRequest(token: token)
            }
        } catch {
            handleAttestationError(error)
        }
    }
}
```

## API Reference

### Main SDK Class

#### `Grantiva`

The primary interface for device attestation.

```swift
public class Grantiva {
    public init(teamId: String)
    
    public func validateAttestation() async throws -> AttestationResult
    public func refreshToken() async throws -> AttestationResult?
    public func getCurrentToken() -> String?
    public func isTokenValid() -> Bool
    public func clearStoredData()
}
```

### Models

#### `AttestationResult`

Contains the result of an attestation validation.

```swift
public struct AttestationResult {
    public let isValid: Bool
    public let token: String
    public let expiresAt: Date
    public let deviceIntelligence: DeviceIntelligence
    public let customClaims: [String: Any]
}
```

#### `DeviceIntelligence`

Provides comprehensive device risk assessment.

```swift
public struct DeviceIntelligence {
    public let deviceId: String
    public let riskScore: Int // 0-100
    public let deviceIntegrity: String
    public let jailbreakDetected: Bool
    public let attestationCount: Int
    public let lastAttestationDate: Date?
}
```

#### `GrantivaError`

Comprehensive error handling for all SDK operations.

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
}
```

## Advanced Usage

### Token Management

```swift
// Check if current token is valid
if grantiva.isTokenValid() {
    let token = grantiva.getCurrentToken()
    // Use existing token
} else {
    // Refresh or get new token
    let result = try await grantiva.refreshToken()
}
```

### Error Handling

```swift
do {
    let result = try await grantiva.validateAttestation()
    // Handle success
} catch GrantivaError.deviceNotSupported {
    // Handle unsupported device
} catch GrantivaError.networkError(let error) {
    // Handle network issues
} catch {
    // Handle other errors
}
```

### Team ID Configuration

```swift
// Initialize with your Apple Developer Team ID
let grantiva = Grantiva(teamId: "YOUR_TEAM_ID")
```

## Device Support

- **iOS 14.0+**: Full App Attest support
- **macOS 11.0+**: Limited support (App Attest availability varies)
- **Simulator**: Graceful degradation with appropriate error messages

## Security Considerations

- All sensitive data is stored in the Keychain with device-only accessibility
- JWT tokens are cached securely until near expiration
- App Attest keys are generated and stored per device
- No sensitive information is logged

## Troubleshooting

### Common Issues

1. **Device Not Supported**: App Attest requires iOS 14+ and is not available in simulators
2. **Network Errors**: Check internet connectivity and server availability
3. **Token Expired**: SDK automatically handles token refresh

### Debug Logging

The SDK uses `os.log` for comprehensive logging. Enable in Xcode Console or use Console.app to view logs.

## Example Projects

Check the `Examples/` directory for complete integration examples:

- `BasicIntegration/`: Simple SwiftUI app demonstrating core functionality

## API Documentation

For complete API documentation, see the inline documentation in the source code or generate documentation using Swift-DocC.

## Pricing

Visit [grantiva.io](https://grantiva.io) for current pricing and plan details.

## Support

- **Documentation**: [[docs.grantiva.com](https://docs.grantiva.com)](https://grantiva.io/documentation)
- **Email**: support@grantiva.com
- **Issues**: Please open an issue on GitHub
- **Sales**: sales@grantiva.com

## License

This SDK is available under the MIT License. See LICENSE file for details.
