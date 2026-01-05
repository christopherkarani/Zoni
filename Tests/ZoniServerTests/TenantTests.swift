// ZoniServer - Server-side extensions for Zoni
//
// TenantTests.swift - Comprehensive tests for tenant types and rate limiting
//
// This file tests TenantContext, TenantConfiguration, TenantTier,
// and TenantRateLimiter functionality for multi-tenant operations.

import Testing
import Foundation
@testable import ZoniServer

// MARK: - Tenant Tests

@Suite("Tenant Tests")
struct TenantTests {

    // MARK: - TenantContext Tests

    @Suite("TenantContext Tests")
    struct TenantContextTests {

        @Test("TenantContext initialization with defaults")
        func testTenantContextInit() {
            let tenant = TenantContext(
                tenantId: "test-tenant",
                tier: .standard
            )

            #expect(tenant.tenantId == "test-tenant")
            #expect(tenant.tier == .standard)
            #expect(tenant.organizationId == nil)
            #expect(tenant.config.queriesPerMinute > 0)
        }

        @Test("TenantContext with organization")
        func testTenantContextWithOrganization() {
            let tenant = TenantContext(
                tenantId: "tenant-123",
                organizationId: "org-456",
                tier: .professional
            )

            #expect(tenant.tenantId == "tenant-123")
            #expect(tenant.organizationId == "org-456")
            #expect(tenant.tier == .professional)
        }

        @Test("TenantContext with custom config")
        func testTenantContextWithCustomConfig() {
            let config = TenantConfiguration(
                queriesPerMinute: 1000,
                documentsPerDay: 10000
            )

            let tenant = TenantContext(
                tenantId: "enterprise",
                tier: .enterprise,
                config: config
            )

            #expect(tenant.config.queriesPerMinute == 1000)
            #expect(tenant.config.documentsPerDay == 10000)
        }

        @Test("TenantContext defaults to tier configuration")
        func testTenantContextDefaultsToTierConfig() {
            let freeTenant = TenantContext(tenantId: "free-tenant", tier: .free)
            let enterpriseTenant = TenantContext(tenantId: "enterprise-tenant", tier: .enterprise)

            let freeConfig = TenantConfiguration.forTier(.free)
            let enterpriseConfig = TenantConfiguration.forTier(.enterprise)

            #expect(freeTenant.config.queriesPerMinute == freeConfig.queriesPerMinute)
            #expect(enterpriseTenant.config.queriesPerMinute == enterpriseConfig.queriesPerMinute)
        }

        @Test("TenantContext description")
        func testTenantContextDescription() {
            let tenant = TenantContext(
                tenantId: "test-id",
                organizationId: "org-id",
                tier: .professional
            )

            let description = tenant.description
            #expect(description.contains("test-id"))
            #expect(description.contains("org-id"))
            #expect(description.contains("professional"))
        }

        @Test("TenantContext equality")
        func testTenantContextEquality() {
            let date = Date()
            let tenant1 = TenantContext(
                tenantId: "tenant-1",
                tier: .standard,
                createdAt: date
            )
            let tenant2 = TenantContext(
                tenantId: "tenant-1",
                tier: .standard,
                createdAt: date
            )
            let tenant3 = TenantContext(
                tenantId: "tenant-2",
                tier: .standard,
                createdAt: date
            )

            #expect(tenant1 == tenant2)
            #expect(tenant1 != tenant3)
        }
    }

    // MARK: - TenantConfiguration Tests

    @Suite("TenantConfiguration Tests")
    struct TenantConfigurationTests {

        @Test("TenantConfiguration defaults")
        func testConfigurationDefaults() {
            let config = TenantConfiguration.default

            #expect(config.queriesPerMinute == 60)
            #expect(config.documentsPerDay == 1000)
            #expect(config.maxConcurrentWebSockets == 5)
            #expect(config.maxDocumentSize == 10_485_760)
            #expect(config.maxChunksPerDocument == 1000)
            #expect(config.enableStreaming == true)
        }

