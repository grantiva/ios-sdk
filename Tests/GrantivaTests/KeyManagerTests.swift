import XCTest
import DeviceCheck
@testable import Grantiva

/// Tests for `KeyManager` — Keychain persistence of the App Attest key id and
/// the "has been attested" flag.
///
/// Only the Keychain-backed state is exercised. `DCAppAttestService.generateKey()`
/// requires a provisioned physical device with the App Attest entitlement, so the
/// key-generation branch is explicitly skipped rather than faked (see
/// `testGenerateKeyPathRequiresRealDevice`).
final class KeyManagerTests: XCTestCase {

    private var keyManager: KeyManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        keyManager = KeyManager()
        keyManager.clearStoredKeyId()

        // The Keychain is environment-sensitive (unsigned binaries, locked keychains,
        // CI without a login keychain). If it isn't writable here, skip loudly rather
        // than reporting a false pass.
        do {
            try keyManager.saveKeyId("keychain-probe")
        } catch {
            throw XCTSkip("Keychain is not writable in this environment: \(error)")
        }
        guard keyManager.getStoredKeyId() == "keychain-probe" else {
            throw XCTSkip("Keychain writes are not readable back in this environment")
        }
        keyManager.clearStoredKeyId()
    }

    override func tearDown() {
        keyManager.clearStoredKeyId()
        keyManager = nil
        super.tearDown()
    }

    // MARK: - Key id round trip

    func testSaveAndRetrieveKeyId() throws {
        try keyManager.saveKeyId("KEY-ABC-123")
        XCTAssertEqual(keyManager.getStoredKeyId(), "KEY-ABC-123")
    }

    func testNoStoredKeyIdReturnsNil() {
        keyManager.clearStoredKeyId()
        XCTAssertNil(keyManager.getStoredKeyId())
    }

    func testSaveKeyIdOverwritesPreviousValue() throws {
        try keyManager.saveKeyId("KEY-FIRST")
        try keyManager.saveKeyId("KEY-SECOND")
        // The save path deletes before adding; a duplicate would otherwise make
        // `SecItemAdd` fail and silently strand the old key id.
        XCTAssertEqual(keyManager.getStoredKeyId(), "KEY-SECOND")
    }

    func testKeyIdSurvivesANewKeyManagerInstance() throws {
        try keyManager.saveKeyId("KEY-PERSISTED")
        // Persistence is the whole point: a fresh SDK launch must find the same key.
        XCTAssertEqual(KeyManager().getStoredKeyId(), "KEY-PERSISTED")
    }

    func testKeyIdRoundTripsNonASCIIAndLongValues() throws {
        let value = String(repeating: "K", count: 512) + "-é✓"
        try keyManager.saveKeyId(value)
        XCTAssertEqual(keyManager.getStoredKeyId(), value)
    }

    func testClearStoredKeyIdIsIdempotent() throws {
        try keyManager.saveKeyId("KEY-X")
        keyManager.clearStoredKeyId()
        keyManager.clearStoredKeyId() // must not trap on errSecItemNotFound
        XCTAssertNil(keyManager.getStoredKeyId())
    }

    // MARK: - Attested flag

    func testAttestedFlagDefaultsToFalse() {
        keyManager.clearStoredKeyId()
        XCTAssertFalse(keyManager.hasBeenAttested())
    }

    func testMarkAsAttestedSetsTheFlag() {
        keyManager.markAsAttested()
        XCTAssertTrue(keyManager.hasBeenAttested())
    }

    func testMarkAsAttestedIsIdempotent() {
        keyManager.markAsAttested()
        keyManager.markAsAttested()
        XCTAssertTrue(keyManager.hasBeenAttested())
    }

    /// The self-heal path: drop the attested flag so the next call re-attests, but
    /// keep the key id — App Attest will not issue a second key for the same app.
    func testClearAttestedFlagKeepsTheKeyId() throws {
        try keyManager.saveKeyId("KEY-KEEPME")
        keyManager.markAsAttested()

        keyManager.clearAttestedFlag()

        XCTAssertFalse(keyManager.hasBeenAttested())
        XCTAssertEqual(keyManager.getStoredKeyId(), "KEY-KEEPME", "clearing the attested flag must not discard the key id")
    }

    func testClearStoredKeyIdAlsoClearsAttestedFlag() throws {
        try keyManager.saveKeyId("KEY-BOTH")
        keyManager.markAsAttested()

        keyManager.clearStoredKeyId()

        XCTAssertNil(keyManager.getStoredKeyId())
        XCTAssertFalse(keyManager.hasBeenAttested(), "a fresh key must go through full attestation")
    }

    func testAttestedFlagIsSharedAcrossInstances() {
        keyManager.markAsAttested()
        XCTAssertTrue(KeyManager().hasBeenAttested())
    }

    // MARK: - getOrCreateKeyId

    func testGetOrCreateReturnsTheStoredKeyIdWithoutGeneratingANewOne() async throws {
        try keyManager.saveKeyId("KEY-EXISTING")

        let keyId = try await keyManager.getOrCreateKeyId()

        XCTAssertEqual(keyId, "KEY-EXISTING")
        XCTAssertEqual(keyManager.getStoredKeyId(), "KEY-EXISTING", "the stored key id must be untouched")
    }

    /// With no stored key id and no App Attest support (simulator, Mac test host,
    /// unentitled binary) the manager must fail closed with `.attestationNotAvailable`
    /// rather than returning a bogus key id.
    func testGetOrCreateThrowsWhenAppAttestIsUnsupported() async throws {
        try XCTSkipIf(
            DCAppAttestService.shared.isSupported,
            "App Attest is supported here — this test covers only the unsupported branch"
        )
        keyManager.clearStoredKeyId()

        do {
            _ = try await keyManager.getOrCreateKeyId()
            XCTFail("Expected .attestationNotAvailable")
        } catch {
            guard case GrantivaError.attestationNotAvailable = error else {
                return XCTFail("Expected .attestationNotAvailable, got \(error)")
            }
        }
    }

    /// Explicitly skipped, not faked: `DCAppAttestService.generateKey()` needs a real
    /// device with the App Attest entitlement and Apple network reachability. There is
    /// no supported way to stub it, so key generation is covered by device QA only.
    func testGenerateKeyPathRequiresRealDevice() throws {
        throw XCTSkip("DCAppAttestService.generateKey() requires a provisioned physical device with the App Attest entitlement; not reproducible in a unit test")
    }
}
