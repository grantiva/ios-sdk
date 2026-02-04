import XCTest
@testable import Grantiva

final class FeedbackTests: XCTestCase {

    // MARK: - Model Tests

    func testFeatureRequestStatusRawValues() {
        XCTAssertEqual(FeatureRequestStatus.pending.rawValue, "pending")
        XCTAssertEqual(FeatureRequestStatus.open.rawValue, "open")
        XCTAssertEqual(FeatureRequestStatus.planned.rawValue, "planned")
        XCTAssertEqual(FeatureRequestStatus.inProgress.rawValue, "in_progress")
        XCTAssertEqual(FeatureRequestStatus.shipped.rawValue, "shipped")
        XCTAssertEqual(FeatureRequestStatus.declined.rawValue, "declined")
        XCTAssertEqual(FeatureRequestStatus.duplicate.rawValue, "duplicate")
    }

    func testFeatureRequestStatusDecodable() {
        for status in FeatureRequestStatus.allCases {
            let json = "\"\(status.rawValue)\""
            let data = json.data(using: .utf8)!
            let decoded = try? JSONDecoder().decode(FeatureRequestStatus.self, from: data)
            XCTAssertEqual(decoded, status, "Failed to decode status: \(status.rawValue)")
        }
    }

    func testTicketStatusRawValues() {
        XCTAssertEqual(TicketStatus.open.rawValue, "open")
        XCTAssertEqual(TicketStatus.awaitingReply.rawValue, "awaiting_reply")
        XCTAssertEqual(TicketStatus.resolved.rawValue, "resolved")
        XCTAssertEqual(TicketStatus.closed.rawValue, "closed")
    }

    func testTicketPriorityRawValues() {
        XCTAssertEqual(TicketPriority.low.rawValue, "low")
        XCTAssertEqual(TicketPriority.normal.rawValue, "normal")
        XCTAssertEqual(TicketPriority.high.rawValue, "high")
        XCTAssertEqual(TicketPriority.urgent.rawValue, "urgent")
    }

    func testCommentAuthorTypeRawValues() {
        XCTAssertEqual(CommentAuthorType.user.rawValue, "user")
        XCTAssertEqual(CommentAuthorType.admin.rawValue, "admin")
    }

