import XCTest
@testable import Grantiva

final class WhatsNewTests: XCTestCase {

    // MARK: - Fixtures

    private static let noteId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let olderNoteId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    /// Two notes, newest first, exactly as the backend encodes `WhatsNewResponse`
    /// (Vapor's default JSON config: camelCase keys, ISO8601 dates).
    private static let populatedResponse = """
    {
      "releaseNotes": [
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "version": "2.10.0",
          "title": "Faster sync",
          "body": "- Sync is **2x** faster\\n- Fixed a crash",
          "publishedAt": "2026-08-27T12:00:00Z"
        },
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "version": "2.9.0",
          "title": "Dark mode",
          "body": "Dark mode is here."
        }
      ]
    }
    """

    private static let emptyResponse = #"{"releaseNotes":[]}"#

    private static let seenResponse = #"{"status":"ok","seenAt":"2026-08-27T12:30:00Z"}"#

    /// A service wired to the recording stub. `retryAttempts` defaults to 1 so
    /// error-path tests don't spend real time in `RetryManager`'s backoff.
    private func makeService(retryAttempts: Int = 1, token: String? = "jwt-token") -> WhatsNewService {
        let config = GrantivaConfiguration(
            baseURL: "https://api.grantiva.io",
            retryAttempts: retryAttempts,
            retryBaseDelay: 0.01,
            apiKey: "test-api-key"
        )
        let client = WhatsNewAPIClient(
            configuration: config,
            teamId: "TEAM123",
            getToken: { token },
            session: StubURLProtocol.makeSession()
        )
        return WhatsNewService(apiClient: client)
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Decoding

    func testGetReleaseNotesDecodesPopulatedResponse() async throws {
        StubURLProtocol.enqueue(.json(Self.populatedResponse))

        let notes = try await makeService().getReleaseNotes()

        XCTAssertEqual(notes.count, 2)

        let newest = notes[0]
        XCTAssertEqual(newest.id, Self.noteId)
        XCTAssertEqual(newest.version, "2.10.0")
        XCTAssertEqual(newest.title, "Faster sync")
        XCTAssertEqual(newest.body, "- Sync is **2x** faster\n- Fixed a crash")
        XCTAssertEqual(
            newest.publishedAt,
            ISO8601DateFormatter().date(from: "2026-08-27T12:00:00Z"),
            "publishedAt must decode with the backend's ISO8601 strategy"
        )

        // Server order is preserved — newest version first, not re-sorted client-side.
        XCTAssertEqual(notes[1].id, Self.olderNoteId)
        XCTAssertEqual(notes[1].version, "2.9.0")
        XCTAssertNil(notes[1].publishedAt, "a missing publishedAt must decode as nil, not fail")
    }

    /// The Simulator / unattested case: the backend has no device profile, so it
    /// returns an empty list rather than an error. It must surface as an empty
    /// array, not a throw.
    func testGetReleaseNotesEmptyListIsNotAnError() async throws {
        StubURLProtocol.enqueue(.json(Self.emptyResponse))

        let notes = try await makeService().getReleaseNotes()

        XCTAssertTrue(notes.isEmpty)
    }

    func testGetReleaseNotesIssuesGETWithTenantHeaders() async throws {
        StubURLProtocol.enqueue(.json(Self.emptyResponse))

        _ = try await makeService().getReleaseNotes()

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url?.path, "/api/v1/whats-new")
        XCTAssertNil(request.url?.query, "the client must not send an app version — the server reads it from the attested profile")
        XCTAssertEqual(request.header("X-Team-ID"), "TEAM123")
        XCTAssertNotNil(request.header("X-Bundle-ID"))
        XCTAssertEqual(request.header("Authorization"), "Bearer jwt-token")
    }

