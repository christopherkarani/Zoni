// ZoniServer - Server-side extensions for Zoni
//
// TenantRateLimiter.swift - Per-tenant rate limiting using token bucket algorithm.
//
// This actor enforces rate limits on operations per tenant with configurable
// limits based on tenant tier.

import Foundation

// MARK: - Rate Limit Constants

/// Constants for rate limiting calculations.
///
/// These values define the relationship between configuration limits
/// and token bucket parameters for different operation types.
private enum RateLimitConstants {
    /// Ingest burst capacity is 1/24 of daily limit (1 hour's worth).
    ///
    /// This allows ingesting a reasonable batch while preventing
    /// exhaustion of the entire daily quota in a single burst.
    static let ingestBurstDivisor: Double = 24.0

    /// Seconds in a day for calculating per-second rates.
    static let secondsPerDay: Double = 24.0 * 60.0 * 60.0

    /// Seconds in a minute for calculating per-second rates.
    static let secondsPerMinute: Double = 60.0

    /// WebSocket refill is conservative at 1 connection per 10 seconds.
    ///
    /// This prevents rapid reconnection flooding while allowing
    /// reasonable recovery from disconnections.
    static let websocketRefillDivisor: Double = 10.0

    /// Batch embed capacity is half of query capacity.
    ///
    /// Batch embedding is more resource-intensive, so we apply
    /// a more conservative limit.
    static let batchEmbedCapacityDivisor: Double = 2.0

    /// Batch embed refill is half the rate of queries.
    ///
    /// This maintains the 2:1 ratio between queries and batch embeds.
    static let batchEmbedRefillDivisor: Double = 120.0
}

// MARK: - TenantRateLimiter

