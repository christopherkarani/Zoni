#if HUMMINGBIRD
// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// HealthRoutes.swift - HTTP routes for health check endpoints.
//
// This file provides route handlers for health and readiness checks
// through the Hummingbird HTTP framework.

import Foundation
import Hummingbird

// MARK: - Health Routes

/// Registers health check routes on a router group.
///
/// This function adds the following endpoints:
/// - `GET /health` - Basic health check (no authentication required)
/// - `GET /health/ready` - Readiness check with component status
///
/// These endpoints do not require authentication and can be used by
/// load balancers, orchestrators, and monitoring systems.
///
/// ## Example Usage
///
/// ```swift
/// let api = router.group("api/v1")
/// addHealthRoutes(to: api)
/// ```
///
/// ## Endpoints
///
/// ### GET /health
///
/// Returns basic health information about the server.
///
/// Response:
/// ```json
/// {
///     "status": "healthy",
///     "version": "0.1.0",
///     "timestamp": "2024-01-15T10:30:00Z"
/// }
/// ```
///
/// ### GET /health/ready
///
/// Returns readiness status with individual component checks.
/// Used by Kubernetes and other orchestrators to determine if the
/// service is ready to accept traffic.
///
/// Response:
/// ```json
/// {
///     "ready": true,
///     "checks": {
///         "database": true,
///         "cache": true
///     }
/// }
/// ```
///
/// - Parameter group: The router group to add routes to.
public func addHealthRoutes<Context: RequestContext>(
    to group: RouterGroup<Context>
) {
    // GET /health - Basic health check
    group.get("health") { _, _ -> HealthResponse in
        HealthResponse(
            status: "healthy",
            version: ZoniHummingbird.version,
            timestamp: Date()
        )
    }

    // GET /health/ready - Readiness check
    group.get("health/ready") { _, _ -> ReadinessResponse in
        // TODO: Implement actual component health checks
        // For now, return healthy status
        ReadinessResponse(
            ready: true,
            checks: [
                "database": true,
                "cache": true
            ]
        )
    }
}

#endif