    func testFeatureRequestCodable() throws {
        let now = Date()
        let request = FeatureRequest(
            id: UUID(),
            title: "Dark Mode",
            description: "Please add dark mode support",
            status: .open,
            voteCount: 42,
            hasVoted: true,
            commentCount: 5,
            createdAt: now,
            updatedAt: now
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(FeatureRequest.self, from: data)

        XCTAssertEqual(decoded.id, request.id)
        XCTAssertEqual(decoded.title, "Dark Mode")
        XCTAssertEqual(decoded.description, "Please add dark mode support")
        XCTAssertEqual(decoded.status, .open)
        XCTAssertEqual(decoded.voteCount, 42)
        XCTAssertTrue(decoded.hasVoted)
        XCTAssertEqual(decoded.commentCount, 5)
    }

    func testSupportTicketCodable() throws {
        let now = Date()
        let ticket = SupportTicket(
            id: UUID(),
            subject: "Login Issue",
            status: .open,
            priority: .high,
            messageCount: 3,
            createdAt: now,
            updatedAt: now
        )

        let data = try JSONEncoder().encode(ticket)
        let decoded = try JSONDecoder().decode(SupportTicket.self, from: data)

        XCTAssertEqual(decoded.id, ticket.id)
        XCTAssertEqual(decoded.subject, "Login Issue")
        XCTAssertEqual(decoded.status, .open)
        XCTAssertEqual(decoded.priority, .high)
        XCTAssertEqual(decoded.messageCount, 3)
    }

    func testVoteCodable() throws {
        let featureId = UUID()
        let vote = Vote(id: UUID(), featureRequestId: featureId, createdAt: Date())
        let data = try JSONEncoder().encode(vote)
        let decoded = try JSONDecoder().decode(Vote.self, from: data)
        XCTAssertEqual(decoded.featureRequestId, featureId)
    }

    func testFeatureCommentCodable() throws {
        let featureId = UUID()
        let comment = FeatureComment(
            id: UUID(),
            featureRequestId: featureId,
            authorType: .admin,
            body: "This is planned for Q2",
            createdAt: Date()
        )
        let data = try JSONEncoder().encode(comment)
        let decoded = try JSONDecoder().decode(FeatureComment.self, from: data)
        XCTAssertEqual(decoded.authorType, .admin)
        XCTAssertEqual(decoded.body, "This is planned for Q2")
    }

    func testTicketMessageCodable() throws {
        let ticketId = UUID()
        let message = TicketMessage(
            id: UUID(),
            ticketId: ticketId,
            authorType: .user,
            body: "I need help with this",
            createdAt: Date()
        )
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(TicketMessage.self, from: data)
        XCTAssertEqual(decoded.ticketId, ticketId)
        XCTAssertEqual(decoded.authorType, .user)
    }

    // MARK: - Device Hasher Tests

    func testDeviceHasherProducesConsistentHash() {
        let hash1 = DeviceHasher.generateDeviceHash()
        let hash2 = DeviceHasher.generateDeviceHash()
        XCTAssertEqual(hash1, hash2, "Device hash should be stable across calls")
        XCTAssertFalse(hash1.isEmpty)
    }

    func testDeviceHasherVoterIdDiffersFromSubmitterId() {
        let voterId = DeviceHasher.generateVoterId()
        let submitterId = DeviceHasher.generateSubmitterId()
        XCTAssertNotEqual(voterId, submitterId, "Voter ID and submitter ID should be different")
    }

    func testDeviceHasherVoterIdIsConsistent() {
        let id1 = DeviceHasher.generateVoterId()
        let id2 = DeviceHasher.generateVoterId()
        XCTAssertEqual(id1, id2)
    }

    func testDeviceHasherSubmitterIdIsConsistent() {
        let id1 = DeviceHasher.generateSubmitterId()
        let id2 = DeviceHasher.generateSubmitterId()
        XCTAssertEqual(id1, id2)
    }

    func testDeviceHashIsSHA256Length() {
        let hash = DeviceHasher.generateDeviceHash()
        // SHA-256 produces 64 hex characters
        XCTAssertEqual(hash.count, 64, "SHA-256 hash should be 64 hex characters")
    }

    // MARK: - Cache Tests

    func testFeedbackCacheStoresAndRetrievesFeatureRequests() {
        let cache = FeedbackCache()
        let now = Date()
        let requests = [
            FeatureRequest(id: UUID(), title: "Feature 1", description: "Desc", status: .open, voteCount: 10, hasVoted: false, commentCount: 0, createdAt: now, updatedAt: now),
            FeatureRequest(id: UUID(), title: "Feature 2", description: "Desc", status: .planned, voteCount: 5, hasVoted: true, commentCount: 2, createdAt: now, updatedAt: now)
        ]

        XCTAssertNil(cache.getCachedFeatureRequests())
        cache.cacheFeatureRequests(requests)

        // Allow barrier write to complete
        let expectation = expectation(description: "cache write")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let cached = cache.getCachedFeatureRequests()
            XCTAssertNotNil(cached)
            XCTAssertEqual(cached?.count, 2)
            XCTAssertEqual(cached?.first?.title, "Feature 1")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testFeedbackCacheInvalidation() {
        let cache = FeedbackCache()
        let now = Date()
        let requests = [
            FeatureRequest(id: UUID(), title: "Feature", description: "Desc", status: .open, voteCount: 0, hasVoted: false, commentCount: 0, createdAt: now, updatedAt: now)
        ]

        cache.cacheFeatureRequests(requests)

        let expectation = expectation(description: "cache invalidate")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            cache.invalidateFeatureRequests()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                XCTAssertNil(cache.getCachedFeatureRequests())
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func testFeedbackCacheClearAll() {
        let cache = FeedbackCache()
        let now = Date()
        let requests = [
            FeatureRequest(id: UUID(), title: "Feature", description: "Desc", status: .open, voteCount: 0, hasVoted: false, commentCount: 0, createdAt: now, updatedAt: now)
        ]
        let tickets = [
            SupportTicket(id: UUID(), subject: "Help", status: .open, priority: .normal, messageCount: 0, createdAt: now, updatedAt: now)
        ]

        cache.cacheFeatureRequests(requests)
        cache.cacheTickets(tickets)

        let expectation = expectation(description: "cache clear")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            cache.clearAll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                XCTAssertNil(cache.getCachedFeatureRequests())
                XCTAssertNil(cache.getCachedTickets())
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Network Model Conversion Tests

    func testFeatureRequestResponseConversion() {
        let formatter = ISO8601DateFormatter()
        let now = formatter.string(from: Date())
        let response = FeatureRequestResponse(
            id: UUID(),
            title: "Test Feature",
            description: "Test Description",
            status: "open",
            voteCount: 10,
            hasVoted: false,
            commentCount: 3,
            createdAt: now,
            updatedAt: now
        )

        let model = response.toModel(dateFormatter: formatter)
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.title, "Test Feature")
        XCTAssertEqual(model?.status, .open)
        XCTAssertEqual(model?.voteCount, 10)
    }

    func testFeatureRequestResponseInvalidStatusReturnsNil() {
        let formatter = ISO8601DateFormatter()
        let now = formatter.string(from: Date())
        let response = FeatureRequestResponse(
            id: UUID(),
            title: "Test",
            description: "Desc",
            status: "invalid_status",
            voteCount: 0,
            hasVoted: false,
            commentCount: 0,
            createdAt: now,
            updatedAt: now
        )

        XCTAssertNil(response.toModel(dateFormatter: formatter))
    }

    func testSupportTicketResponseConversion() {
        let formatter = ISO8601DateFormatter()
        let now = formatter.string(from: Date())
        let response = SupportTicketResponse(
            id: UUID(),
            subject: "Help",
            status: "awaiting_reply",
            priority: "high",
            messageCount: 2,
            createdAt: now,
            updatedAt: now
        )

        let model = response.toModel(dateFormatter: formatter)
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.subject, "Help")
        XCTAssertEqual(model?.status, .awaitingReply)
        XCTAssertEqual(model?.priority, .high)
    }

    func testCommentResponseConversion() {
        let formatter = ISO8601DateFormatter()
        let now = formatter.string(from: Date())
        let response = CommentResponse(
            id: UUID(),
            featureRequestId: UUID(),
            authorType: "admin",
            body: "Great idea!",
            createdAt: now
        )

        let model = response.toModel(dateFormatter: formatter)
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.authorType, .admin)
        XCTAssertEqual(model?.body, "Great idea!")
    }

    func testTicketMessageResponseConversion() {
        let formatter = ISO8601DateFormatter()
        let now = formatter.string(from: Date())
        let response = TicketMessageResponse(
            id: UUID(),
            ticketId: UUID(),
            authorType: "user",
            body: "Thanks for the help",
            createdAt: now
        )

        let model = response.toModel(dateFormatter: formatter)
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.authorType, .user)
    }

