#if HUMMINGBIRD
// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RateLimitMiddleware.swift - Middleware for per-tenant rate limiting.
//
// This file provides middleware that enforces rate limits based on tenant
// configuration and operation type.

import Hummingbird
import HummingbirdAuth

// MARK: - RateLimitMiddleware

/// Middleware that enforces rate limits per tenant.
///
/// `RateLimitMiddleware` checks rate limits before processing requests and
/// records usage after successful responses. It uses the `TenantRateLimiter`
/// which implements the token bucket algorithm for smooth rate limiting.
///
/// ## Rate Limit Behavior
///
/// - Before the request: Checks if the tenant has available quota
/// - If limit exceeded: Returns HTTP 429 Too Many Requests
/// - After successful response: Records usage against the tenant's quota
///
/// ## Usage
///
/// Apply this middleware after `TenantMiddleware` to protected routes:
///
/// ```swift
/// let query = api.group("query")
///     .add(middleware: TenantMiddleware(tenantManager: manager))
///     .add(middleware: RateLimitMiddleware(rateLimiter: limiter, operation: .query))
///
/// query.post { request, context -> QueryResponse in
///     // Rate limit already checked
/// }
/// ```
///
/// ## Thread Safety
///
/// `RateLimitMiddleware` is `Sendable` and can be safely shared across concurrent
/// contexts. The `TenantRateLimiter` is an actor that provides thread-safe
/// rate limit enforcement.
public struct RateLimitMiddleware<Context: AuthRequestContext>: RouterMiddleware
where Context.Identity == TenantContext {

    // MARK: - Properties

    /// The rate limiter used to enforce limits.
    let rateLimiter: TenantRateLimiter

    /// The operation type for rate limiting purposes.
    let operation: RateLimitOperation

    // MARK: - Initialization

    /// Creates a new rate limit middleware.
    ///
    /// - Parameters:
    ///   - rateLimiter: The rate limiter to use for enforcement.
    ///   - operation: The type of operation to track for rate limiting.
    ///
    /// ## Example
    /// ```swift
    /// // For query endpoints
    /// let queryLimit = RateLimitMiddleware<RAGRequestContext>(
    ///     rateLimiter: rateLimiter,
    ///     operation: .query
    /// )
    ///
    /// // For ingestion endpoints
    /// let ingestLimit = RateLimitMiddleware<RAGRequestContext>(
    ///     rateLimiter: rateLimiter,
    ///     operation: .ingest
    /// )
    /// ```
    public init(rateLimiter: TenantRateLimiter, operation: RateLimitOperation) {
        self.rateLimiter = rateLimiter
        self.operation = operation
    }

    // MARK: - RouterMiddleware Protocol

    /// Handles the request by checking and recording rate limits.
    ///
    /// This method:
    /// 1. Checks if the tenant has available quota for the operation
    /// 2. If quota is available, passes the request to the next handler
    /// 3. After a successful response, records the usage
    ///
    /// If the tenant is not authenticated (no identity), the request is passed
    /// through without rate limiting. This allows the middleware to be used
    /// on routes where authentication is optional.
    ///
    /// - Parameters:
    ///   - request: The incoming HTTP request.
    ///   - context: The request context containing tenant information.
    ///   - next: The next handler in the middleware chain.
    /// - Returns: The HTTP response from the downstream handler.
    /// - Throws: `ZoniServerError.rateLimited` if the rate limit is exceeded.
    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        // Skip rate limiting if no tenant is authenticated
        guard let tenant = context.identity else {
            return try await next(request, context)
        }

        // Check rate limit before processing
        try await rateLimiter.checkLimit(tenantId: tenant.tenantId, operation: operation)

        // Process the request
        let response = try await next(request, context)

        // Record usage after successful response
        await rateLimiter.recordUsage(tenantId: tenant.tenantId, operation: operation)

        return response
    }
}

#endif
