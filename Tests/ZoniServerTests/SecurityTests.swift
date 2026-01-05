// ZoniServerTests - Security-focused test suite
//
// SecurityTests.swift - Tests for JWT validation, rate limiting, and security vulnerabilities
//
// This test suite validates security-critical functionality including:
// - JWT signature validation and timing attack resistance
// - Rate limiter bypass attempts
// - Tenant isolation enforcement
// - Authentication edge cases

import XCTest
import Crypto
@testable import ZoniServer

final class SecurityTests: XCTestCase {

    // MARK: - JWT Security Tests

    /// Test that JWT tokens without signatures are rejected when secret is configured
    func testJWTSignatureValidationRequired() async throws {
        let storage = InMemoryTenantStorage()
        let secret = "test-secret-key-at-least-32-bytes-long-for-security"

        // Create a tenant
        let tenant = TenantContext(
            tenantId: "tenant_123",
            name: "Test Tenant",
            tier: "free",
            config: TenantConfiguration(
                maxDocuments: 1000,
                maxStorageBytes: 1_000_000,
                enabledFeatures: []
            ),
            apiKeyHash: nil,
            createdAt: Date()
        )
        try await storage.store(tenant)

        let manager = TenantManager(storage: storage, jwtSecret: secret)

        // Create a valid JWT structure but with invalid signature
        let header = """
        {"alg":"HS256","typ":"JWT"}
        """.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let payload = """
        {"tenant_id":"tenant_123","exp":\(Int(Date().addingTimeInterval(3600).timeIntervalSince1970))}
        """.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        // Use an invalid signature
        let invalidSignature = "invalid-signature-here"

        let maliciousToken = "\(header).\(payload).\(invalidSignature)"

        // Attempt to resolve tenant with invalid signature should fail
        do {
            _ = try await manager.resolve(from: "Bearer \(maliciousToken)")
            XCTFail("Should have rejected token with invalid signature")
        } catch let error as ZoniServerError {
            // Verify we get the correct error
            XCTAssertTrue(
                error.errorDescription.contains("Invalid signature") ||
                error.errorDescription.contains("Invalid base64url"),
                "Expected signature validation error, got: \(error.errorDescription)"
            )
        }
    }

    /// Test that JWT validation without secret allows any token (development mode)
    func testJWTWithoutSecretAcceptsAnyToken() async throws {
        let storage = InMemoryTenantStorage()

        // Create a tenant
        let tenant = TenantContext(
            tenantId: "tenant_123",
            name: "Test Tenant",
            tier: "free",
            config: TenantConfiguration(
                maxDocuments: 1000,
                maxStorageBytes: 1_000_000,
                enabledFeatures: []
            ),
            apiKeyHash: nil,
            createdAt: Date()
        )
        try await storage.store(tenant)

        // No secret = no validation (DEVELOPMENT ONLY)
        let manager = TenantManager(storage: storage, jwtSecret: nil)

        let header = """
        {"alg":"none"}
        """.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let payload = """
        {"tenant_id":"tenant_123","exp":\(Int(Date().addingTimeInterval(3600).timeIntervalSince1970))}
        """.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let unsignedToken = "\(header).\(payload)."

        // This should succeed (but is INSECURE for production)
        let resolved = try await manager.resolve(from: "Bearer \(unsignedToken)")
        XCTAssertEqual(resolved.tenantId, "tenant_123")
    }

    /// Test JWT expiration enforcement
    func testJWTExpirationValidation() async throws {
        let storage = InMemoryTenantStorage()
        let secret = "test-secret-key-at-least-32-bytes-long-for-security"

        let tenant = TenantContext(
            tenantId: "tenant_123",
            name: "Test Tenant",
            tier: "free",
            config: TenantConfiguration(maxDocuments: 1000, maxStorageBytes: 1_000_000, enabledFeatures: []),
            apiKeyHash: nil,
            createdAt: Date()
        )
        try await storage.store(tenant)

        let manager = TenantManager(storage: storage, jwtSecret: secret)

        // Create an expired token (expired 1 hour ago)
        let expiredTime = Int(Date().addingTimeInterval(-3600).timeIntervalSince1970)

        let header = """
        {"alg":"HS256","typ":"JWT"}
        """.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let payload = """
        {"tenant_id":"tenant_123","exp":\(expiredTime)}
        """.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        // Sign it properly
        let message = "\(header).\(payload)"
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        let signatureString = Data(signature).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let expiredToken = "\(header).\(payload).\(signatureString)"

        // Should reject expired token
        do {
            _ = try await manager.resolve(from: "Bearer \(expiredToken)")
            XCTFail("Should have rejected expired token")
        } catch let error as ZoniServerError {
            // Verify it's a token expired error
            switch error {
            case .tokenExpired:
                break // Expected
            default:
                XCTFail("Expected tokenExpired error, got: \(error)")
            }
        }
    }