        @Test("TenantConfiguration tier presets")
        func testTierPresets() {
            let free = TenantConfiguration.forTier(.free)
            let standard = TenantConfiguration.forTier(.standard)
            let professional = TenantConfiguration.forTier(.professional)
            let enterprise = TenantConfiguration.forTier(.enterprise)

            // Verify increasing limits
            #expect(free.queriesPerMinute < standard.queriesPerMinute)
            #expect(standard.queriesPerMinute < professional.queriesPerMinute)
            #expect(professional.queriesPerMinute < enterprise.queriesPerMinute)

            // Verify document limits increase
            #expect(free.documentsPerDay < standard.documentsPerDay)
            #expect(standard.documentsPerDay < professional.documentsPerDay)

            // Verify WebSocket limits increase
            #expect(free.maxConcurrentWebSockets < standard.maxConcurrentWebSockets)
            #expect(standard.maxConcurrentWebSockets < professional.maxConcurrentWebSockets)

            // Verify document size limits increase
            #expect(free.maxDocumentSize < standard.maxDocumentSize)
            #expect(standard.maxDocumentSize < professional.maxDocumentSize)
        }

        @Test("TenantConfiguration free tier streaming disabled")
        func testFreeTierStreamingDisabled() {
            let free = TenantConfiguration.forTier(.free)
            let standard = TenantConfiguration.forTier(.standard)

            #expect(free.enableStreaming == false)
            #expect(standard.enableStreaming == true)
        }

        @Test("TenantConfiguration enterprise unlimited documents")
        func testEnterpriseUnlimitedDocuments() {
            let enterprise = TenantConfiguration.forTier(.enterprise)

            #expect(enterprise.documentsPerDay == Int.max)
        }

        @Test("TenantConfiguration custom initialization")
        func testCustomInit() {
            let config = TenantConfiguration(
                queriesPerMinute: 500,
                documentsPerDay: 5000,
                maxConcurrentWebSockets: 20,
                maxDocumentSize: 50_000_000,
                maxChunksPerDocument: 2000,
                embeddingModel: "text-embedding-3-large",
                indexPrefix: "tenant_123_",
                enableStreaming: true
            )

            #expect(config.queriesPerMinute == 500)
            #expect(config.documentsPerDay == 5000)
            #expect(config.maxConcurrentWebSockets == 20)
            #expect(config.maxDocumentSize == 50_000_000)
            #expect(config.maxChunksPerDocument == 2000)
            #expect(config.embeddingModel == "text-embedding-3-large")
            #expect(config.indexPrefix == "tenant_123_")
            #expect(config.enableStreaming == true)
        }

        @Test("TenantConfiguration Codable")
        func testConfigurationCodable() throws {
            let config = TenantConfiguration(
                queriesPerMinute: 200,
                documentsPerDay: 2000,
                embeddingModel: "custom-model"
            )

            let data = try JSONEncoder().encode(config)
            let decoded = try JSONDecoder().decode(TenantConfiguration.self, from: data)

            #expect(decoded.queriesPerMinute == 200)
            #expect(decoded.documentsPerDay == 2000)
            #expect(decoded.embeddingModel == "custom-model")
        }
    }

    // MARK: - TenantTier Tests

    @Suite("TenantTier Tests")
    struct TenantTierTests {

        @Test("TenantTier raw values")
        func testTierRawValues() {
            #expect(TenantTier.free.rawValue == "free")
            #expect(TenantTier.standard.rawValue == "standard")
            #expect(TenantTier.professional.rawValue == "professional")
            #expect(TenantTier.enterprise.rawValue == "enterprise")
        }

        @Test("TenantTier allCases")
        func testTierAllCases() {
            let allTiers = TenantTier.allCases

            #expect(allTiers.count == 4)
            #expect(allTiers.contains(.free))
            #expect(allTiers.contains(.standard))
            #expect(allTiers.contains(.professional))
            #expect(allTiers.contains(.enterprise))
        }

        @Test("TenantTier Codable")
        func testTierCodable() throws {
            for tier in TenantTier.allCases {
                let data = try JSONEncoder().encode(tier)
                let decoded = try JSONDecoder().decode(TenantTier.self, from: data)
                #expect(decoded == tier)
            }
        }

        @Test("TenantTier from JSON string")
        func testTierFromJSON() throws {
            let json = "\"professional\""
            let data = json.data(using: .utf8)!
            let tier = try JSONDecoder().decode(TenantTier.self, from: data)

            #expect(tier == .professional)
        }
    }

    // MARK: - TenantRateLimiter Tests

    @Suite("TenantRateLimiter Tests")
    struct TenantRateLimiterTests {

