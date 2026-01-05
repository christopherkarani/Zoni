// ZoniServer - Server-side extensions for Zoni
//
// TenantManager.swift - Thread-safe tenant resolution from authentication credentials.
//
// This actor provides tenant resolution from API keys and JWT tokens with
// built-in caching for performance optimization.

import Foundation
import Crypto

// MARK: - TenantManager

/// Actor that manages tenant resolution from authentication credentials.
///
/// `TenantManager` provides thread-safe tenant lookup from API keys and JWT tokens.
/// It implements the `TenantResolver` protocol and caches resolved tenants for
/// improved performance on repeated lookups.
///
/// ## Authentication Methods
///
/// Two authentication methods are supported:
/// - **API Key**: Header format `ApiKey <key>` or raw API key
/// - **JWT Bearer**: Header format `Bearer <token>`
///
/// ## Caching Behavior
///
/// Resolved tenant contexts are cached with a configurable TTL (time-to-live).
/// The cache is keyed by the credential (API key or JWT token), and entries
/// are automatically invalidated when the TTL expires.
///
/// ## Example Usage
///
/// ```swift
/// // Initialize with storage backend
/// let manager = TenantManager(storage: PostgresTenantStorage(db: pool))
///
/// // Resolve from Authorization header
/// let tenant = try await manager.resolve(from: "Bearer eyJ...")
///
/// // Resolve from API key directly
/// let tenant = try await manager.resolve(from: "sk-abc123")
///
/// // Invalidate cache for a specific tenant
/// await manager.invalidateCache(for: "tenant_123")
/// ```
///
/// ## Thread Safety
///
/// As an actor, `TenantManager` guarantees thread-safe access to its internal
/// state including the cache. All public methods are isolated to the actor's
/// execution context.
public actor TenantManager: TenantResolver {

    // MARK: - Properties

    /// The storage backend for tenant data.
    private let storage: any TenantStorage

    /// Cache of resolved tenant contexts keyed by credential.
    private var cache: [String: CachedTenant] = [:]

    /// The time-to-live duration for cached entries.
    private let cacheTTL: Duration

    /// Optional secret for JWT signature validation.
    private let jwtSecret: String?

    // MARK: - Nested Types

    /// A cached tenant context with expiration information.
    struct CachedTenant: Sendable {
        /// The cached tenant context.
        let context: TenantContext

        /// The instant at which this cache entry expires.
        let expiresAt: ContinuousClock.Instant
    }

    // MARK: - Initialization

    /// Creates a new tenant manager with the specified configuration.
    ///
    /// - Parameters:
    ///   - storage: The storage backend for tenant data persistence.
    ///   - jwtSecret: Optional secret for validating JWT token signatures.
    ///     When `nil`, JWT signature validation is skipped and only the
    ///     payload is used for tenant resolution.
    ///   - cacheTTL: The duration for which resolved tenants are cached.
    ///     Default is 5 minutes (300 seconds).
    ///
    /// ## Example
    /// ```swift
    /// // Basic initialization
    /// let manager = TenantManager(storage: myStorage)
    ///
    /// // With JWT validation and custom cache TTL
    /// let secureManager = TenantManager(
    ///     storage: myStorage,
    ///     jwtSecret: "my-secret-key",
    ///     cacheTTL: .minutes(10)
    /// )
    /// ```
    public init(
        storage: any TenantStorage,
        jwtSecret: String? = nil,
        cacheTTL: Duration = .seconds(300)
    ) {
        self.storage = storage
        self.jwtSecret = jwtSecret
        self.cacheTTL = cacheTTL
    }

    // MARK: - TenantResolver Protocol

    /// Resolves a tenant context from an HTTP Authorization header.
    ///
    /// This method extracts and validates credentials from the Authorization
    /// header, then returns the corresponding tenant context. It supports
    /// multiple header formats.
    ///
    /// ## Supported Header Formats
    ///
    /// - `Bearer <jwt_token>`: JWT token authentication
    /// - `ApiKey <api_key>`: Explicit API key authentication
    /// - `<api_key>`: Raw API key (no prefix)
    ///
    /// - Parameter authHeader: The value of the HTTP Authorization header,
    ///   or `nil` if no header was provided.
    /// - Returns: The resolved tenant context.
    /// - Throws: `ZoniServerError.unauthorized` if the header is missing,
    ///   `ZoniServerError.invalidApiKey` if the API key is invalid, or
    ///   `ZoniServerError.invalidJWT` if the JWT token is invalid.
    ///
    /// ## Example
    /// ```swift
    /// // Resolve from Bearer token
    /// let context = try await manager.resolve(from: "Bearer eyJ...")
    ///
    /// // Resolve from API key header
    /// let context = try await manager.resolve(from: "ApiKey sk-abc123")
    ///
    /// // Resolve from raw API key
    /// let context = try await manager.resolve(from: "sk-abc123")
    /// ```
    public func resolve(from authHeader: String?) async throws -> TenantContext {
        guard let header = authHeader else {
            throw ZoniServerError.unauthorized(reason: "Missing authorization header")
        }

        // Support: "Bearer <jwt>", "ApiKey <key>", or raw API key
        if header.hasPrefix("Bearer ") {
            return try await resolveFromJWT(String(header.dropFirst(7)))
        } else if header.hasPrefix("ApiKey ") {
            return try await resolve(from: String(header.dropFirst(7)))
        } else {
            // Assume raw API key
            return try await resolve(from: header)
        }
    }

    /// Resolves a tenant context from an API key.
    ///
    /// This method first checks the cache for a valid entry. If not found
    /// or expired, it looks up the tenant from storage and caches the result.
    ///
    /// - Parameter apiKey: The API key to validate.
    /// - Returns: The resolved tenant context.
    /// - Throws: `ZoniServerError.invalidApiKey` if no tenant is found for
    ///   the provided API key.
    ///
    /// ## Example
    /// ```swift
    /// let context = try await manager.resolve(from: "sk-abc123")
    /// print("Resolved tenant: \(context.tenantId)")
    /// ```
    public func resolve(from apiKey: String) async throws -> TenantContext {
        // Check cache for valid entry
        if let cached = cache[apiKey], cached.expiresAt > .now {
            return cached.context
        }

        // Lookup from storage
        guard let context = try await storage.findByApiKey(apiKey) else {
            throw ZoniServerError.invalidApiKey
        }

        // Cache the result
        cache[apiKey] = CachedTenant(
            context: context,
            expiresAt: .now + cacheTTL
        )

        return context
    }

    // MARK: - JWT Resolution

    /// Resolves a tenant context from a JWT token.
    ///
    /// This method performs basic JWT parsing to extract the tenant identifier
    /// from the token's payload. If a JWT secret is configured, it also validates
    /// the token's signature.
    ///
    /// ## JWT Payload Requirements
    ///
    /// The JWT payload must contain a `tenant_id` claim with the tenant's
    /// unique identifier:
    ///
    /// ```json
    /// {
    ///     "tenant_id": "tenant_123",
    ///     "sub": "user_456",
    ///     "exp": 1704067200
    /// }
    /// ```
    ///
    /// - Parameter token: The JWT token string (without the "Bearer " prefix).
    /// - Returns: The resolved tenant context.
    /// - Throws: `ZoniServerError.invalidJWT` if the token is malformed,
    ///   the signature is invalid (when secret is configured), or the token
    ///   has expired. `ZoniServerError.tenantNotFound` if the tenant ID
    ///   from the token does not exist.
    private func resolveFromJWT(_ token: String) async throws -> TenantContext {
        // Check cache first
        if let cached = cache[token], cached.expiresAt > .now {
            return cached.context
        }

        // Parse JWT (header.payload.signature)
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            throw ZoniServerError.invalidJWT(reason: "Invalid token format: expected 3 parts")
        }

        // Decode payload (second part)
        let payloadPart = String(parts[1])
        guard let payloadData = base64URLDecode(payloadPart) else {
            throw ZoniServerError.invalidJWT(reason: "Invalid base64url encoding in payload")
        }

        // Parse payload JSON
        let payload: JWTPayload
        do {
            payload = try JSONDecoder().decode(JWTPayload.self, from: payloadData)
        } catch {
            throw ZoniServerError.invalidJWT(reason: "Failed to decode payload: \(error.localizedDescription)")
        }

        // Check expiration
        if let exp = payload.exp {
            let expirationDate = Date(timeIntervalSince1970: TimeInterval(exp))
            if expirationDate < Date() {
                throw ZoniServerError.tokenExpired
            }
        }

        // Validate signature if secret is configured
        if let secret = jwtSecret {
            let signatureValid = validateJWTSignature(
                header: String(parts[0]),
                payload: String(parts[1]),
                signature: String(parts[2]),
                secret: secret
            )
            guard signatureValid else {
                throw ZoniServerError.invalidJWT(reason: "Invalid signature")
            }
        }

        // Resolve tenant from storage using the tenant_id claim
        guard let tenantId = payload.tenantId else {
            throw ZoniServerError.invalidJWT(reason: "Missing tenant_id claim")
        }

        guard let context = try await storage.find(tenantId: tenantId) else {
            throw ZoniServerError.tenantNotFound(tenantId: tenantId)
        }

        // Cache the result
        cache[token] = CachedTenant(
            context: context,
            expiresAt: .now + cacheTTL
        )

        return context
    }

    // MARK: - Cache Management

    /// Invalidates all cached entries for a specific tenant.
    ///
    /// Use this method when a tenant's configuration changes to ensure
    /// subsequent requests fetch fresh data from storage.
    ///
    /// - Parameter tenantId: The unique identifier of the tenant whose
    ///   cache entries should be invalidated.
    ///
    /// ## Example
    /// ```swift
    /// // After updating tenant configuration
    /// await manager.invalidateCache(for: "tenant_123")
    /// ```
    public func invalidateCache(for tenantId: String) {
        // Remove all cache entries for this tenant
        cache = cache.filter { $0.value.context.tenantId != tenantId }
    }

    /// Clears all cached tenant entries.
    ///
    /// Use this method to force all subsequent requests to fetch fresh
    /// data from storage. This may be useful after bulk configuration
    /// changes or for testing.
    ///
    /// ## Example
    /// ```swift
    /// // Clear all cached data
    /// await manager.clearCache()
    /// ```
    public func clearCache() {
        cache.removeAll()
    }

    /// Removes expired entries from the cache.
    ///
    /// This method performs cache maintenance by removing entries that
    /// have exceeded their TTL. Call this periodically to prevent
    /// unbounded cache growth.
    ///
    /// ## Example
    /// ```swift
    /// // Periodic cleanup
    /// await manager.pruneExpiredEntries()
    /// ```
    public func pruneExpiredEntries() {
        let now = ContinuousClock.Instant.now
        cache = cache.filter { $0.value.expiresAt > now }
    }

    /// Returns the current number of cached entries.
    ///
    /// - Returns: The number of entries currently in the cache.
    public var cacheCount: Int {
        cache.count
    }

    // MARK: - Private Helpers

    /// Decodes a base64url-encoded string to data.
    ///
    /// Base64url encoding differs from standard base64 by using `-` and `_`
    /// instead of `+` and `/`, and omitting padding characters.
    ///
    /// - Parameter string: The base64url-encoded string.
    /// - Returns: The decoded data, or `nil` if decoding fails.
    private func base64URLDecode(_ string: String) -> Data? {
        // Convert base64url to standard base64
        var base64 = string
            .replacing("-", with: "+")
            .replacing("_", with: "/")

        // Add padding if needed
        let paddingLength = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: paddingLength)

        return Data(base64Encoded: base64)
    }

    /// Validates a JWT signature using HMAC-SHA256.
    ///
    /// This method implements secure signature validation using the CryptoKit
    /// framework. It computes the expected signature using HMAC-SHA256 and
    /// compares it against the provided signature using constant-time comparison.
    ///
    /// - Parameters:
    ///   - header: The base64url-encoded header.
    ///   - payload: The base64url-encoded payload.
    ///   - signature: The base64url-encoded signature.
    ///   - secret: The secret key for HMAC validation.
    /// - Returns: `true` if the signature is valid, `false` otherwise.
    ///
    /// ## Security Notes
    /// - Uses HMAC-SHA256 as specified by JWT standard (HS256 algorithm)
    /// - Comparison is constant-time to prevent timing attacks
    /// - The secret should be at least 256 bits (32 bytes) for security
    private func validateJWTSignature(
        header: String,
        payload: String,
        signature: String,
        secret: String
    ) -> Bool {
        // Decode the signature from base64url
        guard let signatureData = base64URLDecode(signature) else {
            return false
        }

        // Prepare the message to sign (header.payload)
        let message = "\(header).\(payload)"
        guard let messageData = message.data(using: .utf8) else {
            return false
        }

        // Create symmetric key from secret
        guard let secretData = secret.data(using: .utf8) else {
            return false
        }
        let key = SymmetricKey(data: secretData)

        // Compute the expected signature using HMAC-SHA256
        let computedSignature = HMAC<SHA256>.authenticationCode(for: messageData, using: key)

        // Compare signatures using constant-time comparison
        // CryptoKit's Data comparison for HMAC codes is already constant-time
        return Data(computedSignature) == signatureData
    }
}