    // MARK: - Error Tests

    func testRateLimitedError() {
        let error = GrantivaError.rateLimited
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotNil(error.failureReason)
        XCTAssertTrue(error.errorDescription!.contains("Too many"))
    }

    func testFeedbackNotAvailableError() {
        let error = GrantivaError.feedbackNotAvailable
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotNil(error.failureReason)
    }

    // MARK: - UserContext Tests

    func testUserContextAutoCollectsDeviceInfo() {
        let context = UserContext(userId: "user_123")
        XCTAssertEqual(context.userId, "user_123")
        XCTAssertFalse(context.device.osName.isEmpty)
        XCTAssertFalse(context.device.osVersion.isEmpty)
        XCTAssertFalse(context.device.sdkVersion.isEmpty)
        XCTAssertFalse(context.device.locale.isEmpty)
        XCTAssertFalse(context.device.timezone.isEmpty)
    }

    func testUserContextWithProperties() {
        let context = UserContext(userId: "user_123", properties: [
            "plan": "premium",
            "state": "TX"
        ])
        XCTAssertEqual(context.properties["plan"], "premium")
        XCTAssertEqual(context.properties["state"], "TX")
    }

    func testUserContextAllPropertiesMergesDeviceAndCustom() {
        let context = UserContext(userId: "user_123", properties: [
            "plan": "premium"
        ])
        let all = context.allProperties
        // Should contain user_id
        XCTAssertEqual(all["user_id"], "user_123")
        // Should contain custom property
        XCTAssertEqual(all["plan"], "premium")
        // Should contain auto-collected device info
        XCTAssertNotNil(all["os_name"])
        XCTAssertNotNil(all["os_version"])
        XCTAssertNotNil(all["sdk_version"])
        XCTAssertNotNil(all["device_model"])
        XCTAssertNotNil(all["locale"])
        XCTAssertNotNil(all["timezone"])
    }

    func testUserContextCustomPropertiesOverrideDeviceValues() {
        let context = UserContext(userId: "user_123", properties: [
            "os_name": "CustomOS"
        ])
        let all = context.allProperties
        XCTAssertEqual(all["os_name"], "CustomOS", "Developer properties should override auto-collected values")
    }

    func testDeviceContextToDictionary() {
        let device = DeviceContext.current()
        let dict = device.toDictionary()
        XCTAssertEqual(dict.count, 10, "DeviceContext should produce 10 key-value pairs")
        XCTAssertNotNil(dict["app_bundle_id"])
        XCTAssertNotNil(dict["app_version"])
        XCTAssertNotNil(dict["app_build_number"])
        XCTAssertNotNil(dict["device_model"])
        XCTAssertNotNil(dict["os_name"])
        XCTAssertNotNil(dict["os_version"])
        XCTAssertNotNil(dict["locale"])
        XCTAssertNotNil(dict["timezone"])
        XCTAssertNotNil(dict["sdk_version"])
        XCTAssertNotNil(dict["environment"])
    }

