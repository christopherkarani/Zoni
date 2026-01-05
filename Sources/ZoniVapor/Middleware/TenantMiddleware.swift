// ZoniVapor - Vapor framework integration for Zoni RAG
//
// TenantMiddleware.swift - Middleware that resolves tenant from request headers.
//
// This file provides middleware for resolving tenant context from authentication
// credentials in HTTP requests, enabling multi-tenant RAG operations.

import Vapor
import ZoniServer

// MARK: - TenantMiddleware

/// Middleware that resolves tenant context from request headers.
///
/// `TenantMiddleware` extracts authentication credentials from the HTTP
/// Authorization header and resolves the corresponding tenant context.
/// The resolved tenant is stored in the request's storage for use by
/// downstream handlers.
///
/// ## Supported Authentication Methods
///
/// - **API Key**: `Authorization: ApiKey <key>` or `Authorization: <key>`
/// - **JWT Bearer**: `Authorization: Bearer <token>`
///
/// ## Example Usage
///
/// ```swift
/// // Apply to a route group
/// let protected = routes.grouped(TenantMiddleware())
/// protected.get("query") { req in
///     let tenant = req.tenant  // TenantContext available here
///     // ...
/// }
/// ```
///
/// ## Error Handling
///
/// If authentication fails, the middleware throws an appropriate `Abort` error:
/// - 401 Unauthorized: Missing or invalid credentials
/// - 403 Forbidden: Tenant not found or access denied
///
/// ## Thread Safety
///
/// The middleware is stateless and `Sendable`, safe for concurrent use
/// across multiple requests.
public struct TenantMiddleware: AsyncMiddleware {

    // MARK: - Initialization

    /// Creates a new tenant middleware instance.
    public init() {}

    // MARK: - AsyncMiddleware Protocol

    /// Processes the request by resolving tenant context from authentication.
    ///
    /// This method:
    /// 1. Extracts the Authorization header from the request
    /// 2. Resolves the tenant using the configured `TenantManager`
    /// 3. Stores the tenant context in the request's storage
    /// 4. Passes the request to the next handler
    ///
    /// - Parameters:
    ///   - request: The incoming HTTP request.
    ///   - next: The next responder in the middleware chain.
    /// - Returns: The response from downstream handlers.
    /// - Throws: `Abort` with appropriate status code if authentication fails.
    public func respond(
        to request: Request,
        chainingTo next: any AsyncResponder
    ) async throws -> Response {
        let authHeader = request.headers[.authorization].first

        do {
            let tenant = try await request.application.zoni.tenantManager.resolve(from: authHeader)
            request.tenant = tenant
        } catch let error as ZoniServerError {
            throw Abort(
                HTTPResponseStatus(statusCode: error.httpStatusCode),
                reason: error.errorDescription
            )
        }

        return try await next.respond(to: request)
    }
}

// MARK: - Request Extension

extension Request {

    // MARK: - Storage Key

    /// Storage key for the tenant context in the request.
    struct TenantKey: StorageKey {
        typealias Value = TenantContext
    }

    // MARK: - Tenant Property

    /// The tenant context for this request.
    ///
    /// Accessing this property before the `TenantMiddleware` has run
    /// will cause a fatal error. Always use this property in routes
    /// that are protected by the middleware.
    ///
    /// ## Example
    /// ```swift
    /// func handleQuery(req: Request) async throws -> Response {
    ///     let tenant = req.tenant
    ///     // Use tenant.tenantId, tenant.config, etc.
    /// }
    /// ```
    public var tenant: TenantContext {
        get {
            guard let tenant = storage[TenantKey.self] else {
                fatalError("Tenant not resolved. Ensure TenantMiddleware is applied to this route.")
            }
            return tenant
        }
        set {
            storage[TenantKey.self] = newValue
        }
    }

    /// The optional tenant context for this request.
    ///
    /// Use this property when tenant authentication is optional,
    /// such as in health check endpoints that support both authenticated
    /// and unauthenticated access.
    ///
    /// ## Example
    /// ```swift
    /// func handleHealth(req: Request) async throws -> Response {
    ///     if let tenant = req.tenantOptional {
    ///         // Authenticated health check
    ///     } else {
    ///         // Basic health check
    ///     }
    /// }
    /// ```
    public var tenantOptional: TenantContext? {
        storage[TenantKey.self]
    }
}