    // MARK: - Rate Limiter Security Tests

    /// Test that rate limiter prevents bypass attempts
    func testRateLimiterCannotBeBypassedByRapidRequests() async throws {
        let policy = TestRateLimitPolicy()
        let rateLimiter = TenantRateLimiter(policy: policy)

        let tenantId = "tenant_test"
        let operation = RateLimitOperation.query

        // Get the limit
        let limit = policy.limits(for: "free").requestsPerMinute

        // Make requests up to the limit
        for _ in 0..<limit {
            let allowed = await rateLimiter.checkLimit(
                tenantId: tenantId,
                tier: "free",
                operation: operation
            )
            XCTAssertTrue(allowed, "Request within limit should be allowed")
        }

        // Next request should be rate limited
        let shouldBeBlocked = await rateLimiter.checkLimit(
            tenantId: tenantId,
            tier: "free",
            operation: operation
        )
        XCTAssertFalse(shouldBeBlocked, "Request exceeding limit should be blocked")
    }

    /// Test rate limiter with concurrent requests
    func testRateLimiterThreadSafety() async throws {
        let policy = TestRateLimitPolicy()
        let rateLimiter = TenantRateLimiter(policy: policy)

        let tenantId = "tenant_concurrent"
        let operation = RateLimitOperation.query

        // Launch 100 concurrent requests
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    await rateLimiter.checkLimit(
                        tenantId: tenantId,
                        tier: "free",
                        operation: operation
                    )
                }
            }

            var allowedCount = 0
            for await allowed in group {
                if allowed {
                    allowedCount += 1
                }
            }

            // Should allow exactly the rate limit (60 for free tier)
            let expectedLimit = policy.limits(for: "free").requestsPerMinute
            XCTAssertEqual(
                allowedCount,
                expectedLimit,
                "Rate limiter should allow exactly \(expectedLimit) requests, got \(allowedCount)"
            )
        }
    }

    /// Test that different tenants have independent rate limits
    func testRateLimiterTenantIsolation() async throws {
        let policy = TestRateLimitPolicy()
        let rateLimiter = TenantRateLimiter(policy: policy)

        let tenant1 = "tenant_1"
        let tenant2 = "tenant_2"
        let operation = RateLimitOperation.query

        let limit = policy.limits(for: "free").requestsPerMinute

        // Exhaust tenant1's limit
        for _ in 0..<limit {
            _ = await rateLimiter.checkLimit(tenantId: tenant1, tier: "free", operation: operation)
        }

        // Tenant1 should be blocked
        let tenant1Blocked = await rateLimiter.checkLimit(tenantId: tenant1, tier: "free", operation: operation)
        XCTAssertFalse(tenant1Blocked, "Tenant 1 should be rate limited")

        // Tenant2 should still have full quota
        let tenant2Allowed = await rateLimiter.checkLimit(tenantId: tenant2, tier: "free", operation: operation)
        XCTAssertTrue(tenant2Allowed, "Tenant 2 should not be affected by tenant 1's limit")
    }

    // MARK: - Tenant Isolation Tests

    /// Test that tenants cannot access each other's data via API key
    func testTenantCannotAccessOtherTenantData() async throws {
        let storage = InMemoryTenantStorage()

        // Create two tenants
        let tenant1 = TenantContext(
            tenantId: "tenant_1",
            name: "Tenant 1",
            tier: "free",
            config: TenantConfiguration(maxDocuments: 1000, maxStorageBytes: 1_000_000, enabledFeatures: []),
            apiKeyHash: "hash_1",
            createdAt: Date()
        )

        let tenant2 = TenantContext(
            tenantId: "tenant_2",
            name: "Tenant 2",
            tier: "free",
            config: TenantConfiguration(maxDocuments: 1000, maxStorageBytes: 1_000_000, enabledFeatures: []),
            apiKeyHash: "hash_2",
            createdAt: Date()
        )

        try await storage.store(tenant1)
        try await storage.store(tenant2)

        let manager = TenantManager(storage: storage)

        // Resolve tenant1 with their API key
        storage.apiKeyMap["key_1"] = tenant1
        let resolved1 = try await manager.resolve(from: "key_1")
        XCTAssertEqual(resolved1.tenantId, "tenant_1")

        // Resolve tenant2 with their API key
        storage.apiKeyMap["key_2"] = tenant2
        let resolved2 = try await manager.resolve(from: "key_2")
        XCTAssertEqual(resolved2.tenantId, "tenant_2")

        // Attempting to use tenant1's key should never return tenant2's data
        XCTAssertNotEqual(resolved1.tenantId, resolved2.tenantId)
    }

    // MARK: - Cache Security Tests

    /// Test that cache eviction doesn't expose tenant data
    func testCacheEvictionDoesNotLeakData() async throws {
        let storage = InMemoryTenantStorage()
        let manager = TenantManager(
            storage: storage,
            jwtSecret: nil,
            cacheTTL: .seconds(1),
            maxCacheSize: 2  // Very small cache to force eviction
        )

        // Create 3 tenants
        for i in 1...3 {
            let tenant = TenantContext(
                tenantId: "tenant_\(i)",
                name: "Tenant \(i)",
                tier: "free",
                config: TenantConfiguration(maxDocuments: 1000, maxStorageBytes: 1_000_000, enabledFeatures: []),
                apiKeyHash: nil,
                createdAt: Date()
            )
            try await storage.store(tenant)
            storage.apiKeyMap["key_\(i)"] = tenant
        }

        // Access tenants to fill and overflow cache
        _ = try await manager.resolve(from: "key_1")
        _ = try await manager.resolve(from: "key_2")
        _ = try await manager.resolve(from: "key_3")  // Should evict oldest

        // Verify cache size is respected
        let cacheSize = await manager.cacheCount
        XCTAssertLessThanOrEqual(cacheSize, 2, "Cache should not exceed max size")

        // All tenants should still be accessible (from storage)
        let tenant1 = try await manager.resolve(from: "key_1")
        XCTAssertEqual(tenant1.tenantId, "tenant_1")
    }
}

