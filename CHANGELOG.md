# Changelog

## 2.0.4 — 2026-05-10

### Features

- `validateAttestation()` now sends a stable hashed device fingerprint with every attestation (#21). The backend uses this as a secondary key for MAD lookup so the same physical device counts once toward billing even when its App Attest key is regenerated mid-month by the 2.0.3 self-heal path. Requires backend with [grantiva/super-duper-disco#174](https://github.com/grantiva/super-duper-disco/pull/174).
- New `PlatformSupport.getDeviceFingerprint()` helper (internal): hex SHA256 of `identifierForVendor` (iOS) / `IOPlatformSerialNumber` (macOS). The raw identifier never leaves the device — only the hash, which is opaque to the server.

### Privacy note

We hash the device identifier client-side and only send the digest. The server cannot recover the raw IDFV from the hash, so the on-wire value is a stable opaque token usable only for matching attestations from the same device.

---

## 2.0.3 — 2026-05-10

### Bug Fixes

- `validateAttestation()` now self-heals when Apple rejects `attestKey()` with `DCError.invalidInput` (code 2) — the error App Attest returns when a keyId has already been attested in a prior session and cannot be re-attested (#20). The SDK clears the stored keyId, generates a fresh one, requests a new challenge, and retries once before surfacing failure. Closes a hole in the 2.0.1 `reattestRequired` self-heal, which cleared the `attested` flag but kept the keyId — sending the next attestation straight into this error.
- New `GrantivaError.keyAlreadyAttested` case (informational — handled internally by the retry path; surfaces only if the second attestation also fails).

### Known Issue

- Self-heal cycles count as a new MAD on the backend because `DeviceProfile` is keyed by `(organization_id, keyId)`. Same physical device with a regenerated keyId currently counts twice in the month the heal occurs. Follow-up planned to dedupe via device fingerprint in `getOrCreateDeviceProfile`.

---

## 2.0.2 — 2026-05-10

### Bug Fixes

- `AttestationManager` now logs the underlying `DCErrorDomain` code + description before rethrowing `GrantivaError.validationFailed` (#19). Previously, all App Attest failures collapsed to a generic error with no diagnostic info, making real-device attestation failures impossible to triage from the app console.

### Developer Experience

- New `GrantivaError.simulatorAPIKeyRequired` case (#18). `validateAttestation()` on the iOS Simulator without an `apiKey` now throws this targeted error immediately and points at `Grantiva(teamId:apiKey:)` + the simulator setup docs, instead of falling through to a generic `deviceNotSupported`. The previous misleading "Using API key fallback" warning that appeared even when no API key was set has been removed.

---

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

