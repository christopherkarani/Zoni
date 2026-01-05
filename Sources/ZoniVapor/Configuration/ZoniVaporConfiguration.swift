// ZoniVapor - Vapor framework integration for Zoni RAG
//
// ZoniVaporConfiguration.swift - Configuration for ZoniVapor integration.
//
// This file defines the configuration structure and Vapor Application extensions
// for integrating Zoni RAG services with the Vapor web framework.

import Vapor
import ZoniServer
import Zoni

// MARK: - ZoniVaporConfiguration

/// Configuration for ZoniVapor integration.
///
/// `ZoniVaporConfiguration` holds all the services needed for the Zoni RAG system
/// to operate within a Vapor application, including the query engine, tenant management,
/// rate limiting, and background job processing.
///
/// ## Example Usage
///
/// ```swift
/// let config = ZoniVaporConfiguration(
///     queryEngine: engine,
///     tenantManager: manager,
///     rateLimiter: TenantRateLimiter(),
///     jobQueue: InMemoryJobQueue()
/// )
/// app.configureZoni(config)
/// ```
///
/// ## Thread Safety
///
/// `ZoniVaporConfiguration` is `Sendable` and can be safely shared across
/// actor boundaries and concurrent request handlers.
public struct ZoniVaporConfiguration: Sendable {

    // MARK: - Properties

    /// The query engine for executing RAG queries.
    ///
    /// This is the main orchestrator for retrieval-augmented generation,
    /// coordinating retrieval, context building, and response synthesis.
    public let queryEngine: QueryEngine

    /// The tenant manager for resolving tenant context from authentication.
    ///
    /// Handles API key and JWT token validation, caching resolved tenants
    /// for performance optimization.
    public let tenantManager: TenantManager

    /// The rate limiter for enforcing per-tenant rate limits.
    ///
    /// Uses the token bucket algorithm to allow burst traffic while
    /// maintaining average rate limits based on tenant tier.
    public let rateLimiter: TenantRateLimiter

    /// The job queue backend for asynchronous operations.
    ///
    /// Stores and manages background jobs such as document ingestion
    /// and batch embedding operations.
    public let jobQueue: any JobQueueBackend

    /// Optional job executor for processing background jobs.
    ///
    /// When provided, the executor polls the job queue and processes
    /// jobs concurrently. If `nil`, jobs must be processed externally.
    public let jobExecutor: JobExecutor?

    // MARK: - Initialization

    /// Creates a new ZoniVapor configuration.
    ///
    /// - Parameters:
    ///   - queryEngine: The query engine for RAG operations.
    ///   - tenantManager: The tenant manager for authentication.
    ///   - rateLimiter: The rate limiter for enforcing limits.
    ///                  Defaults to a new `TenantRateLimiter()`.
    ///   - jobQueue: The job queue backend.
    ///               Defaults to `InMemoryJobQueue()`.
    ///   - jobExecutor: Optional job executor for background processing.
    ///                  Defaults to `nil`.
    ///
    /// ## Example
    /// ```swift
    /// // Minimal configuration
    /// let config = ZoniVaporConfiguration(
    ///     queryEngine: engine,
    ///     tenantManager: manager
    /// )
    ///
    /// // Full configuration with custom job queue
    /// let config = ZoniVaporConfiguration(
    ///     queryEngine: engine,
    ///     tenantManager: manager,
    ///     rateLimiter: customRateLimiter,
    ///     jobQueue: RedisJobQueue(client: redis),
    ///     jobExecutor: executor
    /// )
    /// ```
    public init(
        queryEngine: QueryEngine,
        tenantManager: TenantManager,
        rateLimiter: TenantRateLimiter = TenantRateLimiter(),
        jobQueue: any JobQueueBackend = InMemoryJobQueue(),
        jobExecutor: JobExecutor? = nil
    ) {
        self.queryEngine = queryEngine
        self.tenantManager = tenantManager
        self.rateLimiter = rateLimiter
        self.jobQueue = jobQueue
        self.jobExecutor = jobExecutor
    }
}

// MARK: - Application Extension

extension Application {

    // MARK: - Storage Key

    /// Storage key for the Zoni configuration in the Vapor application.
    public struct ZoniKey: StorageKey {
        public typealias Value = ZoniVaporConfiguration
    }

    // MARK: - Zoni Property

    /// The Zoni configuration for this application.
    ///
    /// Accessing this property before calling `configureZoni(_:)` will
    /// cause a fatal error. Always configure Zoni during application setup.
    ///
    /// ## Example
    /// ```swift
    /// // Access in a route handler
    /// func getQuery(req: Request) async throws -> QueryResponse {
    ///     let engine = req.application.zoni.queryEngine
    ///     // Use engine...
    /// }
    /// ```
    public var zoni: ZoniVaporConfiguration {
        get {
            guard let config = storage[ZoniKey.self] else {
                fatalError("Zoni not configured. Call app.configureZoni(_:) during setup.")
            }
            return config
        }
        set {
            storage[ZoniKey.self] = newValue
        }
    }

    // MARK: - Configuration Methods

    /// Configures Zoni with the given configuration.
    ///
    /// Call this method during application setup to initialize all Zoni services.
    /// This must be called before registering Zoni routes.
    ///
    /// - Parameter config: The Zoni configuration containing all required services.
    ///
    /// ## Example
    /// ```swift
    /// func configure(_ app: Application) throws {
    ///     let config = ZoniVaporConfiguration(
    ///         queryEngine: engine,
    ///         tenantManager: manager
    ///     )
    ///     app.configureZoni(config)
    ///     try app.registerZoniRoutes()
    /// }
    /// ```
    public func configureZoni(_ config: ZoniVaporConfiguration) {
        self.zoni = config
    }

    /// Registers all Zoni routes at the specified path prefix.
    ///
    /// This method registers the following route groups:
    /// - `/api/v1/query` - RAG query endpoints
    /// - `/api/v1/documents` - Document ingestion endpoints
    /// - `/api/v1/indices` - Index management endpoints
    /// - `/api/v1/jobs` - Background job management endpoints
    /// - `/api/v1/health` - Health check endpoints
    ///
    /// - Parameter path: The path prefix for all Zoni routes.
    ///                   Defaults to `"api"`.
    /// - Throws: An error if route registration fails.
    ///
    /// ## Example
    /// ```swift
    /// // Register at default path (/api/v1/...)
    /// try app.registerZoniRoutes()
    ///
    /// // Register at custom path (/rag/v1/...)
    /// try app.registerZoniRoutes(at: "rag")
    /// ```
    public func registerZoniRoutes(at path: PathComponent = "api") throws {
        let controllers: [RouteCollection] = [
            QueryController(),
            IngestController(),
            IndexController(),
            JobController(),
            HealthController()
        ]

        let versionedRoutes = routes.grouped(path, "v1")

        for controller in controllers {
            try versionedRoutes.register(collection: controller)
        }
    }
}
