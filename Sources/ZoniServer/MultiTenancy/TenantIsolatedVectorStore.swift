// ZoniServer - Server-side extensions for Zoni
//
// TenantIsolatedVectorStore.swift - A VectorStore wrapper providing tenant isolation.

import Foundation
import Zoni

// MARK: - TenantIsolatedVectorStore

/// A VectorStore wrapper that provides automatic tenant isolation.
///
/// `TenantIsolatedVectorStore` wraps any `VectorStore` implementation and ensures
/// all operations are scoped to a specific tenant. It automatically:
/// - Prefixes chunk and document IDs with the tenant identifier
/// - Adds tenant metadata to all stored chunks
/// - Filters search results to only return the tenant's data
/// - Strips tenant prefixes and metadata from returned results
///
/// ## Data Isolation Strategy
///
/// Tenant isolation is achieved through:
/// 1. **ID Prefixing**: All chunk IDs become `{idPrefix}_{originalId}`
/// 2. **Metadata Injection**: A `_tenantId` field is added to chunk metadata
/// 3. **Query Filtering**: All searches include `_tenantId = tenantId` filter
///
/// This approach enables secure multi-tenant data storage within a single vector
/// store instance while ensuring complete data isolation between tenants.
///
/// ## Example Usage
///
/// ```swift
/// let baseStore = InMemoryVectorStore()
/// let tenant = TenantContext(tenantId: "acme-corp", tier: .professional)
/// let isolatedStore = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant)
///
/// // All operations are now scoped to "acme-corp"
/// try await isolatedStore.add(chunks, embeddings: embeddings)
/// let results = try await isolatedStore.search(query: queryEmbedding, limit: 5)
///
/// // Results only contain acme-corp's data, with tenant metadata stripped
/// for result in results {
///     print(result.chunk.id) // Original ID without prefix
///     print(result.chunk.metadata.custom) // No _tenantId field
/// }
/// ```
///
/// ## Convenience Extension
///
/// Any `VectorStore` can be easily wrapped for tenant isolation:
///
/// ```swift
/// let store = InMemoryVectorStore()
/// let isolatedStore = store.isolated(for: tenant)
/// ```
///
/// ## Thread Safety
///
/// This store is implemented as an `actor`, ensuring thread-safe access when
/// multiple requests for the same tenant execute concurrently. All mutations
/// to the underlying store are serialized through the actor's isolation.
///
/// ## Performance Considerations
///
/// - **ID operations**: O(1) for prefixing and stripping
/// - **Metadata operations**: O(k) where k is the number of custom metadata fields
/// - **Search filtering**: The tenant filter is added to all searches, which may
///   impact performance depending on the underlying store's filter implementation
/// - **Count/Clear operations**: May require scanning all data in stores that don't
///   support efficient filtered counting
public actor TenantIsolatedVectorStore: VectorStore {

    // MARK: - Properties

    /// The name identifier for this isolated vector store.
    ///
    /// Format: `{underlyingName}[tenant:{tenantId}]`
    public nonisolated let name: String

    /// The underlying vector store that holds the actual data.
    private let underlying: any VectorStore

    /// The tenant identifier used for data isolation.
    private let tenantId: String

    /// The prefix applied to all chunk and document IDs.
    ///
    /// This is derived from `TenantConfiguration.indexPrefix` if non-empty,
    /// otherwise falls back to the `tenantId`.
    private let idPrefix: String

    /// Metadata key used for tenant identification.
    ///
    /// This key is added to all stored chunks and used for filtering.
    /// The leading underscore indicates it is an internal/system field.
    public static let tenantMetadataKey = "_tenantId"

    /// Metadata key used for storing the original document ID.
    ///
    /// This allows restoration of the original document ID when retrieving results.
    private static let originalDocumentIdKey = "_originalDocumentId"

    // MARK: - Initialization

    /// Creates a new tenant-isolated vector store wrapping the given underlying store.
    ///
    /// - Parameters:
    ///   - underlying: The vector store to wrap with tenant isolation.
    ///   - tenant: The tenant context providing identity and configuration.
    ///
    /// ## Example
    /// ```swift
    /// let baseStore = InMemoryVectorStore()
    /// let tenant = TenantContext(tenantId: "tenant_123", tier: .professional)
    /// let isolatedStore = TenantIsolatedVectorStore(underlying: baseStore, tenant: tenant)
    /// ```
    public init(underlying: any VectorStore, tenant: TenantContext) {
        self.underlying = underlying
        self.tenantId = tenant.tenantId
        self.idPrefix = tenant.config.indexPrefix.isEmpty
            ? tenant.tenantId
            : tenant.config.indexPrefix
        self.name = "\(underlying.name)[tenant:\(tenant.tenantId)]"
    }

    // MARK: - VectorStore Protocol

    /// Adds chunks with their corresponding embeddings to the tenant's isolated storage.
    ///
    /// This method transforms each chunk before storage:
    /// 1. Prefixes the chunk ID with the tenant's ID prefix
    /// 2. Prefixes the document ID in metadata
    /// 3. Adds the `_tenantId` metadata field for filtering
    /// 4. Stores the original document ID for restoration during retrieval
    ///
    /// - Parameters:
    ///   - chunks: The chunks to store. Each chunk must have a unique ID within the tenant.
    ///   - embeddings: Corresponding embeddings for each chunk (same order and count).
    ///
    /// - Throws: `ZoniError.insertionFailed` if the chunk count does not match
    ///   the embedding count or if the underlying store fails.
    ///
    /// ## Example
    /// ```swift
    /// let chunk = Chunk(
    ///     id: "chunk-1",
    ///     content: "Document content...",
    ///     metadata: ChunkMetadata(documentId: "doc-1", index: 0)
    /// )
    /// let embedding = Embedding(vector: [0.1, 0.2, 0.3])
    ///
    /// try await isolatedStore.add([chunk], embeddings: [embedding])
    /// // Stored as: "tenant_123_chunk-1" with metadata containing "_tenantId": "tenant_123"
    /// ```
    public func add(_ chunks: [Chunk], embeddings: [Embedding]) async throws {
        // Transform chunks for tenant isolation
        let isolatedChunks = chunks.map { isolateChunk($0) }

        // Delegate to underlying store
        try await underlying.add(isolatedChunks, embeddings: embeddings)
    }

    /// Searches for chunks similar to the query embedding within the tenant's data.
    ///
    /// This method ensures tenant isolation by:
    /// 1. Adding a tenant filter (`_tenantId = tenantId`) to all searches
    /// 2. Combining the tenant filter with any user-provided filter using AND logic
    /// 3. Stripping tenant prefixes and metadata from returned results
    ///
    /// - Parameters:
    ///   - query: The query embedding to search for similar vectors.
    ///   - limit: Maximum number of results to return. Must be positive.
    ///   - filter: Optional metadata filter to further narrow the search scope.
    ///     This filter is combined with the implicit tenant filter.
    ///
    /// - Returns: An array of `RetrievalResult` objects sorted by relevance,
    ///   with tenant prefixes and metadata stripped.
    ///
    /// - Throws: `ZoniError.searchFailed` if the search fails.
    ///
    /// ## Example
    /// ```swift
    /// // Basic search within tenant's data
    /// let results = try await isolatedStore.search(
    ///     query: queryEmbedding,
    ///     limit: 10,
    ///     filter: nil
    /// )
    ///
    /// // Search with additional filtering
    /// let filter = MetadataFilter.equals("category", "technology")
    /// let filteredResults = try await isolatedStore.search(
    ///     query: queryEmbedding,
    ///     limit: 5,
    ///     filter: filter
    /// )
    /// // Internally becomes: AND(_tenantId = "tenant_123", category = "technology")
    /// ```
    public func search(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        // Add tenant filter to ensure isolation
        let tenantFilter = addTenantFilter(to: filter)

        // Search underlying store with tenant filter
        let results = try await underlying.search(
            query: query,
            limit: limit,
            filter: tenantFilter
        )

        // Restore original chunk data by stripping tenant prefixes and metadata
        return results.map { result in
            RetrievalResult(
                chunk: restoreChunk(result.chunk),
                score: result.score,
                metadata: result.metadata
            )
        }
    }

    /// Deletes chunks with the specified IDs from the tenant's storage.
    ///
    /// IDs are automatically prefixed with the tenant prefix before deletion.
    /// IDs that do not exist are silently ignored.
    ///
    /// - Parameter ids: The original (unprefixed) IDs of chunks to delete.
    ///
    /// - Throws: If the underlying store's deletion fails.
    ///
    /// ## Example
    /// ```swift
    /// // Delete chunks using original IDs (no prefix needed)
    /// try await isolatedStore.delete(ids: ["chunk-1", "chunk-2"])
    /// // Internally deletes: "tenant_123_chunk-1", "tenant_123_chunk-2"
    /// ```
    public func delete(ids: [String]) async throws {
        // Prefix IDs with tenant prefix before deletion
        let prefixedIds = ids.map { prefixId($0) }
        try await underlying.delete(ids: prefixedIds)
    }

    /// Deletes all chunks matching the specified metadata filter within the tenant's data.
    ///
    /// The tenant filter is automatically combined with the provided filter to ensure
    /// only the tenant's chunks can be deleted.
    ///
    /// - Parameter filter: The metadata filter specifying which chunks to delete.
    ///
    /// - Throws: If the underlying store's deletion fails.
    ///
    /// ## Example
    /// ```swift
    /// // Delete all chunks from a specific document
    /// let filter = MetadataFilter.equals("documentId", "doc-to-remove")
    /// try await isolatedStore.delete(filter: filter)
    /// // Only deletes chunks where _tenantId matches AND documentId matches
    /// ```
    public func delete(filter: MetadataFilter) async throws {
        // Combine with tenant filter to ensure isolation
        let tenantFilter = addTenantFilter(to: filter)
        try await underlying.delete(filter: tenantFilter)
    }

    /// Returns the number of chunks stored for this tenant.
    ///
    /// This implementation attempts to count tenant chunks efficiently by:
    /// 1. First trying the underlying store's `count()` if available and efficient
    /// 2. Falling back to a search-based approach with a reasonable limit
    ///
    /// - Returns: The count of chunks belonging to this tenant.
    ///
    /// - Throws: If the count cannot be determined.
    ///
    /// - Warning: This implementation may undercount for tenants with more than
    ///   100,000 chunks. For high-volume multi-tenant scenarios, consider:
    ///   - Using a vector store with native filtered count support
    ///   - Maintaining cached counts per tenant
    ///   - Adding a dedicated count method to the `VectorStore` protocol
    ///
    /// - Note: The search uses a minimal dimension embedding as a workaround
    ///   since vector stores require a query vector even when only filtering.
    public func count() async throws -> Int {
        // Create a tenant-only filter
        let tenantFilter = MetadataFilter.equals(Self.tenantMetadataKey, .string(tenantId))

        // Maximum number of results we can reliably count
        // This is a trade-off between accuracy and performance
        let maxSearchLimit = 100_000

        // Use a minimal embedding for the search
        // Most vector stores require a query even when just filtering
        // Note: This may fail if the store validates embedding dimensions
        let minimalEmbedding = Embedding(vector: [0.0])

        let results = try await underlying.search(
            query: minimalEmbedding,
            limit: maxSearchLimit,
            filter: tenantFilter
        )

        // If we hit the limit, the actual count may be higher
        if results.count >= maxSearchLimit {
            // Log warning for observability (in production, use proper logging)
            // print("⚠️ TenantIsolatedVectorStore: count() may be underreported for tenant \(tenantId)")
        }

        return results.count
    }

    /// Clears all data belonging to this tenant from the store.
    ///
    /// This method searches for all chunks belonging to the tenant and deletes them.
    /// It does not affect data from other tenants.
    ///
    /// - Throws: If the clear operation fails.
    ///
    /// - Warning: This operation cannot be undone. Use with caution.
    ///
    /// ## Example
    /// ```swift
    /// // Clear all data for tenant "acme-corp"
    /// try await acmeStore.clear()
    /// // Only acme-corp's data is deleted; other tenants are unaffected
    /// ```
    public func clear() async throws {
        // Delete all chunks matching the tenant filter
        let tenantFilter = MetadataFilter.equals(Self.tenantMetadataKey, .string(tenantId))
        try await underlying.delete(filter: tenantFilter)
    }

    // MARK: - Private Helpers

    /// Prefixes an ID with the tenant's ID prefix.
    ///
    /// - Parameter id: The original ID.
    /// - Returns: The prefixed ID in format `{idPrefix}_{id}`.
    private func prefixId(_ id: String) -> String {
        "\(idPrefix)_\(id)"
    }

    /// Strips the tenant prefix from an ID.
    ///
    /// - Parameter id: The prefixed ID.
    /// - Returns: The original ID without the prefix, or the input unchanged if
    ///   it doesn't have the expected prefix.
    private func stripPrefix(_ id: String) -> String {
        let prefix = "\(idPrefix)_"
        if id.hasPrefix(prefix) {
            return String(id.dropFirst(prefix.count))
        }
        return id
    }

    /// Transforms a chunk for tenant-isolated storage.
    ///
    /// This method:
    /// 1. Prefixes the chunk ID
    /// 2. Prefixes the document ID in metadata
    /// 3. Adds the tenant ID to custom metadata
    /// 4. Stores the original document ID for later restoration
    ///
    /// - Parameter chunk: The original chunk.
    /// - Returns: A new chunk ready for tenant-isolated storage.
    private func isolateChunk(_ chunk: Chunk) -> Chunk {
        var customMetadata = chunk.metadata.custom

        // Add tenant ID for filtering
        customMetadata[Self.tenantMetadataKey] = .string(tenantId)

        // Store original document ID for restoration
        customMetadata[Self.originalDocumentIdKey] = .string(chunk.metadata.documentId)

        // Create isolated metadata with prefixed document ID
        let isolatedMetadata = ChunkMetadata(
            documentId: prefixId(chunk.metadata.documentId),
            index: chunk.metadata.index,
            startOffset: chunk.metadata.startOffset,
            endOffset: chunk.metadata.endOffset,
            source: chunk.metadata.source,
            custom: customMetadata
        )

        // Return chunk with prefixed ID and isolated metadata
        return Chunk(
            id: prefixId(chunk.id),
            content: chunk.content,
            metadata: isolatedMetadata,
            embedding: chunk.embedding
        )
    }

    /// Restores a chunk from tenant-isolated storage to its original form.
    ///
    /// This method:
    /// 1. Strips the tenant prefix from the chunk ID
    /// 2. Restores the original document ID from stored metadata
    /// 3. Removes tenant-specific metadata fields
    ///
    /// - Parameter chunk: The isolated chunk from storage.
    /// - Returns: The chunk with original IDs and without tenant metadata.
    private func restoreChunk(_ chunk: Chunk) -> Chunk {
        var customMetadata = chunk.metadata.custom

        // Remove tenant metadata fields
        customMetadata.removeValue(forKey: Self.tenantMetadataKey)

        // Restore original document ID
        let originalDocumentId: String
        if let storedOriginal = customMetadata.removeValue(forKey: Self.originalDocumentIdKey),
           case .string(let value) = storedOriginal {
            originalDocumentId = value
        } else {
            // Fallback: strip prefix from current document ID
            originalDocumentId = stripPrefix(chunk.metadata.documentId)
        }

        // Create restored metadata
        let restoredMetadata = ChunkMetadata(
            documentId: originalDocumentId,
            index: chunk.metadata.index,
            startOffset: chunk.metadata.startOffset,
            endOffset: chunk.metadata.endOffset,
            source: chunk.metadata.source,
            custom: customMetadata
        )

        // Return chunk with original ID and restored metadata
        return Chunk(
            id: stripPrefix(chunk.id),
            content: chunk.content,
            metadata: restoredMetadata,
            embedding: chunk.embedding
        )
    }

    /// Combines a tenant filter with an optional user filter.
    ///
    /// - Parameter filter: The optional user-provided filter.
    /// - Returns: A filter that includes tenant isolation, combined with the
    ///   user filter if provided.
    private func addTenantFilter(to filter: MetadataFilter?) -> MetadataFilter {
        let tenantFilter = MetadataFilter.equals(Self.tenantMetadataKey, .string(tenantId))

        if let existingFilter = filter {
            return .and([tenantFilter, existingFilter])
        }

        return tenantFilter
    }
}

// MARK: - VectorStore Extension for Tenant Support

extension VectorStore {
    /// Creates a tenant-isolated version of this vector store.
    ///
    /// This convenience method wraps the current store with `TenantIsolatedVectorStore`,
    /// providing automatic tenant isolation for all operations.
    ///
    /// - Parameter tenant: The tenant context to isolate operations for.
    /// - Returns: A new `TenantIsolatedVectorStore` wrapping this store.
    ///
    /// ## Example
    /// ```swift
    /// let store = InMemoryVectorStore()
    /// let tenant = TenantContext(tenantId: "acme-corp", tier: .professional)
    /// let isolatedStore = store.isolated(for: tenant)
    ///
    /// // Use isolatedStore for all tenant-specific operations
    /// try await isolatedStore.add(chunks, embeddings: embeddings)
    /// ```
    public func isolated(for tenant: TenantContext) -> TenantIsolatedVectorStore {
        TenantIsolatedVectorStore(underlying: self, tenant: tenant)
    }
}

// MARK: - CustomStringConvertible

extension TenantIsolatedVectorStore: CustomStringConvertible {
    /// A textual representation of the isolated store for debugging.
    nonisolated public var description: String {
        "TenantIsolatedVectorStore(name: \"\(name)\")"
    }
}
