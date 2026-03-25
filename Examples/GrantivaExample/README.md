# GrantivaExample

A minimal SwiftUI reference app demonstrating end-to-end integration of the [Grantiva SDK](https://grantiva.io).

## Get Running in 3 Steps

**1. Clone the repo**

```bash
git clone https://github.com/grantiva/super-duper-disco.git
cd super-duper-disco/GrantivaSDK/Examples/GrantivaExample
open GrantivaExample.xcodeproj
```

**2. Set your Team ID**

In `GrantivaExampleApp.swift`, replace `"YOUR_TEAM_ID"` with your Apple Developer Team ID.
Find it in [developer.apple.com](https://developer.apple.com) → Account → Membership.

**3. Run on a real device**

Select your iPhone in Xcode and hit Run (⌘R).

> **Simulator:** App Attest is not available in the iOS Simulator. The app detects this automatically and shows a friendly explanation. To test the unattested path on simulator, pass an `apiKey` to the `Grantiva` initializer (see comments in `GrantivaExampleApp.swift`).

---

## What this example shows

| Feature | File |
|---|---|
| SDK initialization | `GrantivaExampleApp.swift` |
| Attestation on launch | `ContentView.swift` → `attest()` |
| Simulator fallback | `ContentView.swift` → `.simulatorFallback` case |
| Device intelligence (risk score, jailbreak) | `ContentView.swift` → `deviceSection` |
| Feature flag evaluation | `ContentView.swift` → `fetchFlags()` |
| Error handling for all `GrantivaError` cases | `ContentView.swift` → `errorMessage(for:)` |

## Requirements

- Xcode 16+
- iOS 18+ deployment target
- A physical iOS device for full attestation (simulator shows graceful fallback)
- A Grantiva account — [sign up free at grantiva.io](https://grantiva.io)
