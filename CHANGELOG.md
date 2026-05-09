# Changelog

## 2.0.1 — 2026-05-09

### Bug Fixes

- `validateAttestation()` now self-heals when the server's stored attestation has diverged from the on-device App Attest key. Previously, refresh failures (rpIdHash drift on multi-app orgs, or on-device key replacement after restore-from-backup) returned a generic 401 and the SDK retried indefinitely. The backend now returns HTTP 409 with code `reattest_required`; the SDK drops the cached attested-flag and token, requests a fresh challenge, and runs the full attest path once before surfacing the failure. Requires backend with [grantiva/super-duper-disco#167](https://github.com/grantiva/super-duper-disco/pull/167).
- New `GrantivaError.reattestRequired` case (informational — the SDK handles this internally and only surfaces it if the recovery attest also fails).
- Lifecycle-related `Task` capture made Sendable-safe (#16).
- `DeviceIntelligence` now persists across token refresh in the keychain (#15).
- All SDK API requests now send the attestation JWT (or API key) header consistently (#14).

---

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