/// Actor that enforces rate limits per tenant using the token bucket algorithm.
///
/// `TenantRateLimiter` provides thread-safe rate limiting with configurable
/// limits based on tenant tier. It uses the token bucket algorithm which
/// allows for burst traffic while maintaining average rate limits.
///
/// ## Token Bucket Algorithm
///
/// Each tenant/operation pair maintains a bucket that:
/// - Has a maximum capacity (burst limit)
/// - Refills at a constant rate (sustained rate)
/// - Consumes one token per operation
///
/// This allows short bursts while preventing sustained overuse.
///
/// ## Example Usage
///
/// ```swift
/// let limiter = TenantRateLimiter()
///
/// // Configure limits for a tenant
/// await limiter.setConfiguration(
///     for: "tenant_123",
///     config: TenantConfiguration.forTier(.professional)
/// )
///
/// // Check if operation is allowed
/// try await limiter.checkLimit(tenantId: "tenant_123", operation: .query)
///
/// // Record usage after successful operation
/// await limiter.recordUsage(tenantId: "tenant_123", operation: .query)
///
/// // Check remaining quota
/// if let remaining = await limiter.getRemainingQuota(
///     tenantId: "tenant_123",
///     operation: .query
/// ) {
///     print("Remaining queries: \(remaining)")
/// }
/// ```
///
/// ## Thread Safety
///
/// As an actor, `TenantRateLimiter` guarantees thread-safe access to all
/// internal state. Rate limit checks and updates are atomic within the
/// actor's execution context.
public actor TenantRateLimiter: TenantRateLimitPolicy {

    // MARK: - Nested Types

    /// Token bucket state for a tenant/operation pair.
    ///
    /// The bucket maintains the current token count and refills
    /// tokens over time at the configured rate.
    private struct TokenBucket: Sendable {
        /// The current number of tokens available.
        var tokens: Double

        /// The last time tokens were refilled.
        var lastRefill: ContinuousClock.Instant

        /// The maximum number of tokens (burst capacity).
        let capacity: Double

        /// The rate at which tokens are added (tokens per second).
        let refillRate: Double
    }

    // MARK: - Properties

    /// Token buckets keyed by "tenantId:operation".
    private var buckets: [String: TokenBucket] = [:]

    /// Tenant-specific configurations keyed by tenant ID.
    private var tenantConfigs: [String: TenantConfiguration] = [:]

    /// Default configuration used when no tenant-specific config is set.
    private let defaultConfig: TenantConfiguration

    // MARK: - Initialization

    /// Creates a new rate limiter with optional default configuration.
    ///
    /// - Parameter defaultConfig: The default configuration to use for
    ///   tenants without specific configuration. Defaults to standard tier settings.
    ///
    /// ## Example
    /// ```swift
    /// // Use standard defaults
    /// let limiter = TenantRateLimiter()
    ///
    /// // Use custom defaults
    /// let customLimiter = TenantRateLimiter(
    ///     defaultConfig: TenantConfiguration.forTier(.professional)
    /// )
    /// ```
    public init(defaultConfig: TenantConfiguration = .default) {
        self.defaultConfig = defaultConfig
    }

    // MARK: - Configuration

    /// Sets the rate limit configuration for a specific tenant.
    ///
    /// When configuration is set, existing buckets for the tenant are
    /// cleared to ensure the new limits take effect immediately.
    ///
    /// - Parameters:
    ///   - tenantId: The unique identifier of the tenant.
    ///   - config: The configuration containing rate limits.
    ///
    /// ## Example
    /// ```swift
    /// // Set configuration for a professional tier tenant
    /// await limiter.setConfiguration(
    ///     for: "tenant_123",
    ///     config: TenantConfiguration.forTier(.professional)
    /// )
    ///
    /// // Set custom configuration
    /// await limiter.setConfiguration(
    ///     for: "tenant_456",
    ///     config: TenantConfiguration(
    ///         queriesPerMinute: 500,
    ///         documentsPerDay: 5000
    ///     )
    /// )
    /// ```
    public func setConfiguration(for tenantId: String, config: TenantConfiguration) {
        tenantConfigs[tenantId] = config

        // Clear existing buckets for this tenant to apply new limits
        buckets = buckets.filter { !$0.key.hasPrefix("\(tenantId):") }
    }

    /// Removes the configuration for a specific tenant.
    ///
    /// After removal, the tenant will use the default configuration.
    ///
    /// - Parameter tenantId: The unique identifier of the tenant.
    public func removeConfiguration(for tenantId: String) {
        tenantConfigs.removeValue(forKey: tenantId)
        buckets = buckets.filter { !$0.key.hasPrefix("\(tenantId):") }
    }

    // MARK: - TenantRateLimitPolicy Protocol

    /// Checks if an operation is allowed under current rate limits.
    ///
    /// This method refills the token bucket based on elapsed time, then
    /// checks if at least one token is available. If the bucket is empty,
    /// a rate limit error is thrown.
    ///
    /// - Parameters:
    ///   - tenantId: The unique identifier of the tenant.
    ///   - operation: The type of operation being performed.
    /// - Throws: `ZoniServerError.rateLimited` if the rate limit has been
    ///   exceeded, including a suggested retry duration.
    ///
    /// ## Example
    /// ```swift
    /// do {
    ///     try await limiter.checkLimit(tenantId: "tenant_123", operation: .query)
    ///     // Proceed with query
    /// } catch let error as ZoniServerError {
    ///     // Handle rate limit exceeded
    ///     print(error.localizedDescription)
    /// }
    /// ```
    public func checkLimit(
        tenantId: String,
        operation: RateLimitOperation
    ) async throws {
        let key = bucketKey(tenantId: tenantId, operation: operation)
        var bucket = getOrCreateBucket(tenantId: tenantId, operation: operation)

        // Refill tokens based on elapsed time
        refillBucket(&bucket)
        buckets[key] = bucket

        if bucket.tokens < 1.0 {
            // Calculate retry duration based on refill rate
            let tokensNeeded = 1.0 - bucket.tokens
            let secondsUntilRefill = tokensNeeded / bucket.refillRate
            let retryAfter = Duration.seconds(secondsUntilRefill)

            throw ZoniServerError.rateLimited(operation: operation, retryAfter: retryAfter)
        }
    }

    /// Records that an operation was performed by a tenant.
    ///
    /// This method consumes one token from the bucket. Call this after
    /// successfully completing a rate-limited operation to track usage.
    ///
    /// - Parameters:
    ///   - tenantId: The unique identifier of the tenant.
    ///   - operation: The type of operation that was performed.
    ///
    /// ## Example
    /// ```swift
    /// try await limiter.checkLimit(tenantId: tenantId, operation: .query)
    /// let result = try await performQuery(query)
    /// await limiter.recordUsage(tenantId: tenantId, operation: .query)
    /// return result
    /// ```
    public func recordUsage(
        tenantId: String,
        operation: RateLimitOperation
    ) async {
        let key = bucketKey(tenantId: tenantId, operation: operation)

        if var bucket = buckets[key] {
            // Refill first, then consume
            refillBucket(&bucket)
            bucket.tokens = max(0, bucket.tokens - 1.0)
            buckets[key] = bucket
        } else {
            // Create bucket and consume initial token
            var bucket = getOrCreateBucket(tenantId: tenantId, operation: operation)
            bucket.tokens = max(0, bucket.tokens - 1.0)
            buckets[key] = bucket
        }
    }

    /// Returns the remaining quota for a specific operation.
    ///
    /// This method returns the current number of tokens available in the
    /// bucket after refilling based on elapsed time.
    ///
    /// - Parameters:
    ///   - tenantId: The unique identifier of the tenant.
    ///   - operation: The type of operation to check.
    /// - Returns: The number of operations remaining before the limit is
    ///   reached, or `nil` if quota information is unavailable.
    ///
    /// ## Example
    /// ```swift
    /// if let remaining = await limiter.getRemainingQuota(
    ///     tenantId: context.tenantId,
    ///     operation: .query
    /// ) {
    ///     response.headers.add(name: "X-RateLimit-Remaining", value: "\(remaining)")
    /// }
    /// ```
    public func getRemainingQuota(
        tenantId: String,
        operation: RateLimitOperation
    ) async -> Int? {
        let key = bucketKey(tenantId: tenantId, operation: operation)

        if var bucket = buckets[key] {
            refillBucket(&bucket)
            buckets[key] = bucket
            return Int(bucket.tokens)
        }

        // Return capacity if no bucket exists yet (full quota available)
        let config = tenantConfigs[tenantId] ?? defaultConfig
        let capacity = getCapacity(for: operation, config: config)
        return Int(capacity)
    }

    // MARK: - Management

    /// Resets all rate limits for a specific tenant.
    ///
    /// This removes all buckets for the tenant, effectively resetting
    /// their quota to full capacity for all operations.
    ///
    /// - Parameter tenantId: The unique identifier of the tenant.
    ///
    /// ## Example
    /// ```swift
    /// // Reset limits after upgrading tenant tier
    /// await limiter.resetLimits(for: "tenant_123")
    /// ```
    public func resetLimits(for tenantId: String) {
        buckets = buckets.filter { !$0.key.hasPrefix("\(tenantId):") }
    }

    /// Resets all rate limits for all tenants.
    ///
    /// Use with caution as this affects all tenants in the system.
    ///
    /// ## Example
    /// ```swift
    /// // Reset all limits (e.g., for testing or emergency situations)
    /// await limiter.resetAllLimits()
    /// ```
    public func resetAllLimits() {
        buckets.removeAll()
    }

    /// Returns the total number of active buckets.
    ///
    /// This is useful for monitoring and debugging rate limiter state.
    ///
    /// - Returns: The number of tenant/operation buckets currently tracked.
    public var activeBucketCount: Int {
        buckets.count
    }

    /// Returns rate limit information for a tenant/operation pair.
    ///
    /// - Parameters:
    ///   - tenantId: The unique identifier of the tenant.
    ///   - operation: The operation to get limits for.
    /// - Returns: A tuple containing (remaining tokens, capacity, refill rate per second).
    public func getLimitInfo(
        tenantId: String,
        operation: RateLimitOperation
    ) -> (remaining: Int, capacity: Int, refillRatePerSecond: Double) {
        let config = tenantConfigs[tenantId] ?? defaultConfig
        let capacity = getCapacity(for: operation, config: config)
        let refillRate = getRefillRate(for: operation, config: config)

        let key = bucketKey(tenantId: tenantId, operation: operation)
        if var bucket = buckets[key] {
            refillBucket(&bucket)
            buckets[key] = bucket
            return (Int(bucket.tokens), Int(capacity), refillRate)
        }

        return (Int(capacity), Int(capacity), refillRate)
    }

    // MARK: - Private Helpers

    /// Creates a unique key for a tenant/operation bucket.
    ///
    /// - Parameters:
    ///   - tenantId: The tenant identifier.
    ///   - operation: The operation type.
    /// - Returns: A unique string key for the bucket.
    private func bucketKey(tenantId: String, operation: RateLimitOperation) -> String {
        "\(tenantId):\(operation.rawValue)"
    }

    /// Gets or creates a token bucket for a tenant/operation pair.
    ///
    /// - Parameters:
    ///   - tenantId: The tenant identifier.
    ///   - operation: The operation type.
    /// - Returns: The existing or newly created bucket.
    private func getOrCreateBucket(
        tenantId: String,
        operation: RateLimitOperation
    ) -> TokenBucket {
        let key = bucketKey(tenantId: tenantId, operation: operation)

        if let existing = buckets[key] {
            return existing
        }

        // Create new bucket based on tenant configuration
        let config = tenantConfigs[tenantId] ?? defaultConfig
        let capacity = getCapacity(for: operation, config: config)
        let refillRate = getRefillRate(for: operation, config: config)

        return TokenBucket(
            tokens: capacity,
            lastRefill: .now,
            capacity: capacity,
            refillRate: refillRate
        )
    }

    /// Refills tokens in a bucket based on elapsed time.
    ///
    /// This method uses precise time calculation to avoid floating-point
    /// precision loss that could affect token accounting.
    ///
    /// - Parameter bucket: The bucket to refill (modified in place).
    private func refillBucket(_ bucket: inout TokenBucket) {
        let now = ContinuousClock.Instant.now
        let elapsed = now - bucket.lastRefill

        // Calculate elapsed seconds with better precision handling
        // For short durations, attoseconds dominate; for long durations, seconds dominate
        let components = elapsed.components
        let elapsedSeconds: Double

        if components.seconds > 0 {
            // For longer durations, seconds provide good precision
            // Add attoseconds as fraction (1 attosecond = 10^-18 seconds)
            elapsedSeconds = Double(components.seconds) +
                (Double(components.attoseconds) * 1.0e-18)
        } else {
            // For sub-second durations, use attoseconds directly for precision
            elapsedSeconds = Double(components.attoseconds) * 1.0e-18
        }

        // Calculate and add tokens, capping at bucket capacity
        let tokensToAdd = elapsedSeconds * bucket.refillRate
        bucket.tokens = min(bucket.capacity, bucket.tokens + tokensToAdd)
        bucket.lastRefill = now
    }

    /// Gets the bucket capacity for an operation based on configuration.
    ///
    /// The capacity determines the maximum burst size for each operation type.
    /// Different operations have different burst characteristics based on
    /// their resource usage and typical usage patterns.
    ///
    /// - Parameters:
    ///   - operation: The operation type.
    ///   - config: The tenant configuration.
    /// - Returns: The bucket capacity (maximum tokens).
    private func getCapacity(
        for operation: RateLimitOperation,
        config: TenantConfiguration
    ) -> Double {
        switch operation {
        case .query, .retrieve:
            // Allow burst up to 1 minute's worth of queries
            return Double(config.queriesPerMinute)

        case .ingest:
            // Allow burst up to 1 hour's worth of ingestions
            return Double(config.documentsPerDay) / RateLimitConstants.ingestBurstDivisor

        case .websocket:
            // WebSocket connections use concurrent limit directly
            return Double(config.maxConcurrentWebSockets)

        case .batchEmbed:
            // Batch embedding has lower burst than regular queries
            return Double(config.queriesPerMinute) / RateLimitConstants.batchEmbedCapacityDivisor
        }
    }

    /// Gets the refill rate for an operation based on configuration.
    ///
    /// The refill rate determines the sustained throughput for each operation.
    /// Rates are calculated from the configured limits (per-minute, per-day)
    /// converted to tokens per second.
    ///
    /// - Parameters:
    ///   - operation: The operation type.
    ///   - config: The tenant configuration.
    /// - Returns: The refill rate in tokens per second.
    private func getRefillRate(
        for operation: RateLimitOperation,
        config: TenantConfiguration
    ) -> Double {
        switch operation {
        case .query, .retrieve:
            // Queries per minute -> queries per second
            return Double(config.queriesPerMinute) / RateLimitConstants.secondsPerMinute

        case .ingest:
            // Documents per day -> documents per second
            return Double(config.documentsPerDay) / RateLimitConstants.secondsPerDay

        case .websocket:
            // WebSocket connections refill conservatively
            return Double(config.maxConcurrentWebSockets) / RateLimitConstants.websocketRefillDivisor

        case .batchEmbed:
            // Batch embedding follows half the query rate
            return Double(config.queriesPerMinute) / RateLimitConstants.batchEmbedRefillDivisor
        }
    }
}

// MARK: - TenantRateLimiter Debugging

extension TenantRateLimiter {

    /// Returns a snapshot of all bucket states for debugging.
    ///
    /// - Returns: A dictionary mapping bucket keys to their current token counts.
    public func getBucketSnapshot() -> [String: Double] {
        var snapshot: [String: Double] = [:]
        for (key, bucket) in buckets {
            var mutableBucket = bucket
            refillBucket(&mutableBucket)
            snapshot[key] = mutableBucket.tokens
        }
        return snapshot
    }

    /// Returns all configured tenant IDs.
    ///
    /// - Returns: An array of tenant IDs that have custom configurations.
    public var configuredTenantIds: [String] {
        Array(tenantConfigs.keys)
    }
}
