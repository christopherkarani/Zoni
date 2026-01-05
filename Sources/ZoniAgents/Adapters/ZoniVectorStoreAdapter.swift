// ZoniAgents - SwiftAgents Integration for Zoni RAG Framework
//
// ZoniVectorStoreAdapter.swift - Adapter wrapping Zoni VectorStore for agent memory.

import Zoni

// MARK: - Configuration

/// Configuration options for ZoniVectorStoreAdapter.
public struct VectorStoreAdapterConfig: Sendable {
    /// Maximum number of entries that can be tracked. Default: 100,000.
    public let maxEntries: Int

    /// Maximum length for entry IDs. Default: 256.
    public let maxIdLength: Int

    /// Default configuration with sensible limits.
    public static let `default` = VectorStoreAdapterConfig(
        maxEntries: 100_000,
        maxIdLength: 256
    )

    public init(maxEntries: Int = 100_000, maxIdLength: Int = 256) {
        self.maxEntries = maxEntries
        self.maxIdLength = maxIdLength
    }
}

// MARK: - ZoniVectorStoreAdapter

/// Adapts a Zoni `VectorStore` to serve as an agent vector memory backend.
///
/// This adapter allows agents to store and retrieve memories using Zoni's
/// vector stores (InMemory, SQLite, Pinecone, etc.) with namespace isolation.
///
/// ## Namespace Isolation
///
/// Each adapter instance operates within a namespace. Multiple adapters can
/// share the same underlying vector store while keeping their data separate.
/// Namespace isolation is enforced through:
/// - **ID prefixing**: All chunk IDs are prefixed with the namespace
/// - **Metadata filtering**: Search and delete operations filter by namespace
///
/// ```swift
/// let store = InMemoryVectorStore()
///
/// let agent1Memory = ZoniVectorStoreAdapter(vectorStore: store, namespace: "agent1")
/// let agent2Memory = ZoniVectorStoreAdapter(vectorStore: store, namespace: "agent2")
///
/// // Each agent only sees its own memories
/// // Isolation persists across adapter restarts
/// ```
///
/// ## Counting Behavior
///
/// The `count()` method returns the count of entries added through this adapter
/// instance. This is tracked locally for performance (O(1) operation).
///
/// - Note: If you create a new adapter for an existing namespace, `count()` will
///   initially return 0 even if the namespace contains data. Use a search to
///   verify existing entries.
///
/// ## Thread Safety
///
/// This adapter is implemented as an actor for safe concurrent access.
/// The generic constraint on `Store` ensures compile-time verification of
/// `Sendable` conformance for Swift 6 strict concurrency.
///
/// ## Error Handling
///
/// Methods throw specific `ZoniError` types:
/// - `ZoniError.insertionFailed`: Add/delete/clear failures
/// - `ZoniError.searchFailed`: Search failures
/// - `ZoniError.invalidConfiguration`: Validation failures
public actor ZoniVectorStoreAdapter<Store: VectorStore>: AgentsVectorMemoryBackend {

    // MARK: - Properties

    /// The wrapped Zoni vector store.
    private let vectorStore: Store

    /// The namespace for this adapter's data.
    public nonisolated let namespace: String

    /// Configuration for this adapter.
    private let config: VectorStoreAdapterConfig

    /// Tracks IDs added through this adapter for accurate namespace counting.
    ///
    /// This set enables O(1) count operations. IDs are stored without the
    /// namespace prefix for user-facing consistency.
    private var trackedIds: Set<String> = []

    // MARK: - Initialization

    /// Creates a new adapter wrapping the given Zoni vector store.
    ///
    /// - Parameters:
    ///   - vectorStore: A Zoni vector store to wrap.
    ///   - namespace: The namespace for this adapter's data. Default: "agent_memory".
    ///   - config: Configuration options. Default: `.default`.
    ///
    /// - Note: The namespace is used as a prefix for all stored IDs to ensure
    ///   isolation persists across adapter restarts.
    public init(
        vectorStore: Store,
        namespace: String = "agent_memory",
        config: VectorStoreAdapterConfig = .default
    ) {
        self.vectorStore = vectorStore
        self.namespace = namespace
        self.config = config
    }

    // MARK: - AgentsVectorMemoryBackend

    /// Adds a memory entry to the backend.
    ///
    /// - Parameters:
    ///   - id: A unique identifier for this memory entry.
    ///   - content: The text content of the memory.
    ///   - embedding: The pre-computed embedding vector for this content.
    ///   - metadata: Additional metadata to store with the memory.
    ///
    /// - Throws:
    ///   - `ZoniError.invalidConfiguration` if the ID is empty, too long, or
    ///     contains invalid characters, or if the embedding is empty or
    ///     contains non-finite values.
    ///   - `ZoniError.insertionFailed` if the maximum entry limit is exceeded
    ///     or the vector store insertion fails.
    public func add(
        id: String,
        content: String,
        embedding: [Float],
        metadata: [String: String]
    ) async throws {
        // Validate inputs
        try validateId(id)
        try validateEmbedding(embedding)

        // Check capacity
        guard trackedIds.count < config.maxEntries else {
            throw ZoniError.insertionFailed(
                reason: "Maximum entry limit of \(config.maxEntries) exceeded"
            )
        }

        // Convert metadata to MetadataValue
        var customMetadata: [String: MetadataValue] = [:]
        for (key, value) in metadata {
            customMetadata[key] = .string(value)
        }

        // Create chunk with prefixed ID for namespace isolation
        let prefixedId = makeNamespacedId(id)
        let chunk = Chunk(
            id: prefixedId,
            content: content,
            metadata: ChunkMetadata(
                documentId: namespace,
                index: 0,
                startOffset: 0,
                endOffset: content.count,
                source: metadata["source"],
                custom: customMetadata
            )
        )

        let embeddingObj = Embedding(vector: embedding, model: nil)
        try await vectorStore.add([chunk], embeddings: [embeddingObj])

        // Track original (non-prefixed) ID for user-facing consistency
        trackedIds.insert(id)
    }

    /// Searches for memories similar to the given embedding.
    ///
    /// Only returns entries within this adapter's namespace.
    ///
    /// - Parameters:
    ///   - queryEmbedding: The embedding vector to search for.
    ///   - limit: Maximum number of results to return. Must be > 0.
    /// - Returns: An array of search results sorted by similarity (highest first).
    ///
    /// - Throws:
    ///   - `ZoniError.invalidConfiguration` if the embedding is empty or contains
    ///     non-finite values, or if limit is <= 0.
    ///   - `ZoniError.searchFailed` if the vector store search fails.
    public func search(
        queryEmbedding: [Float],
        limit: Int
    ) async throws -> [MemorySearchResult] {
        // Validate inputs
        try validateEmbedding(queryEmbedding)
        guard limit > 0 else {
            throw ZoniError.invalidConfiguration(
                reason: "Search limit must be greater than 0"
            )
        }

        let embedding = Embedding(vector: queryEmbedding, model: nil)

        // Search with namespace filter using documentId field
        let filter = MetadataFilter.equals("documentId", .string(namespace))
        let results = try await vectorStore.search(
            query: embedding,
            limit: limit,
            filter: filter
        )

        return results.map { result in
            MemorySearchResult(
                id: stripNamespacePrefix(result.chunk.id),
                content: result.chunk.content,
                score: result.score,
                metadata: extractMetadata(from: result.chunk.metadata)
            )
        }
    }

    /// Deletes memory entries by their IDs.
    ///
    /// Uses namespace-prefixed IDs to ensure isolation. Only entries within
    /// this namespace can be deleted, regardless of the `trackedIds` state.
    ///
    /// - Parameter ids: The IDs of entries to delete.
    ///
    /// - Throws: `ZoniError.insertionFailed` if the vector store deletion fails.
    public func delete(ids: [String]) async throws {
        guard !ids.isEmpty else { return }

        // Create namespace-prefixed IDs for deletion
        // This ensures isolation even if trackedIds is out of sync
        let prefixedIds = ids.map { makeNamespacedId($0) }

        try await vectorStore.delete(ids: prefixedIds)

        // Update tracking for IDs we knew about
        for id in ids {
            trackedIds.remove(id)
        }
    }

    /// Clears all memory entries in this namespace.
    ///
    /// Only entries within this adapter's namespace are deleted.
    /// Other namespaces sharing the same underlying store are unaffected.
    ///
    /// - Throws: `ZoniError.insertionFailed` if the vector store deletion fails.
    public func clear() async throws {
        let filter = MetadataFilter.equals("documentId", .string(namespace))
        try await vectorStore.delete(filter: filter)

        // Reset tracking
        trackedIds.removeAll()
    }

    /// Returns the count of memory entries added through this adapter instance.
    ///
    /// This is an O(1) operation using locally tracked IDs.
    ///
    /// - Note: If you create a new adapter for an existing namespace, this will
    ///   return 0 initially even if the namespace contains data from previous
    ///   sessions. Use `search` to verify existing entries.
    ///
    /// - Returns: The count of entries tracked by this adapter instance.
    public func count() async throws -> Int {
        trackedIds.count
    }

    // MARK: - Public Utilities

    /// Access the underlying Zoni vector store.
    ///
    /// Use this to access store-specific features not exposed through
    /// the `AgentsVectorMemoryBackend` protocol.
    ///
    /// - Warning: Direct manipulation of the underlying store may bypass
    ///   namespace isolation. Use with caution.
    public var underlyingStore: Store {
        vectorStore
    }

    // MARK: - Private Helpers

    /// Creates a namespace-prefixed ID for storage.
    private func makeNamespacedId(_ id: String) -> String {
        "\(namespace)_\(id)"
    }

    /// Strips the namespace prefix from a stored ID.
    private func stripNamespacePrefix(_ prefixedId: String) -> String {
        let prefix = "\(namespace)_"
        if prefixedId.hasPrefix(prefix) {
            return String(prefixedId.dropFirst(prefix.count))
        }
        return prefixedId
    }

    /// Validates an entry ID.
    private func validateId(_ id: String) throws {
        guard !id.isEmpty else {
            throw ZoniError.invalidConfiguration(reason: "ID cannot be empty")
        }
        guard id.count <= config.maxIdLength else {
            throw ZoniError.invalidConfiguration(
                reason: "ID exceeds maximum length of \(config.maxIdLength) characters"
            )
        }
        guard !id.contains("\0") && !id.contains("\n") && !id.contains("\r") else {
            throw ZoniError.invalidConfiguration(
                reason: "ID contains invalid characters (null, newline)"
            )
        }
    }

    /// Validates an embedding vector.
    private func validateEmbedding(_ embedding: [Float]) throws {
        guard !embedding.isEmpty else {
            throw ZoniError.invalidConfiguration(
                reason: "Embedding vector cannot be empty"
            )
        }
        guard embedding.allSatisfy({ $0.isFinite }) else {
            throw ZoniError.invalidConfiguration(
                reason: "Embedding contains non-finite values (NaN or Infinity)"
            )
        }
    }

    /// Extracts string metadata from ChunkMetadata custom dictionary.
    private func extractMetadata(from chunkMetadata: ChunkMetadata) -> [String: String] {
        var result: [String: String] = [:]

        // Add source if present
        if let source = chunkMetadata.source {
            result["source"] = source
        }

        // Extract string values from custom metadata
        for (key, value) in chunkMetadata.custom {
            if case .string(let str) = value {
                result[key] = str
            }
        }

        return result
    }
}

// MARK: - Type-Erased Convenience

/// Type alias for the most common use case with type-erased vector store.
///
/// Use `ZoniVectorStoreAdapter<SomeConcreteStore>` when you need
/// compile-time type safety, or use the factory method
/// `ZoniAgents.memoryBackend(vectorStore:)` for type-erased creation.
public typealias AnyZoniVectorStoreAdapter = ZoniVectorStoreAdapter<InMemoryVectorStore>
