// ZoniServer - Server-side extensions for Zoni
//
// ServerProtocols.swift - Protocol abstractions for multi-tenant server operations

import Foundation

// MARK: - RateLimitOperation

/// Operations that are subject to rate limiting in the RAG server.
///
/// Each operation type may have different rate limits based on the tenant's
/// configuration and service tier. Rate limits are typically enforced per
/// tenant, per operation type.
///
/// ## Example
/// ```swift
/// // Check if a query operation is allowed
/// try await rateLimiter.checkLimit(
///     tenantId: context.tenantId,
///     operation: .query
/// )
///
/// // Record usage after successful operation
/// await rateLimiter.recordUsage(
///     tenantId: context.tenantId,
///     operation: .query
/// )
/// ```
public enum RateLimitOperation: String, Sendable, CaseIterable, Equatable {
    /// Query operations including search and RAG queries.
    ///
    /// These are typically the most common operations and have
    /// per-minute rate limits defined in `TenantConfiguration.queriesPerMinute`.
    case query

    /// Document ingestion operations.
    ///
    /// These have per-day limits defined in `TenantConfiguration.documentsPerDay`
    /// and are typically more expensive than queries.
    case ingest

    /// WebSocket connection establishment.
    ///
    /// Limited by `TenantConfiguration.maxConcurrentWebSockets`.
    /// Unlike other operations, this tracks concurrent connections
    /// rather than request rate.
    case websocket

    /// Batch embedding operations.
    ///
    /// These may have separate rate limits due to the higher
    /// computational cost of generating multiple embeddings.
    case batchEmbed

    /// Retrieval operations for fetching similar documents.
    ///
    /// These are typically counted together with queries but
    /// may have separate limits for internal retrieval operations.
    case retrieve
}

// MARK: - TenantResolver

/// A protocol for resolving tenant context from authentication credentials.
///
/// Implement this protocol to support different authentication mechanisms
/// such as API keys, JWT tokens, or OAuth. The resolver validates credentials
/// and returns the corresponding tenant context.
///
/// ## Thread Safety
/// Implementations must be `Sendable` and safe to use from any actor context.
///
/// ## Example Implementation
/// ```swift
/// actor APIKeyTenantResolver: TenantResolver {
///     private let storage: TenantStorage
///
///     init(storage: TenantStorage) {
///         self.storage = storage
///     }
///
///     func resolve(from authHeader: String?) async throws -> TenantContext {
///         guard let header = authHeader,
///               header.hasPrefix("Bearer ") else {
///             throw AuthError.missingCredentials
///         }
///
///         let apiKey = String(header.dropFirst(7))
///         return try await resolve(from: apiKey)
///     }
///
///     func resolve(from apiKey: String) async throws -> TenantContext {
///         guard let context = try await storage.findByApiKey(apiKey) else {
///             throw AuthError.invalidApiKey
///         }
///         return context
///     }
/// }
/// ```
public protocol TenantResolver: Sendable {

    /// Resolves a tenant context from an HTTP Authorization header.
    ///
    /// This method extracts and validates credentials from the Authorization
    /// header, then returns the corresponding tenant context.
    ///
    /// - Parameter authHeader: The value of the HTTP Authorization header,
    ///   or `nil` if no header was provided.
    /// - Returns: The resolved tenant context.
    /// - Throws: An error if the credentials are missing, invalid, or expired.
    ///
    /// ## Supported Header Formats
    /// Implementations typically support:
    /// - `Bearer <api_key>` - API key authentication
    /// - `Bearer <jwt_token>` - JWT token authentication
    func resolve(from authHeader: String?) async throws -> TenantContext

    /// Resolves a tenant context from an API key.
    ///
    /// This method validates the API key and returns the corresponding
    /// tenant context. Use this for direct API key authentication
    /// without an Authorization header.
    ///
    /// - Parameter apiKey: The API key to validate.
    /// - Returns: The resolved tenant context.
    /// - Throws: An error if the API key is invalid or expired.
    func resolve(from apiKey: String) async throws -> TenantContext
}

// MARK: - TenantRateLimitPolicy

