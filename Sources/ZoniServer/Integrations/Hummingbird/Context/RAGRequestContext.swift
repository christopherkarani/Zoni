#if HUMMINGBIRD
// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RAGRequestContext.swift - Custom request context for RAG operations.
//
// This file defines the request context used by Zoni's Hummingbird routes,
// providing tenant authentication and request-specific state.

import Hummingbird
import HummingbirdAuth

// MARK: - RAGRequestContext

/// Custom request context for RAG operations.
///
/// `RAGRequestContext` provides the request context required by Zoni's route handlers,
/// implementing both `RequestContext` for standard Hummingbird functionality and
/// `AuthRequestContext` for HummingbirdAuth integration.
///
/// The context stores the resolved tenant identity, which is populated by the
/// `TenantMiddleware` during request processing.
///
/// ## Thread Safety
///
/// `RAGRequestContext` is designed to be used within a single request lifecycle.
/// The `coreContext` and `identity` properties are mutable to allow middleware
/// to update them during request processing.
///
/// ## Example Usage
///
/// ```swift
/// // In a route handler
/// router.post("query") { request, context -> QueryResponse in
///     let tenant = try context.tenant
///     print("Processing query for tenant: \(tenant.tenantId)")
///     // ...
/// }
/// ```
public struct RAGRequestContext: RequestContext, AuthRequestContext {

    // MARK: - RequestContext Protocol

    /// The core request context storage required by Hummingbird.
    ///
    /// This provides access to request ID, logger, and other core functionality.
    public var coreContext: CoreRequestContextStorage

    // MARK: - AuthRequestContext Protocol

    /// The resolved tenant identity for this request.
    ///
    /// This is populated by `TenantMiddleware` during request processing.
    /// Before authentication, this value is `nil`.
    public var identity: TenantContext?

    // MARK: - Initialization

    /// Creates a new RAG request context.
    ///
    /// This initializer is called by Hummingbird when creating a new request context.
    ///
    /// - Parameter source: The source information for the request context.
    public init(source: ApplicationRequestContextSource) {
        self.coreContext = .init(source: source)
        self.identity = nil
    }

    // MARK: - Convenience Properties

    /// The resolved tenant for this request.
    ///
    /// This property provides convenient access to the authenticated tenant context.
    /// It throws an error if the request has not been authenticated.
    ///
    /// - Returns: The authenticated tenant context.
    /// - Throws: `ZoniServerError.unauthorized` if no tenant context is available.
    ///
    /// ## Example
    /// ```swift
    /// let tenant = try context.tenant
    /// print("Tenant ID: \(tenant.tenantId)")
    /// print("Tier: \(tenant.tier)")
    /// ```
    public var tenant: TenantContext {
        get throws {
            guard let identity else {
                throw ZoniServerError.unauthorized(reason: "No tenant context")
            }
            return identity
        }
    }
}

#endif