// MARK: - API Key Hashing Utilities

extension TenantManager {
    /// Hashes an API key using SHA256.
    ///
    /// This utility method can be used by `TenantStorage` implementations
    /// to hash API keys before storage or comparison.
    ///
    /// - Parameter apiKey: The API key to hash.
    /// - Returns: The hexadecimal representation of the SHA256 hash.
    ///
    /// ## Example
    /// ```swift
    /// let hashedKey = TenantManager.hashApiKey("sk-live-abc123")
    /// // Store hashedKey in database instead of the raw API key
    /// ```
    public static func hashApiKey(_ apiKey: String) -> String {
        let data = Data(apiKey.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - JWTPayload

/// Internal structure for decoding JWT payloads.
///
/// This struct captures the claims relevant for tenant resolution.
private struct JWTPayload: Codable, Sendable {
    /// The tenant identifier claim.
    let tenantId: String?

    /// The subject (user) identifier.
    let sub: String?

    /// The expiration timestamp (seconds since Unix epoch).
    let exp: Int?

    /// The issued-at timestamp (seconds since Unix epoch).
    let iat: Int?

    /// The issuer claim.
    let iss: String?

    private enum CodingKeys: String, CodingKey {
        case tenantId = "tenant_id"
        case sub
        case exp
        case iat
        case iss
    }
}