/// A protocol for enforcing rate limits on tenant operations.
///
/// Implement this protocol to provide rate limiting with different
/// backends such as Redis, in-memory stores, or distributed systems.
///
/// ## Thread Safety
/// Implementations must be `Sendable` and safe to use from any actor context.
/// Rate limit checks should be atomic to prevent race conditions.
///
/// ## Example Implementation
/// ```swift
/// actor InMemoryRateLimiter: TenantRateLimitPolicy {
///     private var usage: [String: [RateLimitOperation: Int]] = [:]
///     private var lastReset: Date = Date()
///
///     func checkLimit(
///         tenantId: String,
///         operation: RateLimitOperation
///     ) async throws {
///         let current = usage[tenantId]?[operation] ?? 0
///         let limit = getLimit(for: tenantId, operation: operation)
///
///         if current >= limit {
///             throw RateLimitError.exceeded(
///                 operation: operation,
///                 limit: limit,
///                 resetAt: nextResetTime()
///             )
///         }
///     }
///
///     func recordUsage(
///         tenantId: String,
///         operation: RateLimitOperation
///     ) async {
///         usage[tenantId, default: [:]][operation, default: 0] += 1
///     }
///
///     func getRemainingQuota(
///         tenantId: String,
///         operation: RateLimitOperation
///     ) async -> Int? {
///         let current = usage[tenantId]?[operation] ?? 0
///         let limit = getLimit(for: tenantId, operation: operation)
///         return max(0, limit - current)
///     }
/// }
/// ```
public protocol TenantRateLimitPolicy: Sendable {

    /// Checks if an operation is allowed under current rate limits.
    ///
    /// Call this method before performing a rate-limited operation.
    /// If the limit is exceeded, this method throws an error.
    ///
    /// - Parameters:
    ///   - tenantId: The unique identifier of the tenant.
    ///   - operation: The type of operation being performed.
    /// - Throws: An error if the rate limit has been exceeded.
    ///   The error should include information about when the limit resets.
    ///
    /// ## Example
    /// ```swift
    /// do {
    ///     try await rateLimiter.checkLimit(
    ///         tenantId: context.tenantId,
    ///         operation: .query
    ///     )
    ///     // Proceed with query
    /// } catch let error as RateLimitError {
    ///     // Handle rate limit exceeded
    /// }
    /// ```
    func checkLimit(tenantId: String, operation: RateLimitOperation) async throws

    /// Records that an operation was performed by a tenant.
    ///
    /// Call this method after successfully completing a rate-limited operation.
    /// This increments the usage counter for the specified operation type.
    ///
    /// - Parameters:
    ///   - tenantId: The unique identifier of the tenant.
    ///   - operation: The type of operation that was performed.
    ///
    /// ## Example
    /// ```swift
    /// try await rateLimiter.checkLimit(tenantId: tenantId, operation: .query)
    /// let result = try await performQuery(query)
    /// await rateLimiter.recordUsage(tenantId: tenantId, operation: .query)
    /// return result
    /// ```
    func recordUsage(tenantId: String, operation: RateLimitOperation) async

    /// Returns the remaining quota for a specific operation.
    ///
    /// Use this method to provide clients with information about their
    /// remaining rate limit allocation, typically in response headers.
    ///
    /// - Parameters:
    ///   - tenantId: The unique identifier of the tenant.
    ///   - operation: The type of operation to check.
    /// - Returns: The number of operations remaining before the limit is reached,
    ///   or `nil` if the quota information is unavailable.
    ///
    /// ## Example
    /// ```swift
    /// if let remaining = await rateLimiter.getRemainingQuota(
    ///     tenantId: context.tenantId,
    ///     operation: .query
    /// ) {
    ///     response.headers.add(name: "X-RateLimit-Remaining", value: "\(remaining)")
    /// }
    /// ```
    func getRemainingQuota(tenantId: String, operation: RateLimitOperation) async -> Int?
}

// MARK: - TenantStorage