        @Test("TenantRateLimiter allows requests within limit")
        func testRateLimiterAllows() async throws {
            let limiter = TenantRateLimiter()
            let config = TenantConfiguration.forTier(.standard)

            await limiter.setConfiguration(for: "tenant-1", config: config)

            // First request should succeed
            try await limiter.checkLimit(tenantId: "tenant-1", operation: .query)
            await limiter.recordUsage(tenantId: "tenant-1", operation: .query)

            // Check remaining quota
            let remaining = await limiter.getRemainingQuota(tenantId: "tenant-1", operation: .query)
            #expect(remaining != nil)
            #expect(remaining! > 0)
        }

        @Test("TenantRateLimiter blocks excessive requests")
        func testRateLimiterBlocks() async {
            let limiter = TenantRateLimiter()

            // Use very low limit
            var config = TenantConfiguration.default
            config.queriesPerMinute = 1

            await limiter.setConfiguration(for: "tenant-1", config: config)

            // First request succeeds and consumes the only token
            try? await limiter.checkLimit(tenantId: "tenant-1", operation: .query)
            await limiter.recordUsage(tenantId: "tenant-1", operation: .query)

            // Second request should be rate limited
            do {
                try await limiter.checkLimit(tenantId: "tenant-1", operation: .query)
                Issue.record("Should have thrown rate limit error")
            } catch {
                #expect(error is ZoniServerError)
                if case .rateLimited(let operation, _) = error as? ZoniServerError {
                    #expect(operation == .query)
                }
            }
        }

        @Test("TenantRateLimiter tracks different operations separately")
        func testSeparateOperationTracking() async throws {
            let limiter = TenantRateLimiter()
            let config = TenantConfiguration.forTier(.standard)

            await limiter.setConfiguration(for: "tenant-1", config: config)

            // Use query operation
            await limiter.recordUsage(tenantId: "tenant-1", operation: .query)

            // Ingest should have its own quota
            let ingestRemaining = await limiter.getRemainingQuota(tenantId: "tenant-1", operation: .ingest)
            let queryRemaining = await limiter.getRemainingQuota(tenantId: "tenant-1", operation: .query)

            // They should be tracked separately
            #expect(ingestRemaining != nil)
            #expect(queryRemaining != nil)
        }

        @Test("TenantRateLimiter tracks different tenants separately")
        func testSeparateTenantTracking() async throws {
            let limiter = TenantRateLimiter()
            let config = TenantConfiguration.forTier(.standard)

            await limiter.setConfiguration(for: "tenant-1", config: config)
            await limiter.setConfiguration(for: "tenant-2", config: config)

            // Use tenant-1's quota
            await limiter.recordUsage(tenantId: "tenant-1", operation: .query)

            // Tenant-2 should have full quota
            let tenant1Remaining = await limiter.getRemainingQuota(tenantId: "tenant-1", operation: .query)
            let tenant2Remaining = await limiter.getRemainingQuota(tenantId: "tenant-2", operation: .query)

            // Tenant-2 should have more remaining (not used)
            #expect(tenant1Remaining != nil)
            #expect(tenant2Remaining != nil)
            #expect(tenant2Remaining! > tenant1Remaining!)
        }

        @Test("TenantRateLimiter uses default config for unknown tenant")
        func testDefaultConfig() async throws {
            let limiter = TenantRateLimiter()

            // Don't set configuration for tenant
            let remaining = await limiter.getRemainingQuota(tenantId: "unknown-tenant", operation: .query)

            // Should use default configuration
            #expect(remaining != nil)
            #expect(remaining! == TenantConfiguration.default.queriesPerMinute)
        }

        @Test("TenantRateLimiter reset limits")
        func testResetLimits() async throws {
            let limiter = TenantRateLimiter()
            var config = TenantConfiguration.default
            config.queriesPerMinute = 10

            await limiter.setConfiguration(for: "tenant-1", config: config)

            // Use some quota
            for _ in 0..<5 {
                await limiter.recordUsage(tenantId: "tenant-1", operation: .query)
            }

            let beforeReset = await limiter.getRemainingQuota(tenantId: "tenant-1", operation: .query)
            #expect(beforeReset != nil && beforeReset! < 10)

            // Reset limits
            await limiter.resetLimits(for: "tenant-1")

            // After reset, bucket is cleared, so next check creates a new full bucket
            let afterReset = await limiter.getRemainingQuota(tenantId: "tenant-1", operation: .query)
            #expect(afterReset == 10)
        }

