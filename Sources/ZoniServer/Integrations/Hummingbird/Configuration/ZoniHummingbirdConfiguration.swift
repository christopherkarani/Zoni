#if HUMMINGBIRD
// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// ZoniHummingbirdConfiguration.swift - Configuration for ZoniHummingbird integration.
//
// This file provides configuration and dependency injection for the Hummingbird
// integration, including query engine, tenant management, rate limiting, and job queue.

import Hummingbird
import Zoni

// MARK: - ZoniHummingbirdConfiguration

/// Configuration for ZoniHummingbird integration.
///
/// `ZoniHummingbirdConfiguration` encapsulates all the services needed to run
/// the Zoni RAG server with Hummingbird, including the query engine, tenant
/// management, rate limiting, and background job processing.
///
/// ## Example Usage
///
/// ```swift
/// let config = ZoniHummingbirdConfiguration(
///     queryEngine: queryEngine,
///     tenantManager: tenantManager,
///     rateLimiter: TenantRateLimiter(),
///     jobQueue: InMemoryJobQueue()
/// )
///
/// let services = ZoniServices(from: config)
/// addZoniRoutes(to: router, services: services)
/// ```
public struct ZoniHummingbirdConfiguration: Sendable {

    // MARK: - Properties

    /// The query engine for RAG operations.
    ///
    /// Handles document retrieval and response generation for user queries.
    public let queryEngine: QueryEngine

    /// The tenant manager for authentication and authorization.
    ///
    /// Resolves tenant context from API keys and JWT tokens.
    public let tenantManager: TenantManager

    /// The rate limiter for enforcing per-tenant rate limits.
    ///
    /// Uses the token bucket algorithm to control request rates.
    public let rateLimiter: TenantRateLimiter

    /// The job queue backend for asynchronous operations.
    ///
    /// Manages background jobs for batch ingestion and other long-running tasks.
    public let jobQueue: any JobQueueBackend

    // MARK: - Initialization

    /// Creates a new ZoniHummingbird configuration.
    ///
    /// - Parameters:
    ///   - queryEngine: The query engine for RAG operations.
    ///   - tenantManager: The tenant manager for authentication.
    ///   - rateLimiter: The rate limiter for per-tenant rate limiting.
    ///                  Defaults to a new `TenantRateLimiter()` with standard settings.
    ///   - jobQueue: The job queue backend for async operations.
    ///               Defaults to an `InMemoryJobQueue()`.
    ///
    /// ## Example
    /// ```swift
    /// // Minimal initialization
    /// let config = ZoniHummingbirdConfiguration(
    ///     queryEngine: engine,
    ///     tenantManager: manager
    /// )
    ///
    /// // Full customization
    /// let config = ZoniHummingbirdConfiguration(
    ///     queryEngine: engine,
    ///     tenantManager: manager,
    ///     rateLimiter: TenantRateLimiter(defaultConfig: .forTier(.professional)),
    ///     jobQueue: RedisJobQueue(connection: redisConn)
    /// )
    /// ```
    public init(
        queryEngine: QueryEngine,
        tenantManager: TenantManager,
        rateLimiter: TenantRateLimiter = TenantRateLimiter(),
        jobQueue: any JobQueueBackend = InMemoryJobQueue()
    ) {
        self.queryEngine = queryEngine
        self.tenantManager = tenantManager
        self.rateLimiter = rateLimiter
        self.jobQueue = jobQueue
    }
}

// MARK: - ZoniServices

/// Services container for dependency injection in route handlers.
///
/// `ZoniServices` provides a convenient container for all services needed by
/// route handlers, making it easy to pass dependencies to route registration
/// functions.
///
/// ## Thread Safety
///
/// `ZoniServices` is `Sendable` and can be safely shared across concurrent
/// contexts. All contained services are also `Sendable`.
///
/// ## Example Usage
///
/// ```swift
/// let config = ZoniHummingbirdConfiguration(
///     queryEngine: engine,
///     tenantManager: manager
/// )
/// let services = ZoniServices(from: config)
///
/// // Use in route registration
/// addQueryRoutes(to: router.group("api/v1"), services: services)
/// ```
public struct ZoniServices: Sendable {

    // MARK: - Properties

    /// The query engine for RAG operations.
    public let queryEngine: QueryEngine

    /// The tenant manager for authentication and authorization.
    public let tenantManager: TenantManager

    /// The rate limiter for enforcing per-tenant rate limits.
    public let rateLimiter: TenantRateLimiter

    /// The job queue backend for asynchronous operations.
    public let jobQueue: any JobQueueBackend

    // MARK: - Initialization

    /// Creates a new services container from a configuration.
    ///
    /// - Parameter config: The configuration to extract services from.
    public init(from config: ZoniHummingbirdConfiguration) {
        self.queryEngine = config.queryEngine
        self.tenantManager = config.tenantManager
        self.rateLimiter = config.rateLimiter
        self.jobQueue = config.jobQueue
    }

    /// Creates a new services container with explicit dependencies.
    ///
    /// - Parameters:
    ///   - queryEngine: The query engine for RAG operations.
    ///   - tenantManager: The tenant manager for authentication.
    ///   - rateLimiter: The rate limiter for per-tenant rate limiting.
    ///   - jobQueue: The job queue backend for async operations.
    public init(
        queryEngine: QueryEngine,
        tenantManager: TenantManager,
        rateLimiter: TenantRateLimiter,
        jobQueue: any JobQueueBackend
    ) {
        self.queryEngine = queryEngine
        self.tenantManager = tenantManager
        self.rateLimiter = rateLimiter
        self.jobQueue = jobQueue
    }
}

#endif
