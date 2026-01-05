// ZoniServer - Server-side extensions for Zoni
//
// TenantContext.swift - Multi-tenant context and configuration types

import Foundation

// MARK: - TenantTier

/// The service tier for a tenant, determining available features and limits.
///
/// `TenantTier` defines different levels of service that tenants can subscribe to,
/// each with progressively higher limits and additional features.
///
/// ## Tier Comparison
///
/// | Feature               | Free  | Standard | Professional | Enterprise |
/// |-----------------------|-------|----------|--------------|------------|
/// | Queries/minute        | 10    | 60       | 300          | 1000       |
/// | Documents/day         | 100   | 1000     | 10000        | Unlimited  |
/// | Max document size     | 1 MB  | 10 MB    | 50 MB        | 100 MB     |
/// | Concurrent WebSockets | 1     | 5        | 25           | 100        |
/// | Streaming             | No    | Yes      | Yes          | Yes        |
///
/// ## Example
/// ```swift
/// let tier = TenantTier.professional
/// let config = TenantConfiguration.forTier(tier)
/// print("Queries per minute: \(config.queriesPerMinute)") // 300
/// ```
public enum TenantTier: String, Sendable, Codable, CaseIterable, Equatable {
    /// Free tier with basic limits for evaluation and small projects.
    ///
    /// Suitable for:
    /// - Development and testing
    /// - Small personal projects
    /// - Proof of concept applications
    case free

    /// Standard tier for regular production workloads.
    ///
    /// Suitable for:
    /// - Small to medium applications
    /// - Production workloads with moderate traffic
    /// - Teams getting started with RAG
    case standard

    /// Professional tier for high-volume applications.
    ///
    /// Suitable for:
    /// - Large applications with significant traffic
    /// - Teams requiring higher throughput
    /// - Applications with complex RAG workflows
    case professional

    /// Enterprise tier with maximum limits and dedicated support.
    ///
    /// Suitable for:
    /// - Enterprise-scale applications
    /// - Mission-critical workloads
    /// - Organizations requiring custom configurations
    case enterprise
}

// MARK: - TenantConfiguration

/// Per-tenant configuration settings controlling limits and features.
///
/// `TenantConfiguration` encapsulates all configurable aspects of a tenant's
/// access to the RAG system, including rate limits, size constraints, and
/// feature toggles.
///
/// ## Usage
///
/// Create a configuration with custom settings:
/// ```swift
/// let config = TenantConfiguration(
///     queriesPerMinute: 100,
///     documentsPerDay: 500,
///     maxDocumentSize: 5 * 1024 * 1024, // 5 MB
///     enableStreaming: true
/// )
/// ```
///
/// Or use tier-based presets:
/// ```swift
/// let config = TenantConfiguration.forTier(.professional)
/// ```
///
/// ## Thread Safety
/// `TenantConfiguration` is `Sendable` and can be safely shared across
/// actor boundaries and concurrent contexts.
public struct TenantConfiguration: Sendable, Codable, Equatable {

    // MARK: - Rate Limits

    /// The maximum number of queries allowed per minute.
    ///
    /// Queries include both search and generation requests.
    /// When exceeded, requests return a rate limit error.
    public var queriesPerMinute: Int

    /// The maximum number of documents that can be ingested per day.
    ///
    /// This limit resets at midnight UTC.
    /// A value of `Int.max` indicates unlimited ingestion.
    public var documentsPerDay: Int

    /// The maximum number of concurrent WebSocket connections.
    ///
    /// Additional connection attempts beyond this limit are rejected.
    public var maxConcurrentWebSockets: Int

    // MARK: - Size Limits

    /// The maximum size of a single document in bytes.
    ///
    /// Documents exceeding this size are rejected during ingestion.
    /// Common values:
    /// - 1 MB: `1_048_576`
    /// - 10 MB: `10_485_760`
    /// - 100 MB: `104_857_600`
    public var maxDocumentSize: Int

    /// The maximum number of chunks that can be created from a single document.
    ///
    /// This prevents excessively large documents from overwhelming the system.
    /// If a document would produce more chunks, ingestion fails.
    public var maxChunksPerDocument: Int

    // MARK: - Features

    /// The embedding model to use for this tenant.
    ///
    /// When `nil`, the system default embedding model is used.
    /// Examples: "text-embedding-3-small", "text-embedding-3-large"
    public var embeddingModel: String?

