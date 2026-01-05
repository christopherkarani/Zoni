// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// ZoniVapor.swift - Vapor framework integration for Zoni RAG.
//
// This file serves as the main entry point for the ZoniVapor module,
// providing Vapor web framework integration for the Zoni RAG system.

@_exported import Vapor
@_exported import ZoniServer

// MARK: - ZoniVapor

/// ZoniVapor provides Vapor framework integration for the Zoni RAG system.
///
/// This module includes:
/// - HTTP REST controllers for RAG operations
/// - WebSocket support for streaming responses
/// - Middleware for authentication and rate limiting
/// - Application configuration helpers
///
/// ## Quick Start
///
/// ```swift
/// import Vapor
/// import ZoniVapor
///
/// func configure(_ app: Application) throws {
///     // Create Zoni configuration
///     let config = ZoniVaporConfiguration(
///         queryEngine: engine,
///         tenantManager: manager
///     )
///
///     // Configure Zoni services
///     app.configureZoni(config)
///
///     // Register RAG routes
///     try app.registerZoniRoutes()
/// }
/// ```
///
/// ## Available Endpoints
///
/// After registration, the following endpoints are available:
///
/// ### Query Endpoints
/// - `POST /api/v1/query` - Execute a RAG query
/// - `GET /api/v1/query/retrieve` - Search without generation
///
/// ### Document Endpoints
/// - `POST /api/v1/documents` - Ingest documents
/// - `POST /api/v1/documents/batch` - Batch ingest (async)
/// - `DELETE /api/v1/documents/:id` - Delete a document
///
/// ### Index Endpoints
/// - `GET /api/v1/indices` - List indices
/// - `POST /api/v1/indices` - Create an index
/// - `GET /api/v1/indices/:name` - Get index info
/// - `DELETE /api/v1/indices/:name` - Delete an index
///
/// ### Job Endpoints
/// - `GET /api/v1/jobs` - List jobs
/// - `GET /api/v1/jobs/:id` - Get job status
/// - `DELETE /api/v1/jobs/:id` - Cancel a job
///
/// ### Health Endpoints
/// - `GET /api/v1/health` - Basic health check
/// - `GET /api/v1/health/ready` - Readiness check
///
/// ## Multi-Tenancy
///
/// ZoniVapor supports multi-tenant deployments with:
/// - Tenant resolution from API keys or JWT tokens
/// - Per-tenant rate limiting
/// - Tenant-isolated vector store indices
///
/// ## Thread Safety
///
/// All ZoniVapor components are designed for concurrent use with
/// Swift 6 strict concurrency checking enabled.
public enum ZoniVapor {

    /// The current version of ZoniVapor.
    public static let version = "0.1.0"
}