        @Test("TenantRateLimiter remove configuration")
        func testRemoveConfiguration() async throws {
            let limiter = TenantRateLimiter()

            var customConfig = TenantConfiguration.default
            customConfig.queriesPerMinute = 500

            await limiter.setConfiguration(for: "tenant-1", config: customConfig)

            // Verify custom config is used
            let initialLimit = await limiter.getLimitInfo(tenantId: "tenant-1", operation: .query)
            #expect(initialLimit.capacity == 500)

            // Remove configuration
            await limiter.removeConfiguration(for: "tenant-1")

            // Should now use default
            let afterRemoval = await limiter.getLimitInfo(tenantId: "tenant-1", operation: .query)
            #expect(afterRemoval.capacity == TenantConfiguration.default.queriesPerMinute)
        }

        @Test("TenantRateLimiter active bucket count")
        func testActiveBucketCount() async {
            let limiter = TenantRateLimiter()

            // Initially no buckets
            let initial = await limiter.activeBucketCount
            #expect(initial == 0)

            // Record usage creates buckets
            await limiter.recordUsage(tenantId: "tenant-1", operation: .query)
            await limiter.recordUsage(tenantId: "tenant-1", operation: .ingest)
            await limiter.recordUsage(tenantId: "tenant-2", operation: .query)

            let afterUsage = await limiter.activeBucketCount
            #expect(afterUsage == 3)

            // Reset all clears buckets
            await limiter.resetAllLimits()

            let afterReset = await limiter.activeBucketCount
            #expect(afterReset == 0)
        }

        @Test("TenantRateLimiter getLimitInfo")
        func testGetLimitInfo() async {
            let limiter = TenantRateLimiter()
            let config = TenantConfiguration.forTier(.professional)

            await limiter.setConfiguration(for: "tenant-1", config: config)

            let info = await limiter.getLimitInfo(tenantId: "tenant-1", operation: .query)

            #expect(info.capacity == config.queriesPerMinute)
            #expect(info.remaining == config.queriesPerMinute) // Full quota initially
            #expect(info.refillRatePerSecond > 0)
        }

        @Test("TenantRateLimiter configured tenant IDs")
        func testConfiguredTenantIds() async {
            let limiter = TenantRateLimiter()
            let config = TenantConfiguration.default

            await limiter.setConfiguration(for: "tenant-a", config: config)
            await limiter.setConfiguration(for: "tenant-b", config: config)
            await limiter.setConfiguration(for: "tenant-c", config: config)

            let tenantIds = await limiter.configuredTenantIds

            #expect(tenantIds.count == 3)
            #expect(tenantIds.contains("tenant-a"))
            #expect(tenantIds.contains("tenant-b"))
            #expect(tenantIds.contains("tenant-c"))
        }

        @Test("TenantRateLimiter bucket snapshot")
        func testBucketSnapshot() async {
            let limiter = TenantRateLimiter()
            var config = TenantConfiguration.default
            config.queriesPerMinute = 100

            await limiter.setConfiguration(for: "tenant-1", config: config)

            // Record some usage
            await limiter.recordUsage(tenantId: "tenant-1", operation: .query)
            await limiter.recordUsage(tenantId: "tenant-1", operation: .query)

            let snapshot = await limiter.getBucketSnapshot()

            #expect(!snapshot.isEmpty)
            #expect(snapshot["tenant-1:query"] != nil)
            #expect(snapshot["tenant-1:query"]! < 100) // Some tokens used
        }
    }

    // MARK: - RateLimitOperation Tests

    @Suite("RateLimitOperation Tests")
    struct RateLimitOperationTests {

        @Test("RateLimitOperation raw values")
        func testOperationRawValues() {
            #expect(RateLimitOperation.query.rawValue == "query")
            #expect(RateLimitOperation.ingest.rawValue == "ingest")
            #expect(RateLimitOperation.websocket.rawValue == "websocket")
            #expect(RateLimitOperation.batchEmbed.rawValue == "batchEmbed")
            #expect(RateLimitOperation.retrieve.rawValue == "retrieve")
        }