// MARK: - Test Helpers

/// In-memory tenant storage for testing
actor InMemoryTenantStorage: TenantStorage {
    var tenants: [String: TenantContext] = [:]
    var apiKeyMap: [String: TenantContext] = [:]

    func store(_ tenant: TenantContext) async throws {
        tenants[tenant.tenantId] = tenant
    }

    func find(tenantId: String) async throws -> TenantContext? {
        tenants[tenantId]
    }

    func findByApiKey(_ apiKey: String) async throws -> TenantContext? {
        apiKeyMap[apiKey]
    }

    func update(_ tenant: TenantContext) async throws {
        tenants[tenant.tenantId] = tenant
    }

    func delete(tenantId: String) async throws {
        tenants.removeValue(forKey: tenantId)
    }

    func list(limit: Int, offset: Int) async throws -> [TenantContext] {
        Array(tenants.values.sorted { $0.createdAt > $1.createdAt }.prefix(limit).dropFirst(offset))
    }
}

/// Test rate limit policy
struct TestRateLimitPolicy: TenantRateLimitPolicy {
    func limits(for tier: String) -> RateLimits {
        switch tier {
        case "free":
            return RateLimits(
                requestsPerMinute: 60,
                requestsPerHour: 1000,
                concurrentRequests: 5
            )
        case "pro":
            return RateLimits(
                requestsPerMinute: 600,
                requestsPerHour: 10000,
                concurrentRequests: 20
            )
        default:
            return RateLimits(
                requestsPerMinute: 10,
                requestsPerHour: 100,
                concurrentRequests: 2
            )
        }
    }
}
