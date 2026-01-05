// ZoniVapor - Vapor framework integration for Zoni RAG
//
// RateLimitMiddleware.swift - Middleware that enforces rate limits per tenant.
//
// This file provides middleware for enforcing rate limits on operations
// using the token bucket algorithm for smooth rate limiting.

import Vapor
import ZoniServer

// MARK: - RateLimitMiddleware

/// Middleware that enforces rate limits per tenant.
///
/// `RateLimitMiddleware` checks and records rate limit usage for each request
/// based on the operation type. It uses the tenant's rate limiter configuration
/// to determine allowed request rates.
///
/// ## Rate Limiting Algorithm
///
/// Uses the token bucket algorithm which:
/// - Allows short bursts of traffic up to the bucket capacity
/// - Maintains a steady average rate over time
/// - Provides smooth rate limiting without abrupt cutoffs
///
/// ## Example Usage
///
/// ```swift
/// // Apply rate limiting to query routes
/// let queryRoutes = routes
///     .grouped(TenantMiddleware())
///     .grouped(RateLimitMiddleware(operation: .query))
///
/// queryRoutes.post("query") { req in
///     // Handler is only called if rate limit allows
/// }
/// ```
///
/// ## Response Headers
///
/// On successful requests, rate limit headers are added:
/// - `X-RateLimit-Remaining`: Number of requests remaining in the window
///
/// On rate limit exceeded, a 429 response includes:
/// - `Retry-After`: Seconds until the rate limit resets
///
/// ## Thread Safety
///
/// The middleware is `Sendable` and safe for concurrent use.
/// Rate limit checks are performed atomically via the rate limiter actor.
public struct RateLimitMiddleware: AsyncMiddleware {

    // MARK: - Properties

    /// The type of operation being rate limited.
    let operation: RateLimitOperation

    // MARK: - Initialization

    /// Creates a new rate limit middleware for the specified operation.
    ///
    /// - Parameter operation: The type of operation to rate limit.
    ///
    /// ## Example
    /// ```swift
    /// let queryLimiter = RateLimitMiddleware(operation: .query)
    /// let ingestLimiter = RateLimitMiddleware(operation: .ingest)
    /// ```
    public init(operation: RateLimitOperation) {
        self.operation = operation
    }

    // MARK: - AsyncMiddleware Protocol

    /// Processes the request by checking and recording rate limits.
    ///
    /// This method:
    /// 1. Checks if the tenant has been resolved (skips if not)
    /// 2. Verifies the operation is within rate limits
    /// 3. Passes the request to the next handler
    /// 4. Records usage after a successful response
    ///
    /// - Parameters:
    ///   - request: The incoming HTTP request.
    ///   - next: The next responder in the middleware chain.
    /// - Returns: The response from downstream handlers.
    /// - Throws: `Abort(.tooManyRequests)` if the rate limit is exceeded.
    public func respond(
        to request: Request,
        chainingTo next: any AsyncResponder
    ) async throws -> Response {
        // If no tenant is resolved, skip rate limiting
        // This allows unauthenticated endpoints to pass through
        guard let tenant = request.tenantOptional else {
            return try await next.respond(to: request)
        }

        let rateLimiter = request.application.zoni.rateLimiter

        // Check if the operation is within rate limits
        do {
            try await rateLimiter.checkLimit(
                tenantId: tenant.tenantId,
                operation: operation
            )
        } catch let error as ZoniServerError {
            // Convert rate limit error to Vapor Abort
            var headers = HTTPHeaders()

            // Add Retry-After header for rate limit errors
            if case .rateLimited(_, let retryAfter) = error, let duration = retryAfter {
                let seconds = Int(duration.components.seconds)
                headers.add(name: .retryAfter, value: "\(max(1, seconds))")
            }

            throw Abort(
                HTTPResponseStatus(statusCode: error.httpStatusCode),
                headers: headers,
                reason: error.errorDescription
            )
        }

        // Execute the request
        let response = try await next.respond(to: request)

        // Record usage after successful response
        await rateLimiter.recordUsage(
            tenantId: tenant.tenantId,
            operation: operation
        )

        // Add rate limit headers to response
        if let remaining = await rateLimiter.getRemainingQuota(
            tenantId: tenant.tenantId,
            operation: operation
        ) {
            response.headers.add(name: "X-RateLimit-Remaining", value: "\(remaining)")
        }

        return response
    }
}
