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

    /// Maximum number of entries in the cache. Default is 10,000.
    private let maxCacheSize: Int

    // MARK: - Nested Types

    /// A cached tenant context with expiration information.
    struct CachedTenant: Sendable {
        /// The cached tenant context.
        let context: TenantContext

        /// The instant at which this cache entry expires.
        let expiresAt: ContinuousClock.Instant

        /// The last time this cache entry was accessed (for LRU eviction).
        var lastAccessed: ContinuousClock.Instant
    }

    // MARK: - Initialization

    /// Creates a new tenant manager with the specified configuration.
    ///
    /// - Parameters:
    ///   - storage: The storage backend for tenant data persistence.
    ///   - jwtSecret: Optional secret for validating JWT token signatures.
    ///     Bearer JWT authentication requires this secret. If `nil`, Bearer JWT
    ///     requests are rejected and only API key authentication is available.
    ///   - cacheTTL: The duration for which resolved tenants are cached.
    ///     Default is 5 minutes (300 seconds).
    ///   - maxCacheSize: Maximum number of entries in the cache. When this limit
    ///     is reached, the least recently used entries are evicted. Default is 10,000.
    ///
    /// ## Security Best Practices
    ///
    /// ### JWT Secret Requirements (Production)
    /// - **REQUIRED**: Always provide `jwtSecret` in production
    /// - **Minimum length**: 256 bits (32 bytes) for HS256 algorithm
    /// - **Generation**: Use cryptographically secure random generator
    /// - **Storage**: Store in environment variables, never in source code
    /// - **Rotation**: Implement secret rotation strategy
    ///
    /// ### Example (API key only)
    /// ```swift
    /// // Bearer JWTs are rejected when no JWT secret is configured
    /// let manager = TenantManager(storage: myStorage, jwtSecret: nil)
    /// ```
    ///
    /// ### Example (Production - SECURE)
    /// ```swift
    /// // ✅ PRODUCTION - With signature validation
    /// guard let secret = ProcessInfo.processInfo.environment["JWT_SECRET"],
    ///       secret.count >= 32 else {
    ///     fatalError("JWT_SECRET environment variable must be set and ≥32 bytes")
    /// }
    ///
    /// let prodManager = TenantManager(
    ///     storage: myStorage,
    ///     jwtSecret: secret,
    ///     cacheTTL: .minutes(10),
    ///     maxCacheSize: 5000
    /// )
    /// ```
    public init(
        storage: any TenantStorage,
        jwtSecret: String? = nil,
        cacheTTL: Duration = .seconds(300),
        maxCacheSize: Int = 10_000
    ) {
        self.storage = storage
        self.jwtSecret = jwtSecret
        self.cacheTTL = cacheTTL
        self.maxCacheSize = maxCacheSize
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
        if var cached = cache[apiKey], cached.expiresAt > .now {
            // Update last accessed time for LRU
            cached.lastAccessed = .now
            cache[apiKey] = cached
            return cached.context
        }

        // Lookup from storage
        guard let context = try await storage.findByApiKey(apiKey) else {
            throw ZoniServerError.invalidApiKey
        }

        // Cache the result
        let now = ContinuousClock.Instant.now
        cache[apiKey] = CachedTenant(
            context: context,
            expiresAt: now + cacheTTL,
            lastAccessed: now
        )

        // Enforce cache size limit
        evictCacheIfNeeded()

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
        if var cached = cache[token], cached.expiresAt > .now {
            // Update last accessed time for LRU
            cached.lastAccessed = .now
            cache[token] = cached
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

        guard let secret = jwtSecret, !secret.isEmpty else {
            throw ZoniServerError.invalidJWT(
                reason: "Bearer JWT authentication requires a configured jwtSecret"
            )
        }
        guard secret.utf8.count >= 32 else {
            throw ZoniServerError.invalidJWT(
                reason: "Configured jwtSecret is too short; minimum length is 32 bytes"
            )
        }

        let signatureValid = validateJWTSignature(
            header: String(parts[0]),
            payload: String(parts[1]),
            signature: String(parts[2]),
            secret: secret
        )
        guard signatureValid else {
            throw ZoniServerError.invalidJWT(reason: "Invalid signature")
        }

        // Resolve tenant from storage using the tenant_id claim
        guard let tenantId = payload.tenantId else {
            throw ZoniServerError.invalidJWT(reason: "Missing tenant_id claim")
        }

        guard let context = try await storage.find(tenantId: tenantId) else {
            throw ZoniServerError.tenantNotFound(tenantId: tenantId)
        }

        // Cache the result
        let now = ContinuousClock.Instant.now
        cache[token] = CachedTenant(
            context: context,
            expiresAt: now + cacheTTL,
            lastAccessed: now
        )

        // Enforce cache size limit
        evictCacheIfNeeded()

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

    /// Evicts least recently used cache entries if the cache exceeds maxCacheSize.
    ///
    /// This method ensures the cache doesn't grow unbounded by removing the
    /// oldest entries (by last access time) when the limit is reached.
    /// Approximately 10% of the cache is evicted when the limit is exceeded.
    private func evictCacheIfNeeded() {
        guard cache.count > maxCacheSize else { return }

        // Calculate how many entries to remove (10% of cache size)
        let targetRemovalCount = max(1, maxCacheSize / 10)

        // Sort by last accessed time (oldest first) and remove the oldest entries
        let sortedByAge = cache.sorted { $0.value.lastAccessed < $1.value.lastAccessed }
        let keysToRemove = sortedByAge.prefix(targetRemovalCount).map { $0.key }

        for key in keysToRemove {
            cache.removeValue(forKey: key)
        }
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
    /// - Uses isValidAuthenticationCode for constant-time comparison to prevent timing attacks
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

        // Use isValidAuthenticationCode for constant-time comparison to prevent timing attacks
        return HMAC<SHA256>.isValidAuthenticationCode(signatureData, authenticating: messageData, using: key)
    }
}

// MARK: - API Key Hashing Utilities

extension TenantManager {
    private static let apiKeyHashScheme = "pbkdf2-sha256"
    private static let apiKeyHashIterations = 120_000
    private static let apiKeySaltLength = 16
    private static let apiKeyDerivedKeyLength = 32

    /// Hashes an API key using PBKDF2-HMAC-SHA256 with salt and a secret pepper.
    ///
    /// This intentionally uses a slow KDF to increase brute-force cost if hashes
    /// are leaked. The output format is:
    /// `pbkdf2-sha256$<iterations>$<salt-hex>$<derived-key-hex>`
    ///
    /// - Parameters:
    ///   - apiKey: The API key to hash.
    ///   - pepper: Secret pepper stored outside the database (for example env var).
    /// - Returns: Encoded salted hash string suitable for database storage.
    public static func hashApiKey(_ apiKey: String, pepper: String) -> String {
        let salt = randomBytes(count: Self.apiKeySaltLength)
        let password = Data((pepper + ":" + apiKey).utf8)
        let derived = pbkdf2SHA256(
            password: password,
            salt: Data(salt),
            iterations: Self.apiKeyHashIterations,
            keyLength: Self.apiKeyDerivedKeyLength
        )
        return [
            Self.apiKeyHashScheme,
            String(Self.apiKeyHashIterations),
            encodeHex(Data(salt)),
            encodeHex(derived)
        ].joined(separator: "$")
    }

    /// Verifies an API key against a stored PBKDF2 hash in constant time.
    ///
    /// - Parameters:
    ///   - apiKey: The API key to verify.
    ///   - storedHash: Stored hash string in `hashApiKey(_:pepper:)` format.
    ///   - pepper: Secret pepper used when hashing.
    /// - Returns: `true` if the key matches the stored hash.
    public static func verifyApiKey(_ apiKey: String, storedHash: String, pepper: String) -> Bool {
        let parts = storedHash.split(separator: "$", omittingEmptySubsequences: false)
        guard
            parts.count == 4,
            parts[0] == Self.apiKeyHashScheme,
            let iterations = Int(parts[1]),
            iterations > 0,
            let salt = Self.decodeHex(String(parts[2])),
            let expected = Self.decodeHex(String(parts[3]))
        else {
            return false
        }

        let password = Data((pepper + ":" + apiKey).utf8)
        let derived = pbkdf2SHA256(
            password: password,
            salt: Data(salt),
            iterations: iterations,
            keyLength: expected.count
        )
        return constantTimeEquals(derived, Data(expected))
    }

    @available(
        *,
        unavailable,
        message: "Removed for security. Use hashApiKey(_:pepper:) with a secret pepper."
    )
    public static func hashApiKey(_ apiKey: String) -> String {
        fatalError("Unavailable")
    }

    private static func pbkdf2SHA256(
        password: Data,
        salt: Data,
        iterations: Int,
        keyLength: Int
    ) -> Data {
        let hLen = 32 // SHA-256 output length in bytes
        let blockCount = Int(ceil(Double(keyLength) / Double(hLen)))
        let key = SymmetricKey(data: password)

        var derived = Data()
        derived.reserveCapacity(blockCount * hLen)

        for blockIndex in 1...blockCount {
            var blockData = Data()
            blockData.append(salt)

            var beIndex = UInt32(blockIndex).bigEndian
            withUnsafeBytes(of: &beIndex) { rawBuffer in
                blockData.append(contentsOf: rawBuffer)
            }

            var u = Data(HMAC<SHA256>.authenticationCode(for: blockData, using: key))
            var t = u

            if iterations > 1 {
                for _ in 2...iterations {
                    u = Data(HMAC<SHA256>.authenticationCode(for: u, using: key))
                    t = xor(t, u)
                }
            }

            derived.append(t)
        }

        return Data(derived.prefix(keyLength))
    }

    private static func xor(_ lhs: Data, _ rhs: Data) -> Data {
        let lhsBytes = [UInt8](lhs)
        let rhsBytes = [UInt8](rhs)
        guard lhsBytes.count == rhsBytes.count else { return Data() }

        let combined = zip(lhsBytes, rhsBytes).map { $0 ^ $1 }
        return Data(combined)
    }

    private static func randomBytes(count: Int) -> [UInt8] {
        var generator = SystemRandomNumberGenerator()
        return (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
    }

    private static func encodeHex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func decodeHex(_ hex: String) -> [UInt8]? {
        guard hex.count.isMultiple(of: 2) else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)

        var currentIndex = hex.startIndex
        while currentIndex < hex.endIndex {
            let nextIndex = hex.index(currentIndex, offsetBy: 2)
            let byteString = hex[currentIndex..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else {
                return nil
            }
            bytes.append(byte)
            currentIndex = nextIndex
        }

        return bytes
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
