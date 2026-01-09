#if HUMMINGBIRD
// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// TenantMiddleware.swift - Middleware for tenant resolution from request headers.
//
// This file provides middleware that resolves tenant context from the
// Authorization header, supporting both API key and JWT authentication.

import Hummingbird
import HummingbirdAuth

// MARK: - TenantMiddleware

/// Middleware that resolves tenant context from request headers.
///
/// `TenantMiddleware` extracts authentication credentials from the HTTP
/// Authorization header and resolves them to a `TenantContext` using the
/// provided `TenantManager`. The resolved context is stored in the request
/// context's `identity` property.
///
/// ## Authentication Methods
///
/// The middleware supports the following Authorization header formats:
/// - `Bearer <jwt_token>` - JWT token authentication
/// - `ApiKey <api_key>` - API key authentication
/// - `<api_key>` - Raw API key (no prefix)
///
/// ## Usage
///
/// Apply this middleware to route groups that require authentication:
///
/// ```swift
/// let api = router.group("api/v1")
/// let protected = api.group("protected")
///     .add(middleware: TenantMiddleware(tenantManager: manager))
///
/// protected.get("data") { request, context -> Response in
///     let tenant = try context.tenant
///     // Handle authenticated request
/// }
/// ```
///
/// ## Thread Safety
///
/// `TenantMiddleware` is `Sendable` and can be safely shared across concurrent
/// contexts. The `TenantManager` is an actor that provides thread-safe tenant
/// resolution with caching.
public struct TenantMiddleware<Context: AuthRequestContext>: RouterMiddleware
where Context.Identity == TenantContext {

    // MARK: - Properties

    /// The tenant manager used to resolve credentials to tenant context.
    let tenantManager: TenantManager

    // MARK: - Initialization

    /// Creates a new tenant middleware with the specified tenant manager.
    ///
    /// - Parameter tenantManager: The manager used to resolve tenant context
    ///   from authentication credentials.
    ///
    /// ## Example
    /// ```swift
    /// let middleware = TenantMiddleware<RAGRequestContext>(
    ///     tenantManager: tenantManager
    /// )
    /// ```
    public init(tenantManager: TenantManager) {
        self.tenantManager = tenantManager
    }

    // MARK: - RouterMiddleware Protocol

    /// Handles the request by resolving tenant context from the Authorization header.
    ///
    /// This method extracts the Authorization header value and uses the tenant
    /// manager to resolve it to a `TenantContext`. If successful, the context
    /// is stored in the request context's `identity` property before passing
    /// the request to the next handler.
    ///
    /// - Parameters:
    ///   - request: The incoming HTTP request.
    ///   - context: The request context to update with tenant information.
    ///   - next: The next handler in the middleware chain.
    /// - Returns: The HTTP response from the downstream handler.
    /// - Throws: `ZoniServerError.unauthorized` if authentication fails.
    public func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        // Extract Authorization header
        let authHeader = request.headers[.authorization]

        // Resolve tenant context
        var context = context
        context.identity = try await tenantManager.resolve(from: authHeader)

        return try await next(request, context)
    }
}

#endif
