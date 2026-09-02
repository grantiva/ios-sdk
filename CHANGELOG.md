# Changelog

## Unreleased

### Bug Fixes

- Feedback, flags and What's New calls no longer fail after the attestation JWT expires. They previously sent whatever token was stored — expired or not — and every call after the one-hour expiry came back `validationFailed` until the app happened to call `validateAttestation()` again. The three clients now share the same plumbing the heartbeat and flag stream got in 2.1.x: an expired token is renewed before the request goes out, and a 401 on a token the SDK believed valid is answered with one refresh and one retry.
- A cold launch with a still-valid cached token now starts the heartbeat and the SSE flag stream. `validateAttestation()` returned early on the cached path without bringing either up, so live presence and real-time flags silently stayed off until the token expired or the app was backgrounded and resumed. The assertion-refresh path had the same gap for the flag stream.
- Heartbeats now report the SDK version in `sdkVersion`; they were sending the host app's marketing version.
- Heartbeats honour the server's `nextHeartbeatSeconds`, floored at 10s, instead of ignoring it.
- `DCError.serverUnavailable` (code 4) from `attestKey` / `generateAssertion` now surfaces as `GrantivaError.networkError` — a transient Apple-side failure the app can retry — instead of the terminal `validationFailed`.
- `RetryManager` no longer retries HTTP 4xx responses from the What's New client; only 5xx and 408 are treated as transient.
- macOS: the hardware model is read from `hw.model` (`hw.machine` reports the CPU architecture there), the serial-number lookup uses the non-deprecated `kIOMainPortDefault`, and a leaked `CFString` from `IORegistryEntryCreateCFProperty` is released.
- `IdentityProvider` guards its state with a lock; `identify(_:)` from the main thread raced reads from the service actors.
- `HeartbeatManager` and `FlagSSEClient` cancel their tasks on `deinit`, and `Grantiva` stops both on `deinit`. Previously a released `HeartbeatManager` left its timer task sleeping forever.

### Improvements

- `FlagService.setCacheTTL(_:)` and `WhatsNewService.setCacheTTL(_:)` — `cacheTTL` is actor-isolated, so it could be read but never assigned from outside the actor. The setter closes that gap; the property is now `public private(set)`.
- `DeviceIntelligence`, `RiskCategory`, `UserContext`, `DeviceContext` and `GrantivaError` are now `Sendable`; `AttestationResult` is `@unchecked Sendable`. All additive.
- `refreshToken()` returns the stored `DeviceIntelligence` from the last attestation instead of a placeholder when the token is still valid.
- Removed dead code: `CustomClaimsProcessor`, `DeviceIntelligenceExtractor`'s local risk heuristics, `DeviceCompatibility.getDeviceInfo`, `KeyManager.clearAttestedFlag`, and the unused `KeyManager` inside `AttestationManager`. None were reachable from the public API.

### Features

- What's New: new `grantiva.whatsNew` service delivering version-targeted release notes — `getReleaseNotes(forceRefresh:)`, `markSeen(_:)`, and `clearCache()`, plus the `ReleaseNote` model. The backend returns only the notes this device should see (published, for a version the device upgraded *past*, not yet marked seen), newest first; the device's app version is read server-side from its attested profile, so there is nothing to send or configure. Notes are cached in-memory for 5 minutes by default. Additive and backward compatible. **Unattested clients (iOS Simulator, API-key builds) always receive an empty list** — release notes are keyed to the attested device profile, which a simulator never creates.

---

## 2.1.0 — 2026-06-22

### Features

- Subscription entitlements: new `setSubjectId(_:)` / `clearSubjectId()` / `subjectId` API to associate a device with an entitlement **sharing unit** (e.g. a family/household). The id is sent on attestation and assertion-refresh requests so the backend links the device to its `Subject` and projects `custom_claims.subscription` into the JWT — letting one paying member entitle every device in the unit. Use the same value as the Apple StoreKit `appAccountToken` and the Stripe Checkout `client_reference_id`. Optional and backward compatible; distinct from `identify(_:)` (which scopes the individual user for feedback/flags). See the Subscriptions section in the README.

---

## 2.0.6 — 2026-06-10

### Bug Fixes

- Fixed the flag SSE stream churning in a 30-second connect/timeout/reconnect loop. The streaming session's `timeoutIntervalForRequest` was set to 30s under the assumption it was a connect timeout — it is an idle timeout (time between received bytes), so any quiet period on the stream killed the connection with NSURLError -1001. The idle timeout is now 75s, sized to ~3 missed server keepalives (the backend now emits a `: keepalive` SSE comment every 20s — requires backend with keepalive support). A genuine 75s silence still fires the timeout so dead connections (network drop without a FIN) are detected and reconnected.
- Reconnect backoff now resets after a healthy connection (≥60s uptime) drops. Previously the backoff only reset on a clean server close, so devices on flaky networks compounded delays from failures hours apart and crept to a permanent 30s reconnect delay.

---

## 2.0.5 — 2026-06-10

### Bug Fixes

- `validateAttestation()` now self-heals when Apple rejects `generateAssertion()` with `DCError.invalidInput` (code 2) or `DCError.invalidKey` (code 3) — the errors App Attest returns when the stored keyId references a Secure Enclave key that can no longer produce assertions (backup restore/device transfer, or local "attested" state drifting from reality). Previously this collapsed to a permanent `validationFailed` on every launch: the assertion-refresh path only recovered from the server-driven `reattestRequired`, never from a local Apple rejection, so affected devices were wedged until the app's keychain state was manually cleared. The SDK now clears the stored keyId + tokens, requests a fresh challenge, and runs full attestation once — the same recovery the `reattestRequired` path already used.
- New `GrantivaError.assertionKeyInvalid` case (informational — handled internally by the recovery path; surfaces only if the follow-up full attestation also fails).

---

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

