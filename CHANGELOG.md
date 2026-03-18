# Changelog

## 2.0.0 — 2026-03-18

### BREAKING CHANGES

- **`DeviceIntelligence.riskScore` is now `Int?`** (was `Int`). This value is `nil` when risk scoring is unavailable — simulator builds, API key mode (Free tier), and cached tokens issued before risk scoring was available. **Migration:** Guard against nil before displaying. Example: `score.map { "\$0/100" } ?? "N/A"`.
- **`DeviceIntelligenceResponse.riskScore` is now `Int?`** in the network layer, matching the public API.

### New Features

- Simulator warning log: when running in the iOS Simulator, the SDK now emits a prominent warning at `init()` and `validateAttestation()` time:
  `[Grantiva] ⚠️ Running in simulator — App Attest unavailable. Using API key fallback. riskScore will be nil. Test on a real device to verify full attestation.`
- README: Added **Simulator vs Device** section documenting expected behaviour differences.

### Bug Fixes

- Example app `ContentView` no longer renders `"nil/100"` for risk score — displays `"N/A (simulator or Free tier)"` when nil.

---

## 1.0.4 — 2026-03-10

Internal improvements and attestation reliability fixes.

## 1.0.0 — 2026-03-01

Initial public release.

