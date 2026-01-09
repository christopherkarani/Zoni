#if HUMMINGBIRD
// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// ZoniHummingbird.swift - Hummingbird framework integration for Zoni RAG.

import Hummingbird
import HummingbirdAuth

/// ZoniHummingbird provides Hummingbird framework integration for the Zoni RAG system.
///
/// This module includes:
/// - Route handlers for RAG operations (query, ingest, jobs)
/// - WebSocket support for streaming responses
/// - Middleware for authentication and rate limiting
/// - Request context extensions
///
/// ## Quick Start
///
/// ```swift
/// import Hummingbird
/// import ZoniHummingbird
///
/// // Create services
/// let services = ZoniServices(
///     queryEngine: engine,
///     tenantManager: manager,
///     rateLimiter: TenantRateLimiter(),
///     jobQueue: InMemoryJobQueue()
/// )
///
/// // Create router with RAG context
/// let router = Router(context: RAGRequestContext.self)
///
/// // Add all Zoni routes
/// addZoniRoutes(to: router, services: services)
///
/// // Create and run application
/// let app = Application(
///     router: router,
///     configuration: .init(address: .hostname("localhost", port: 8080))
/// )
/// try await app.run()
/// ```
///
/// ## Available Endpoints
///
/// - `GET /api/v1/health` - Health check (no auth)
/// - `GET /api/v1/health/ready` - Readiness check (no auth)
/// - `POST /api/v1/query` - Execute RAG query
/// - `GET /api/v1/query/retrieve` - Search documents
/// - `POST /api/v1/documents` - Ingest documents
/// - `POST /api/v1/documents/batch` - Batch ingestion
/// - `DELETE /api/v1/documents/:id` - Delete document
/// - `GET /api/v1/jobs` - List jobs
/// - `GET /api/v1/jobs/:id` - Get job status
/// - `DELETE /api/v1/jobs/:id` - Cancel job
public enum ZoniHummingbird {
    /// The current version of ZoniHummingbird.
    public static let version = "0.1.0"
}

// MARK: - Router Helper

/// Adds all Zoni routes to a router.
///
/// This convenience function registers all Zoni endpoints on the provided router,
/// including query, ingestion, job management, and health check routes.
///
/// ## Route Structure
///
/// Routes are organized under the specified path prefix (default: `api/v1`):
///
/// ```
/// /api/v1/
///     health           - Basic health check
///     health/ready     - Readiness check
///     query            - POST: Execute RAG query
///     query/retrieve   - GET: Search documents
///     documents        - POST: Ingest documents
///     documents/batch  - POST: Batch ingestion
///     documents/:id    - DELETE: Remove document
///     jobs             - GET: List jobs
///     jobs/:id         - GET: Job status, DELETE: Cancel
/// ```
///
/// ## Authentication
///
/// Health endpoints do not require authentication. All other endpoints require
/// a valid tenant context resolved from the Authorization header.
///
/// - Parameters:
///   - router: The router to add routes to.
///   - services: The Zoni services container with all dependencies.
///   - pathPrefix: The URL path prefix for all routes. Defaults to `"api/v1"`.
///
/// ## Example
/// ```swift
/// let router = Router(context: RAGRequestContext.self)
/// let services = ZoniServices(from: config)
///
/// // Use default path prefix
/// addZoniRoutes(to: router, services: services)
///
/// // Use custom path prefix
/// addZoniRoutes(to: router, services: services, pathPrefix: "v2/api")
/// ```
public func addZoniRoutes<Context: AuthRequestContext>(
    to router: Router<Context>,
    services: ZoniServices,
    pathPrefix: String = "api/v1"
) where Context.Identity == TenantContext {
    let api = router.group(RouterPath(pathPrefix))

    // Add all route groups
    addQueryRoutes(to: api, services: services)
    addIngestRoutes(to: api, services: services)
    addJobRoutes(to: api, services: services)
    addHealthRoutes(to: api)
}

// Re-export ZoniServer types for convenience
@_exported import Hummingbird

#endif