    // MARK: - Identity Provider Tests

    func testIdentityProviderDefaultsToDeviceBased() {
        let provider = IdentityProvider()
        XCTAssertNil(provider.userId)
        XCTAssertFalse(provider.isIdentified)
        XCTAssertFalse(provider.effectiveSubmitterId.isEmpty)
        XCTAssertFalse(provider.effectiveVoterId.isEmpty)
    }

    func testIdentityProviderIdentifyWithContext() {
        let provider = IdentityProvider()
        let context = UserContext(userId: "user_123", properties: ["plan": "pro"])
        provider.identify(context)
        XCTAssertEqual(provider.userId, "user_123")
        XCTAssertTrue(provider.isIdentified)
        XCTAssertEqual(provider.effectiveSubmitterId, "user_123")
        XCTAssertEqual(provider.effectiveVoterId, "user_123")
        XCTAssertEqual(provider.userContext?.properties["plan"], "pro")
    }

    func testIdentityProviderAllPropertiesWhenIdentified() {
        let provider = IdentityProvider()
        let context = UserContext(userId: "user_123", properties: ["role": "admin"])
        provider.identify(context)
        let props = provider.allProperties
        XCTAssertEqual(props["user_id"], "user_123")
        XCTAssertEqual(props["role"], "admin")
        XCTAssertNotNil(props["os_name"])
    }

    func testIdentityProviderAllPropertiesWhenNotIdentified() {
        let provider = IdentityProvider()
        let props = provider.allProperties
        XCTAssertNil(props["user_id"])
        XCTAssertNotNil(props["os_name"], "Should still have device context when not identified")
    }

    func testIdentityProviderClearIdentity() {
        let provider = IdentityProvider()
        provider.identify(UserContext(userId: "user_123"))
        provider.clearIdentity()
        XCTAssertNil(provider.userId)
        XCTAssertNil(provider.userContext)
        XCTAssertFalse(provider.isIdentified)
        XCTAssertNotEqual(provider.effectiveSubmitterId, "user_123")
    }

    func testIdentityProviderDeviceHashAlwaysDeviceBased() {
        let provider = IdentityProvider()
        let hashBefore = provider.deviceHash
        provider.identify(UserContext(userId: "user_123"))
        let hashAfter = provider.deviceHash
        XCTAssertEqual(hashBefore, hashAfter, "deviceHash should not change when user is identified")
    }

    func testIdentityProviderSubmitterAndVoterDifferWhenDeviceBased() {
        let provider = IdentityProvider()
        XCTAssertNotEqual(provider.effectiveSubmitterId, provider.effectiveVoterId,
                         "Device-based submitter and voter IDs should differ")
    }

    func testIdentityProviderSubmitterAndVoterSameWhenIdentified() {
        let provider = IdentityProvider()
        provider.identify(UserContext(userId: "user_456"))
        XCTAssertEqual(provider.effectiveSubmitterId, "user_456")
        XCTAssertEqual(provider.effectiveVoterId, "user_456")
    }

    // MARK: - Grantiva Integration

    func testGrantivaExposesFeedbackProperty() {
        let grantiva = Grantiva(teamId: "TEAM123")
        let feedback = grantiva.feedback
        XCTAssertNotNil(feedback, "Grantiva should expose a feedback property")
    }

    func testGrantivaFeedbackPropertyIsStable() {
        let grantiva = Grantiva(teamId: "TEAM123")
        let feedback1 = grantiva.feedback
        let feedback2 = grantiva.feedback
        XCTAssertTrue(feedback1 === feedback2, "feedback property should return the same instance")
    }

    func testGrantivaIdentifyWithString() {
        let grantiva = Grantiva(teamId: "TEAM123")
        XCTAssertNil(grantiva.currentUserId)
        grantiva.identify("user_789")
        XCTAssertEqual(grantiva.currentUserId, "user_789")
    }

    func testGrantivaIdentifyWithContext() {
        let grantiva = Grantiva(teamId: "TEAM123")
        grantiva.identify(UserContext(userId: "user_789", properties: ["plan": "enterprise"]))
        XCTAssertEqual(grantiva.currentUserId, "user_789")
        XCTAssertEqual(grantiva.currentUserContext?.properties["plan"], "enterprise")
    }

    func testGrantivaClearIdentity() {
        let grantiva = Grantiva(teamId: "TEAM123")
        grantiva.identify("user_789")
        grantiva.clearIdentity()
        XCTAssertNil(grantiva.currentUserId)
        XCTAssertNil(grantiva.currentUserContext)
    }
}