    func testFallsBackToAPIKeyWhenNoTokenIsAvailable() async throws {
        StubURLProtocol.enqueue(.json(Self.emptyResponse))

        _ = try await makeService(token: nil).getReleaseNotes()

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.header("Authorization"), "Bearer test-api-key")
    }

    func testMalformedResponseThrowsRatherThanReturningEmpty() async {
        StubURLProtocol.enqueue(.json(#"{"notes":[]}"#))

        do {
            _ = try await makeService().getReleaseNotes()
            XCTFail("Expected a decoding error")
        } catch {
            XCTAssertFalse(error is GrantivaError, "a decode failure should surface, not be masked as an empty list")
        }
    }

    // MARK: - Mark Seen

    func testMarkSeenIssuesPOSTToSeenPath() async throws {
        StubURLProtocol.enqueue(.json(Self.seenResponse))

        try await makeService().markSeen(Self.noteId)

        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/whats-new/\(Self.noteId.uuidString)/seen")
        XCTAssertEqual(request.header("X-Team-ID"), "TEAM123")
        XCTAssertTrue(request.body.isEmpty, "the note ID is in the path — there is no request body")
    }

    /// The endpoint is idempotent server-side (unique index on
    /// `(release_note_id, device_profile_id)`), so a second call is a no-op that
    /// still returns 200. The client must not treat it as an error.
    func testMarkSeenIsSafeToCallTwice() async throws {
        StubURLProtocol.enqueue(.json(Self.seenResponse))
        StubURLProtocol.enqueue(.json(Self.seenResponse))
        let service = makeService()

        try await service.markSeen(Self.noteId)
        try await service.markSeen(Self.noteId)

        XCTAssertEqual(StubURLProtocol.requestCount, 2)
        for request in StubURLProtocol.requests {
            XCTAssertEqual(request.method, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/whats-new/\(Self.noteId.uuidString)/seen")
        }
    }

    func testMarkSeenDropsTheNoteFromTheCache() async throws {
        StubURLProtocol.enqueue(.json(Self.populatedResponse))
        StubURLProtocol.enqueue(.json(Self.seenResponse))
        let service = makeService()

        let initial = try await service.getReleaseNotes()
        XCTAssertEqual(initial.count, 2)
        try await service.markSeen(Self.noteId)

        // Served from cache (no third stub is consumed), minus the seen note.
        let remaining = try await service.getReleaseNotes()
        XCTAssertEqual(remaining.map(\.id), [Self.olderNoteId])
        XCTAssertEqual(StubURLProtocol.requestCount, 2)
    }

    func testMarkSeenPropagatesErrors() async {
        StubURLProtocol.enqueue(.status(404))
        let service = makeService()

        do {
            try await service.markSeen(Self.noteId)
            XCTFail("Expected a 404 to throw")
        } catch let error as GrantivaError {
            guard case .networkError = error else {
                return XCTFail("Expected .networkError, got \(error)")
            }
        } catch {
            XCTFail("Expected a GrantivaError, got \(error)")
        }
    }

    // MARK: - Error Mapping

    func testUnauthorizedMapsToValidationFailed() async {
        StubURLProtocol.enqueue(.status(401))

        await assertGetThrows(.validationFailed)
    }

    func testTooManyRequestsMapsToRateLimited() async {
        StubURLProtocol.enqueue(.status(429))

        await assertGetThrows(.rateLimited)
    }

    func testBadRequestMapsToNetworkErrorCarryingTheStatusCode() async {
        StubURLProtocol.enqueue(.json(#"{"error":true,"reason":"X-Bundle-ID and X-Team-ID headers are required"}"#, status: 400))

        do {
            _ = try await makeService().getReleaseNotes()
            XCTFail("Expected a 400 to throw")
        } catch let GrantivaError.networkError(underlying) {
            XCTAssertEqual((underlying as NSError).code, 400)
        } catch {
            XCTFail("Expected .networkError, got \(error)")
        }
    }

    func testServerErrorMapsToNetworkErrorCarryingTheStatusCode() async {
        StubURLProtocol.enqueue(.status(500))

        do {
            _ = try await makeService().getReleaseNotes()
            XCTFail("Expected a 500 to throw")
        } catch let GrantivaError.networkError(underlying) {
            XCTAssertEqual((underlying as NSError).code, 500)
        } catch {
            XCTFail("Expected .networkError, got \(error)")
        }
    }

    func testTransportFailureMapsToNetworkError() async {
        StubURLProtocol.setFallback(.failure(URLError(.notConnectedToInternet)))

        do {
            _ = try await makeService().getReleaseNotes()
            XCTFail("Expected a transport failure to throw")
        } catch let GrantivaError.networkError(underlying) {
            XCTAssertEqual((underlying as? URLError)?.code, .notConnectedToInternet)
        } catch {
            XCTFail("Expected .networkError, got \(error)")
        }
    }

    /// `GET /whats-new` is side-effect free, so a transient transport failure is
    /// retried rather than surfaced on the first attempt.
    func testGetReleaseNotesRetriesTransientTransportFailures() async throws {
        StubURLProtocol.enqueue(.failure(URLError(.networkConnectionLost)))
        StubURLProtocol.enqueue(.json(Self.populatedResponse))

        let notes = try await makeService(retryAttempts: 2).getReleaseNotes()

        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(StubURLProtocol.requestCount, 2)
    }

    // MARK: - Cache

    func testSecondFetchIsServedFromCache() async throws {
        StubURLProtocol.enqueue(.json(Self.populatedResponse))
        let service = makeService()

        _ = try await service.getReleaseNotes()
        let cached = try await service.getReleaseNotes()

        XCTAssertEqual(cached.count, 2)
        XCTAssertEqual(StubURLProtocol.requestCount, 1, "the second call must not hit the network")
    }

    func testForceRefreshBypassesTheCache() async throws {
        StubURLProtocol.enqueue(.json(Self.populatedResponse))
        StubURLProtocol.enqueue(.json(Self.emptyResponse))
        let service = makeService()

        let first = try await service.getReleaseNotes()
        XCTAssertEqual(first.count, 2)
        let refreshed = try await service.getReleaseNotes(forceRefresh: true)
        XCTAssertTrue(refreshed.isEmpty)
        XCTAssertEqual(StubURLProtocol.requestCount, 2)

        // The refreshed (empty) result replaces the cache.
        let cached = try await service.getReleaseNotes()
        XCTAssertTrue(cached.isEmpty)
        XCTAssertEqual(StubURLProtocol.requestCount, 2)
    }

    func testExpiredCacheRefetches() async throws {
        StubURLProtocol.enqueue(.json(Self.populatedResponse))
        StubURLProtocol.enqueue(.json(Self.emptyResponse))
        let service = makeService()
        await service.setCacheTTL(0)

        let first = try await service.getReleaseNotes()
        XCTAssertEqual(first.count, 2)
        let second = try await service.getReleaseNotes()
        XCTAssertTrue(second.isEmpty, "a zero TTL must expire immediately")
        XCTAssertEqual(StubURLProtocol.requestCount, 2)
    }

    func testClearCacheForcesARefetch() async throws {
        StubURLProtocol.enqueue(.json(Self.populatedResponse))
        StubURLProtocol.enqueue(.json(Self.emptyResponse))
        let service = makeService()

        let first = try await service.getReleaseNotes()
        XCTAssertEqual(first.count, 2)
        await service.clearCache()
        let second = try await service.getReleaseNotes()
        XCTAssertTrue(second.isEmpty)
        XCTAssertEqual(StubURLProtocol.requestCount, 2)
    }

    func testFailedRefreshLeavesTheCacheIntact() async throws {
        StubURLProtocol.enqueue(.json(Self.populatedResponse))
        StubURLProtocol.enqueue(.status(500))
        let service = makeService()

        let first = try await service.getReleaseNotes()
        XCTAssertEqual(first.count, 2)
        do {
            _ = try await service.getReleaseNotes(forceRefresh: true)
            XCTFail("Expected the forced refresh to throw")
        } catch {
            // expected
        }

        let afterFailure = try await service.getReleaseNotes()
        XCTAssertEqual(afterFailure.count, 2, "a failed refresh must not clear good cached data")
    }

    // MARK: - Model

    func testReleaseNoteRoundTrips() throws {
        let note = ReleaseNote(
            id: Self.noteId,
            version: "2.10.0",
            title: "Faster sync",
            body: "# Notes",
            publishedAt: Date(timeIntervalSince1970: 1_772_000_000)
        )

        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(ReleaseNote.self, from: data)

        XCTAssertEqual(decoded.id, note.id)
        XCTAssertEqual(decoded.version, note.version)
        XCTAssertEqual(decoded.title, note.title)
        XCTAssertEqual(decoded.body, note.body)
        XCTAssertEqual(decoded.publishedAt, note.publishedAt)
    }

    // MARK: - Helpers

    private func assertGetThrows(
        _ expected: GrantivaError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await makeService().getReleaseNotes()
            XCTFail("Expected \(expected) to be thrown", file: file, line: line)
        } catch let error as GrantivaError {
            XCTAssertEqual("\(error)", "\(expected)", file: file, line: line)
        } catch {
            XCTFail("Expected a GrantivaError, got \(error)", file: file, line: line)
        }
    }
}