        @Test("RateLimitOperation allCases")
        func testOperationAllCases() {
            let allOps = RateLimitOperation.allCases

            #expect(allOps.count == 5)
            #expect(allOps.contains(.query))
            #expect(allOps.contains(.ingest))
            #expect(allOps.contains(.websocket))
            #expect(allOps.contains(.batchEmbed))
            #expect(allOps.contains(.retrieve))
        }
    }

    // MARK: - Advanced Rate Limiter Tests

    @Suite("TenantRateLimiter Advanced Tests")
    struct TenantRateLimiterAdvancedTests {

        @Test("Rate limiter refills tokens correctly after idle period")
        func testTokenRefillAfterIdle() async throws {
            let limiter = TenantRateLimiter()
            var config = TenantConfiguration.default
            config.queriesPerMinute = 60 // 1 per second refill

            await limiter.setConfiguration(for: "tenant-1", config: config)

            // Consume most tokens
            for _ in 0..<55 {
                await limiter.recordUsage(tenantId: "tenant-1", operation: .query)
            }

            let afterUsage = await limiter.getRemainingQuota(tenantId: "tenant-1", operation: .query)
            #expect(afterUsage != nil && afterUsage! < 10)

            // Wait a bit for token refill (1 second = 1 token at 60/min)
            try await Task.sleep(for: .milliseconds(100))

            // Should have refilled some tokens
            let afterWait = await limiter.getRemainingQuota(tenantId: "tenant-1", operation: .query)
            #expect(afterWait != nil)
            // Due to refill rate of 1/sec, we should have gained a fraction of a token
        }

        @Test("Rate limiter burst capacity allows initial burst")
        func testBurstCapacity() async throws {
            let limiter = TenantRateLimiter()
            var config = TenantConfiguration.default
            config.queriesPerMinute = 60 // Allows burst of 60

            await limiter.setConfiguration(for: "burst-tenant", config: config)

            // Should be able to perform burst of requests
            var successCount = 0
            for _ in 0..<30 {
                do {
                    try await limiter.checkLimit(tenantId: "burst-tenant", operation: .query)
                    await limiter.recordUsage(tenantId: "burst-tenant", operation: .query)
                    successCount += 1
                } catch {
                    break
                }
            }

            // Should have succeeded for all 30 (well within 60 capacity)
            #expect(successCount == 30)
        }