    /// The prefix to use for this tenant's vector store indices.
    ///
    /// This enables multi-tenant isolation within a shared vector store.
    /// The prefix is prepended to all index names for this tenant.
    ///
    /// Example: If `indexPrefix` is "tenant_123_", an index named "documents"
    /// becomes "tenant_123_documents".
    public var indexPrefix: String

    /// Whether streaming responses are enabled for this tenant.
    ///
    /// When `true`, the tenant can receive streamed LLM responses.
    /// Streaming is typically disabled for the free tier.
    public var enableStreaming: Bool

    // MARK: - Initialization

    /// Creates a new tenant configuration with the specified settings.
    ///
    /// - Parameters:
    ///   - queriesPerMinute: Maximum queries per minute. Default: `60`.
    ///   - documentsPerDay: Maximum documents per day. Default: `1000`.
    ///   - maxConcurrentWebSockets: Maximum WebSocket connections. Default: `5`.
    ///   - maxDocumentSize: Maximum document size in bytes. Default: `10_485_760` (10 MB).
    ///   - maxChunksPerDocument: Maximum chunks per document. Default: `1000`.
    ///   - embeddingModel: The embedding model to use. Default: `nil` (system default).
    ///   - indexPrefix: The prefix for index names. Default: `""`.
    ///   - enableStreaming: Whether streaming is enabled. Default: `true`.
    public init(
        queriesPerMinute: Int = 60,
        documentsPerDay: Int = 1000,
        maxConcurrentWebSockets: Int = 5,
        maxDocumentSize: Int = 10_485_760,
        maxChunksPerDocument: Int = 1000,
        embeddingModel: String? = nil,
        indexPrefix: String = "",
        enableStreaming: Bool = true
    ) {
        self.queriesPerMinute = queriesPerMinute
        self.documentsPerDay = documentsPerDay
        self.maxConcurrentWebSockets = maxConcurrentWebSockets
        self.maxDocumentSize = maxDocumentSize
        self.maxChunksPerDocument = maxChunksPerDocument
        self.embeddingModel = embeddingModel
        self.indexPrefix = indexPrefix
        self.enableStreaming = enableStreaming
    }

    // MARK: - Default Configuration

    /// The default tenant configuration with standard tier settings.
    ///
    /// This configuration provides balanced defaults suitable for most use cases:
    /// - 60 queries per minute
    /// - 1000 documents per day
    /// - 5 concurrent WebSocket connections
    /// - 10 MB maximum document size
    /// - 1000 chunks per document
    /// - Streaming enabled
    public static let `default` = TenantConfiguration(
        queriesPerMinute: 60,
        documentsPerDay: 1000,
        maxConcurrentWebSockets: 5,
        maxDocumentSize: 10_485_760,
        maxChunksPerDocument: 1000,
        embeddingModel: nil,
        indexPrefix: "",
        enableStreaming: true
    )

    // MARK: - Tier-Based Presets

    /// Creates a configuration with preset values for the specified tier.
    ///
    /// Use this method to quickly create configurations based on service tiers
    /// without specifying individual settings.
    ///
    /// - Parameter tier: The service tier to create configuration for.
    /// - Returns: A `TenantConfiguration` with appropriate limits for the tier.
    ///
    /// ## Example
    /// ```swift
    /// let freeConfig = TenantConfiguration.forTier(.free)
    /// let enterpriseConfig = TenantConfiguration.forTier(.enterprise)
    ///
    /// print(freeConfig.queriesPerMinute)       // 10
    /// print(enterpriseConfig.queriesPerMinute) // 1000
    /// ```
    public static func forTier(_ tier: TenantTier) -> TenantConfiguration {
        switch tier {
        case .free:
            return TenantConfiguration(
                queriesPerMinute: 10,
                documentsPerDay: 100,
                maxConcurrentWebSockets: 1,
                maxDocumentSize: 1_048_576,        // 1 MB
                maxChunksPerDocument: 100,
                embeddingModel: nil,
                indexPrefix: "",
                enableStreaming: false
            )

        case .standard:
            return TenantConfiguration(
                queriesPerMinute: 60,
                documentsPerDay: 1000,
                maxConcurrentWebSockets: 5,
                maxDocumentSize: 10_485_760,       // 10 MB
                maxChunksPerDocument: 1000,
                embeddingModel: nil,
                indexPrefix: "",
                enableStreaming: true
            )

        case .professional:
            return TenantConfiguration(
                queriesPerMinute: 300,
                documentsPerDay: 10000,
                maxConcurrentWebSockets: 25,
                maxDocumentSize: 52_428_800,       // 50 MB
                maxChunksPerDocument: 5000,
                embeddingModel: nil,
                indexPrefix: "",
                enableStreaming: true
            )

        case .enterprise:
            return TenantConfiguration(
                queriesPerMinute: 1000,
                documentsPerDay: Int.max,          // Unlimited
                maxConcurrentWebSockets: 100,
                maxDocumentSize: 104_857_600,      // 100 MB
                maxChunksPerDocument: 10000,
                embeddingModel: nil,
                indexPrefix: "",
                enableStreaming: true
            )
        }
    }
}

