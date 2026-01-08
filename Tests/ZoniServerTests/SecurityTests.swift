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
            organizationId: nil,
            tier: .free,
            config: TenantConfiguration(
                queriesPerMinute: 60,
                documentsPerDay: 1000,
                maxConcurrentWebSockets: 5,
                maxDocumentSize: 1_000_000
            ),
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
            let errorDesc = error.errorDescription ?? ""
            XCTAssertTrue(
                errorDesc.contains("Invalid signature") ||
                errorDesc.contains("Invalid base64url"),
                "Expected signature validation error, got: \(errorDesc)"
            )
        }
    }

    /// Test that JWT validation without secret allows any token (development mode)
    func testJWTWithoutSecretAcceptsAnyToken() async throws {
        let storage = InMemoryTenantStorage()

        // Create a tenant
        let tenant = TenantContext(
            tenantId: "tenant_123",
            organizationId: nil,
            tier: .free,
            config: TenantConfiguration(
                queriesPerMinute: 60,
                documentsPerDay: 1000,
                maxConcurrentWebSockets: 5,
                maxDocumentSize: 1_000_000
            ),
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
            organizationId: nil,
            tier: .free,
            config: TenantConfiguration(
                queriesPerMinute: 60,
                documentsPerDay: 1000,
                maxConcurrentWebSockets: 5,
                maxDocumentSize: 1_000_000
            ),
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
        let rateLimiter = TenantRateLimiter(
            defaultConfig: TenantConfiguration(
                queriesPerMinute: 5,  // Very restrictive for testing
                documentsPerDay: 100
            )
        )

        let tenantId = "tenant_test"
        let operation = RateLimitOperation.query

        // Set the configuration for the tenant
        await rateLimiter.setConfiguration(
            for: tenantId,
            config: TenantConfiguration(queriesPerMinute: 5, documentsPerDay: 100)
        )

        // Make requests up to the limit (5 queries per minute)
        for _ in 0..<5 {
            try await rateLimiter.checkLimit(tenantId: tenantId, operation: operation)
            await rateLimiter.recordUsage(tenantId: tenantId, operation: operation)
        }

        // Next request should be rate limited and throw
        do {
            try await rateLimiter.checkLimit(tenantId: tenantId, operation: operation)
            XCTFail("Should have been rate limited")
        } catch {
            // Expected - rate limit exceeded
        }
    }

    /// Test rate limiter with concurrent requests
    func testRateLimiterThreadSafety() async throws {
        let rateLimiter = TenantRateLimiter(
            defaultConfig: TenantConfiguration(queriesPerMinute: 10, documentsPerDay: 100)
        )

        let tenantId = "tenant_concurrent"
        let operation = RateLimitOperation.query

        // Launch 20 concurrent requests
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    do {
                        try await rateLimiter.checkLimit(tenantId: tenantId, operation: operation)
                        await rateLimiter.recordUsage(tenantId: tenantId, operation: operation)
                        return true
                    } catch {
                        return false
                    }
                }
            }

            var allowedCount = 0
            for await allowed in group {
                if allowed {
                    allowedCount += 1
                }
            }

            // Should allow approximately the rate limit (10), with some variance due to concurrency
            XCTAssertLessThanOrEqual(
                allowedCount,
                12,  // Allow slight overflow due to concurrency
                "Rate limiter should allow approximately 10 requests, got \(allowedCount)"
            )
        }
    }

    /// Test that different tenants have independent rate limits
    func testRateLimiterTenantIsolation() async throws {
        let rateLimiter = TenantRateLimiter(
            defaultConfig: TenantConfiguration(queriesPerMinute: 3, documentsPerDay: 100)
        )

        let tenant1 = "tenant_1"
        let tenant2 = "tenant_2"
        let operation = RateLimitOperation.query

        // Exhaust tenant1's limit (3 queries)
        for _ in 0..<3 {
            try await rateLimiter.checkLimit(tenantId: tenant1, operation: operation)
            await rateLimiter.recordUsage(tenantId: tenant1, operation: operation)
        }

        // Tenant1 should be blocked
        do {
            try await rateLimiter.checkLimit(tenantId: tenant1, operation: operation)
            XCTFail("Tenant 1 should be rate limited")
        } catch {
            // Expected
        }

        // Tenant2 should still have full quota
        try await rateLimiter.checkLimit(tenantId: tenant2, operation: operation)
        // If we get here without throwing, tenant2 is not affected by tenant1's limits
    }

    // MARK: - Tenant Isolation Tests

    /// Test that tenants cannot access each other's data via API key
    func testTenantCannotAccessOtherTenantData() async throws {
        let storage = InMemoryTenantStorage()

        // Create two tenants
        let tenant1 = TenantContext(
            tenantId: "tenant_1",
            organizationId: nil,
            tier: .free,
            config: TenantConfiguration(
                queriesPerMinute: 60,
                documentsPerDay: 1000,
                maxConcurrentWebSockets: 5,
                maxDocumentSize: 1_000_000
            ),
            createdAt: Date()
        )

        let tenant2 = TenantContext(
            tenantId: "tenant_2",
            organizationId: nil,
            tier: .free,
            config: TenantConfiguration(
                queriesPerMinute: 60,
                documentsPerDay: 1000,
                maxConcurrentWebSockets: 5,
                maxDocumentSize: 1_000_000
            ),
            createdAt: Date()
        )

        try await storage.store(tenant1)
        try await storage.store(tenant2)

        let manager = TenantManager(storage: storage)

        // Resolve tenant1 with their API key
        await storage.setApiKey("key_1", for: tenant1)
        let resolved1 = try await manager.resolve(from: "key_1")
        XCTAssertEqual(resolved1.tenantId, "tenant_1")

        // Resolve tenant2 with their API key
        await storage.setApiKey("key_2", for: tenant2)
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
                organizationId: nil,
                tier: .free,
                config: TenantConfiguration(
                    queriesPerMinute: 60,
                    documentsPerDay: 1000,
                    maxConcurrentWebSockets: 5,
                    maxDocumentSize: 1_000_000
                ),
                createdAt: Date()
            )
            try await storage.store(tenant)
            await storage.setApiKey("key_\(i)", for: tenant)
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

    func save(_ tenant: TenantContext) async throws {
        tenants[tenant.tenantId] = tenant
    }

    func store(_ tenant: TenantContext) async throws {
        try await save(tenant)
    }

    func find(tenantId: String) async throws -> TenantContext? {
        tenants[tenantId]
    }

    func findByApiKey(_ apiKey: String) async throws -> TenantContext? {
        apiKeyMap[apiKey]
    }

    func update(_ tenant: TenantContext) async throws {
        try await save(tenant)
    }

    func delete(tenantId: String) async throws {
        tenants.removeValue(forKey: tenantId)
    }

    func list(limit: Int, offset: Int) async throws -> [TenantContext] {
        Array(tenants.values.sorted { $0.createdAt > $1.createdAt }.prefix(limit).dropFirst(offset))
    }

    func setApiKey(_ apiKey: String, for tenant: TenantContext) async {
        apiKeyMap[apiKey] = tenant
    }
}

/// Test rate limit policy
actor TestRateLimitPolicy: TenantRateLimitPolicy {
    private var usage: [String: [RateLimitOperation: Int]] = [:]

    func checkLimit(tenantId: String, operation: RateLimitOperation) async throws {
        // Simple implementation for testing - no actual limit checking
    }

    func recordUsage(tenantId: String, operation: RateLimitOperation) async {
        usage[tenantId, default: [:]][operation, default: 0] += 1
    }

    func getRemainingQuota(tenantId: String, operation: RateLimitOperation) async -> Int? {
        let current = usage[tenantId]?[operation] ?? 0
        return max(0, 1000 - current)
    }
}