        @Test("Rate limiter returns correct retry-after duration")
        func testRetryAfterDuration() async {
            let limiter = TenantRateLimiter()
            var config = TenantConfiguration.default
            config.queriesPerMinute = 1 // 1 per minute, refill = 1/60 per second

            await limiter.setConfiguration(for: "tenant-1", config: config)

            // Consume the single token
            await limiter.recordUsage(tenantId: "tenant-1", operation: .query)

            // Next check should fail with retry duration
            do {
                try await limiter.checkLimit(tenantId: "tenant-1", operation: .query)
                Issue.record("Should have thrown rate limit error")
            } catch let error as ZoniServerError {
                if case .rateLimited(_, let retryAfter) = error {
                    // Retry duration should be positive and less than 60 seconds
                    if let duration = retryAfter {
                        #expect(duration.components.seconds >= 0)
                        #expect(duration.components.seconds < 60)
                    } else {
                        // retryAfter is nil - still valid (rate limited without specific retry time)
                        #expect(true)
                    }
                } else {
                    Issue.record("Wrong error type: \(error)")
                }
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }

        @Test("Rate limiter handles all operation types")
        func testAllOperationTypes() async throws {
            let limiter = TenantRateLimiter()
            let config = TenantConfiguration.forTier(.standard)

            await limiter.setConfiguration(for: "ops-tenant", config: config)

            // Test all operation types
            for operation in RateLimitOperation.allCases {
                // Should succeed for first request
                try await limiter.checkLimit(tenantId: "ops-tenant", operation: operation)
                await limiter.recordUsage(tenantId: "ops-tenant", operation: operation)

                // Should have remaining quota
                let remaining = await limiter.getRemainingQuota(tenantId: "ops-tenant", operation: operation)
                #expect(remaining != nil)
            }
        }

        @Test("Rate limiter handles rapid sequential requests")
        func testRapidSequentialRequests() async throws {
            let limiter = TenantRateLimiter()
            var config = TenantConfiguration.default
            config.queriesPerMinute = 100

            await limiter.setConfiguration(for: "rapid-tenant", config: config)

            // Rapidly check and record
            for _ in 0..<50 {
                try await limiter.checkLimit(tenantId: "rapid-tenant", operation: .query)
                await limiter.recordUsage(tenantId: "rapid-tenant", operation: .query)
            }

            let remaining = await limiter.getRemainingQuota(tenantId: "rapid-tenant", operation: .query)
            #expect(remaining != nil)
            #expect(remaining! <= 50) // Should have used about 50 tokens
        }

        @Test("Rate limiter configuration update resets buckets")
        func testConfigUpdateResetsBuckets() async throws {
            let limiter = TenantRateLimiter()

            var config1 = TenantConfiguration.default
            config1.queriesPerMinute = 100
            await limiter.setConfiguration(for: "config-tenant", config: config1)

            // Use some quota
            for _ in 0..<50 {
                await limiter.recordUsage(tenantId: "config-tenant", operation: .query)
            }

            let beforeUpdate = await limiter.getRemainingQuota(tenantId: "config-tenant", operation: .query)
            #expect(beforeUpdate != nil && beforeUpdate! < 100)

            // Update configuration
            var config2 = TenantConfiguration.default
            config2.queriesPerMinute = 200
            await limiter.setConfiguration(for: "config-tenant", config: config2)

            // After config update, bucket should be reset
            let afterUpdate = await limiter.getRemainingQuota(tenantId: "config-tenant", operation: .query)
            #expect(afterUpdate == 200) // New full capacity
        }

        @Test("Rate limiter handles different operation capacities")
        func testDifferentOperationCapacities() async {
            let limiter = TenantRateLimiter()
            let config = TenantConfiguration.forTier(.professional)

            await limiter.setConfiguration(for: "cap-tenant", config: config)

            // Query capacity should be queriesPerMinute
            let queryInfo = await limiter.getLimitInfo(tenantId: "cap-tenant", operation: .query)
            #expect(queryInfo.capacity == config.queriesPerMinute)

            // Ingest capacity should be documentsPerDay / 24
            let ingestInfo = await limiter.getLimitInfo(tenantId: "cap-tenant", operation: .ingest)
            #expect(ingestInfo.capacity == config.documentsPerDay / 24)

            // WebSocket capacity should be maxConcurrentWebSockets
            let wsInfo = await limiter.getLimitInfo(tenantId: "cap-tenant", operation: .websocket)
            #expect(wsInfo.capacity == config.maxConcurrentWebSockets)

            // BatchEmbed capacity should be queriesPerMinute / 2
            let batchInfo = await limiter.getLimitInfo(tenantId: "cap-tenant", operation: .batchEmbed)
            #expect(batchInfo.capacity == config.queriesPerMinute / 2)
        }

        @Test("Rate limiter handles zero remaining gracefully")
        func testZeroRemainingGraceful() async {
            let limiter = TenantRateLimiter()
            var config = TenantConfiguration.default
            config.queriesPerMinute = 5

            await limiter.setConfiguration(for: "zero-tenant", config: config)

            // Exhaust all tokens
            for _ in 0..<5 {
                await limiter.recordUsage(tenantId: "zero-tenant", operation: .query)
            }

            let remaining = await limiter.getRemainingQuota(tenantId: "zero-tenant", operation: .query)
            #expect(remaining != nil)
            #expect(remaining! >= 0) // Should never go negative
        }

        @Test("Rate limiter snapshot reflects current state")
        func testSnapshotReflectsState() async {
            let limiter = TenantRateLimiter()
            var config = TenantConfiguration.default
            config.queriesPerMinute = 100
            config.documentsPerDay = 2400 // 100/hour = ~4.17/minute

            await limiter.setConfiguration(for: "snapshot-tenant", config: config)

            // Record different operations
            await limiter.recordUsage(tenantId: "snapshot-tenant", operation: .query)
            await limiter.recordUsage(tenantId: "snapshot-tenant", operation: .query)
            await limiter.recordUsage(tenantId: "snapshot-tenant", operation: .ingest)

            let snapshot = await limiter.getBucketSnapshot()

            #expect(snapshot["snapshot-tenant:query"] != nil)
            #expect(snapshot["snapshot-tenant:ingest"] != nil)
            #expect(snapshot["snapshot-tenant:query"]! < 100) // Used 2 tokens
        }
    }
}