// MARK: - TenantContext

/// Immutable context representing a tenant for the current request.
///
/// `TenantContext` provides all tenant-specific information needed to process
/// a request, including identity, tier, and configuration. This context is
/// resolved from authentication credentials at the start of each request.
///
/// ## Usage
///
/// Create a tenant context:
/// ```swift
/// let context = TenantContext(
///     tenantId: "tenant_abc123",
///     organizationId: "org_xyz789",
///     tier: .professional,
///     config: TenantConfiguration.forTier(.professional)
/// )
/// ```
///
/// Use in request processing:
/// ```swift
/// func handleQuery(context: TenantContext, query: String) async throws -> Response {
///     // Check rate limits based on tenant tier
///     guard context.config.enableStreaming else {
///         throw ServerError.streamingNotEnabled
///     }
///     // Process query with tenant's index prefix
///     let indexName = "\(context.config.indexPrefix)documents"
///     // ...
/// }
/// ```
///
/// ## Thread Safety
/// `TenantContext` is immutable and `Sendable`, making it safe to pass
/// across actor boundaries and use in concurrent contexts.
public struct TenantContext: Sendable, Equatable {

    // MARK: - Properties

    /// The unique identifier for this tenant.
    ///
    /// This is the primary key used to identify the tenant across all systems.
    /// Format is typically "tenant_" followed by a unique alphanumeric string.
    public let tenantId: String

    /// The organization identifier, if the tenant belongs to an organization.
    ///
    /// Organizations can contain multiple tenants with shared billing
    /// and administration. This is `nil` for standalone tenants.
    public let organizationId: String?

    /// The service tier for this tenant.
    ///
    /// The tier determines the base limits and features available,
    /// which may be customized in the `config` property.
    public let tier: TenantTier

    /// The configuration settings for this tenant.
    ///
    /// This may be the default configuration for the tier, or a customized
    /// configuration specific to this tenant.
    public let config: TenantConfiguration

    /// The date and time when this tenant was created.
    ///
    /// This is used for auditing, analytics, and lifecycle management.
    public let createdAt: Date

    // MARK: - Initialization

    /// Creates a new tenant context with the specified properties.
    ///
    /// - Parameters:
    ///   - tenantId: The unique identifier for this tenant.
    ///   - organizationId: The organization identifier, if applicable. Default: `nil`.
    ///   - tier: The service tier for this tenant. Default: `.standard`.
    ///   - config: The configuration settings. Default: configuration for the tier.
    ///   - createdAt: The creation timestamp. Default: current date and time.
    ///
    /// ## Example
    /// ```swift
    /// // Create with defaults
    /// let context = TenantContext(tenantId: "tenant_123")
    ///
    /// // Create with full customization
    /// let customContext = TenantContext(
    ///     tenantId: "tenant_456",
    ///     organizationId: "org_789",
    ///     tier: .enterprise,
    ///     config: TenantConfiguration(
    ///         queriesPerMinute: 2000,  // Custom override
    ///         documentsPerDay: Int.max,
    ///         maxConcurrentWebSockets: 200
    ///     )
    /// )
    /// ```
    public init(
        tenantId: String,
        organizationId: String? = nil,
        tier: TenantTier = .standard,
        config: TenantConfiguration? = nil,
        createdAt: Date = Date()
    ) {
        self.tenantId = tenantId
        self.organizationId = organizationId
        self.tier = tier
        self.config = config ?? TenantConfiguration.forTier(tier)
        self.createdAt = createdAt
    }
}

// MARK: - TenantContext CustomStringConvertible

extension TenantContext: CustomStringConvertible {

    /// A textual representation of the tenant context.
    public var description: String {
        let org = organizationId.map { ", org: \($0)" } ?? ""
        return "TenantContext(id: \(tenantId)\(org), tier: \(tier.rawValue))"
    }
}