/// A protocol for persisting and retrieving tenant data.
///
/// Implement this protocol to store tenant information in different
/// backends such as PostgreSQL, Redis, or in-memory stores.
///
/// ## Thread Safety
/// Implementations must be `Sendable` and safe to use from any actor context.
/// Storage operations should be atomic where appropriate.
///
/// ## Example Implementation
/// ```swift
/// actor PostgresTenantStorage: TenantStorage {
///     private let database: Database
///
///     init(database: Database) {
///         self.database = database
///     }
///
///     func find(tenantId: String) async throws -> TenantContext? {
///         let row = try await database.query(
///             "SELECT * FROM tenants WHERE id = $1",
///             [tenantId]
///         ).first
///
///         return row.map { TenantContext(from: $0) }
///     }
///
///     func findByApiKey(_ apiKey: String) async throws -> TenantContext? {
///         let hashedKey = hash(apiKey)
///         let row = try await database.query(
///             "SELECT t.* FROM tenants t JOIN api_keys a ON t.id = a.tenant_id WHERE a.key_hash = $1",
///             [hashedKey]
///         ).first
///
///         return row.map { TenantContext(from: $0) }
///     }
///
///     func save(_ tenant: TenantContext) async throws {
///         try await database.execute(
///             """
///             INSERT INTO tenants (id, organization_id, tier, config, created_at)
///             VALUES ($1, $2, $3, $4, $5)
///             ON CONFLICT (id) DO UPDATE SET
///                 organization_id = $2, tier = $3, config = $4
///             """,
///             [tenant.tenantId, tenant.organizationId, tenant.tier.rawValue,
///              try JSONEncoder().encode(tenant.config), tenant.createdAt]
///         )
///     }
///
///     func delete(tenantId: String) async throws {
///         try await database.execute(
///             "DELETE FROM tenants WHERE id = $1",
///             [tenantId]
///         )
///     }
/// }
/// ```
public protocol TenantStorage: Sendable {

    /// Finds a tenant by their unique identifier.
    ///
    /// - Parameter tenantId: The unique identifier of the tenant to find.
    /// - Returns: The tenant context if found, or `nil` if no tenant exists
    ///   with the given identifier.
    /// - Throws: An error if the storage operation fails.
    ///
    /// ## Example
    /// ```swift
    /// if let tenant = try await storage.find(tenantId: "tenant_123") {
    ///     print("Found tenant: \(tenant.tier)")
    /// } else {
    ///     print("Tenant not found")
    /// }
    /// ```
    func find(tenantId: String) async throws -> TenantContext?

    /// Finds a tenant by their API key.
    ///
    /// This method is typically used during authentication to resolve
    /// tenant context from provided credentials.
    ///
    /// - Parameter apiKey: The API key to look up.
    /// - Returns: The tenant context if found, or `nil` if no tenant exists
    ///   with the given API key.
    /// - Throws: An error if the storage operation fails.
    ///
    /// ## Security Note
    /// Implementations should store API keys as secure hashes, not plaintext.
    /// This method should hash the provided key before comparison.
    ///
    /// ## Example
    /// ```swift
    /// guard let tenant = try await storage.findByApiKey(apiKey) else {
    ///     throw AuthError.invalidApiKey
    /// }
    /// ```
    func findByApiKey(_ apiKey: String) async throws -> TenantContext?

    /// Saves or updates a tenant context.
    ///
    /// If a tenant with the same `tenantId` already exists, it is updated.
    /// Otherwise, a new tenant record is created.
    ///
    /// - Parameter tenant: The tenant context to save.
    /// - Throws: An error if the storage operation fails.
    ///
    /// ## Example
    /// ```swift
    /// let newTenant = TenantContext(
    ///     tenantId: "tenant_456",
    ///     tier: .professional
    /// )
    /// try await storage.save(newTenant)
    /// ```
    func save(_ tenant: TenantContext) async throws

    /// Deletes a tenant by their unique identifier.
    ///
    /// This method removes the tenant and all associated data.
    /// If no tenant exists with the given identifier, this method
    /// completes successfully without error.
    ///
    /// - Parameter tenantId: The unique identifier of the tenant to delete.
    /// - Throws: An error if the storage operation fails.
    ///
    /// ## Warning
    /// This is a destructive operation. Implementations should consider
    /// implementing soft deletes or requiring additional confirmation
    /// for production environments.
    ///
    /// ## Example
    /// ```swift
    /// try await storage.delete(tenantId: "tenant_789")
    /// ```
    func delete(tenantId: String) async throws
}
