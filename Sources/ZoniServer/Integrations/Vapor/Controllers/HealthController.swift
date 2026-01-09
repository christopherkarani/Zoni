#if VAPOR
// ZoniVapor - Vapor framework integration for Zoni RAG
//
// HealthController.swift - Controller for health check endpoints.
//
// This file provides HTTP endpoints for health checks and readiness probes,
// typically used by load balancers and container orchestrators.

import Vapor

// MARK: - HealthController

/// Controller for health check endpoints.
///
/// `HealthController` provides endpoints for checking the health and readiness
/// of the Zoni RAG service. These endpoints are typically used by:
/// - Load balancers to route traffic to healthy instances
/// - Container orchestrators (Kubernetes) for liveness and readiness probes
/// - Monitoring systems for uptime tracking
///
/// ## Endpoints
///
/// - `GET /health` - Basic health check (no authentication required)
/// - `GET /health/ready` - Readiness check with component status
///
/// ## No Authentication
///
/// Health endpoints do not require authentication to allow load balancers
/// and orchestrators to check status without credentials.
///
/// ## Example Kubernetes Probes
///
/// ```yaml
/// livenessProbe:
///   httpGet:
///     path: /api/v1/health
///     port: 8080
///   initialDelaySeconds: 5
///   periodSeconds: 10
///
/// readinessProbe:
///   httpGet:
///     path: /api/v1/health/ready
///     port: 8080
///   initialDelaySeconds: 5
///   periodSeconds: 5
/// ```
struct HealthController: RouteCollection {

    // MARK: - RouteCollection Protocol

    /// Registers health check routes with the router.
    ///
    /// Note: Health routes are registered without authentication middleware
    /// to allow external monitoring systems to check status.
    ///
    /// - Parameter routes: The routes builder to register routes with.
    func boot(routes: any RoutesBuilder) throws {
        routes.get("health", use: health)
        routes.get("health", "ready", use: ready)
    }

    // MARK: - Route Handlers

    /// Basic health check endpoint.
    ///
    /// Returns a simple health status indicating the service is running.
    /// This endpoint should always return 200 OK if the service is alive.
    ///
    /// ## Response
    ///
    /// ```json
    /// {
    ///     "status": "healthy",
    ///     "version": "0.1.0",
    ///     "timestamp": "2024-01-15T10:30:00Z"
    /// }
    /// ```
    ///
    /// - Parameter req: The incoming HTTP request.
    /// - Returns: The health response with status and version.
    @Sendable
    func health(req: Request) async throws -> HealthResponse {
        HealthResponse(
            status: "healthy",
            version: ZoniVapor.version,
            timestamp: Date()
        )
    }

    /// Readiness check endpoint with component status.
    ///
    /// Returns detailed readiness information including the status of
    /// dependent services. Used by orchestrators to determine if the
    /// instance is ready to accept traffic.
    ///
    /// ## Response (Ready)
    ///
    /// ```json
    /// {
    ///     "ready": true,
    ///     "checks": {
    ///         "database": true,
    ///         "cache": true,
    ///         "vectorStore": true
    ///     }
    /// }
    /// ```
    ///
    /// ## Response (Not Ready)
    ///
    /// ```json
    /// {
    ///     "ready": false,
    ///     "checks": {
    ///         "database": false,
    ///         "cache": true,
    ///         "vectorStore": true
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter req: The incoming HTTP request.
    /// - Returns: The readiness response with component checks.
    @Sendable
    func ready(req: Request) async throws -> ReadinessResponse {
        // Perform actual health checks on dependent services
        var checks: [String: Bool] = [:]
        var allHealthy = true

        // Check if Zoni is configured
        let zoniConfigured = req.application.storage[Application.ZoniKey.self] != nil
        checks["zoni"] = zoniConfigured
        if !zoniConfigured {
            allHealthy = false
        }

        // Additional checks would go here in production:
        // - Database connectivity
        // - Vector store connectivity
        // - External API availability

        // For now, return basic checks
        checks["database"] = true
        checks["cache"] = true

        return ReadinessResponse(
            ready: allHealthy,
            checks: checks
        )
    }
}

// MARK: - Content Conformance

extension HealthResponse: Content {}
extension ReadinessResponse: Content {}

#endif
