// ZoniAgents - SwiftAgents Integration for Zoni RAG Framework
//
// AgentsVectorMemoryBackend.swift - Protocol for vector memory backends.

import Zoni

// MARK: - AgentsVectorMemoryBackend Protocol

/// A protocol for vector memory backends that can be used by SwiftAgents.
///
/// This protocol defines the interface for storing and retrieving agent memories
/// using vector similarity search. Zoni provides an adapter (`ZoniVectorStoreAdapter`)
/// that wraps any `Zoni.VectorStore` to conform to this protocol.
///
/// ## Usage with SwiftAgents
///
/// ```swift
/// // Create a Zoni vector store and wrap it for agent use
/// let vectorStore = InMemoryVectorStore()
/// let memoryBackend = ZoniVectorStoreAdapter(
///     vectorStore: vectorStore,
///     namespace: "agent_memory"
/// )
///
/// // Use with SwiftAgents
/// let memory = VectorMemory(backend: memoryBackend)
/// ```
///
/// ## Namespace Isolation
///
/// The adapter supports namespace isolation, allowing multiple agents to share
/// a single vector store while keeping their memories separate. Isolation is
/// enforced through ID prefixing and metadata filtering.
///
/// ## Concurrency
///
/// Conforming types must be `Sendable` to ensure thread-safe usage across
/// actor boundaries in SwiftAgents applications.
///
/// ## Error Handling
///
/// Methods should throw `ZoniError` types for consistency:
/// - `ZoniError.insertionFailed`: Add/delete/clear failures
/// - `ZoniError.searchFailed`: Search failures
/// - `ZoniError.invalidConfiguration`: Invalid parameters
public protocol AgentsVectorMemoryBackend: Sendable {

    /// Adds a memory entry to the backend.
    ///
    /// - Parameters:
    ///   - id: A unique identifier for this memory entry.
    ///   - content: The text content of the memory.
    ///   - embedding: The pre-computed embedding vector for this content.
    ///   - metadata: Additional metadata to store with the memory.
    ///
    /// - Throws:
    ///   - `ZoniError.invalidConfiguration`: If the ID is empty/invalid or
    ///     the embedding is empty/contains non-finite values.
    ///   - `ZoniError.insertionFailed`: If the backend insertion fails or
    ///     maximum capacity is exceeded.
    func add(
        id: String,
        content: String,
        embedding: [Float],
        metadata: [String: String]
    ) async throws

    /// Searches for memories similar to the given embedding.
    ///
    /// - Parameters:
    ///   - queryEmbedding: The embedding vector to search for.
    ///   - limit: Maximum number of results to return. Must be > 0.
    /// - Returns: An array of search results sorted by similarity (highest first).
    ///
    /// - Throws:
    ///   - `ZoniError.invalidConfiguration`: If the embedding is invalid or limit <= 0.
    ///   - `ZoniError.searchFailed`: If the backend search fails.
    func search(
        queryEmbedding: [Float],
        limit: Int
    ) async throws -> [MemorySearchResult]

    /// Deletes memory entries by their IDs.
    ///
    /// IDs that do not exist are silently ignored. For namespaced backends,
    /// only entries within the current namespace can be deleted.
    ///
    /// - Parameter ids: The IDs of entries to delete.
    ///
    /// - Throws: `ZoniError.insertionFailed` if the backend deletion fails.
    func delete(ids: [String]) async throws

    /// Clears all memory entries from this backend.
    ///
    /// For namespaced backends, this only clears entries in the current namespace.
    /// Other namespaces sharing the same underlying store are unaffected.
    ///
    /// - Throws: `ZoniError.insertionFailed` if the clear operation fails.
    func clear() async throws

    /// Returns the count of memory entries tracked by this backend.
    ///
    /// For adapters that track entries locally (like `ZoniVectorStoreAdapter`),
    /// this returns the count of entries added through this instance, not the
    /// total count in the underlying store.
    ///
    /// - Returns: The count of tracked entries.
    func count() async throws -> Int
}

// MARK: - MemorySearchResult

/// A result from a vector memory search operation.
///
/// Contains the memory content along with its relevance score and metadata.
///
/// ## Score Interpretation
///
/// Zoni vector stores use cosine similarity by default:
/// - **1.0**: Identical vectors (perfect match)
/// - **0.7-0.9**: High relevance
/// - **0.5-0.7**: Moderate relevance
/// - **0.0**: Orthogonal (no similarity)
/// - **-1.0**: Opposite vectors (maximally dissimilar)
public struct MemorySearchResult: Sendable, Equatable {

    /// The unique identifier of this memory entry.
    public let id: String

    /// The text content of the memory.
    public let content: String

    /// The similarity score (higher = more relevant).
    ///
    /// For cosine similarity (default), values range from -1.0 to 1.0.
    /// Other metrics may have different ranges.
    public let score: Float

    /// Additional metadata stored with this memory.
    public let metadata: [String: String]

    /// Creates a new memory search result.
    ///
    /// - Parameters:
    ///   - id: The unique identifier.
    ///   - content: The text content.
    ///   - score: The similarity score.
    ///   - metadata: Additional metadata.
    public init(
        id: String,
        content: String,
        score: Float,
        metadata: [String: String]
    ) {
        self.id = id
        self.content = content
        self.score = score
        self.metadata = metadata
    }
}

// MARK: - MemorySearchResult + Comparable

extension MemorySearchResult: Comparable {

    /// Compares results by score (ascending).
    public static func < (lhs: MemorySearchResult, rhs: MemorySearchResult) -> Bool {
        lhs.score < rhs.score
    }
}

// MARK: - MemorySearchResult + Hashable

extension MemorySearchResult: Hashable {

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(score)
    }
}

// MARK: - MemorySearchResult + CustomStringConvertible

extension MemorySearchResult: CustomStringConvertible {

    public var description: String {
        let preview = content.prefix(50)
        let truncated = content.count > 50 ? "..." : ""
        return "MemorySearchResult(id: \"\(id)\", score: \(String(format: "%.3f", score)), content: \"\(preview)\(truncated)\")"
    }
}
