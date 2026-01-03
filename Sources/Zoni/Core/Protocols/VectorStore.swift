// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// VectorStore protocol for storing and searching vector embeddings.

// MARK: - VectorStore

/// A protocol for storing and searching vector embeddings.
///
/// Implement this protocol to integrate with vector databases
/// like ChromaDB, Pinecone, Qdrant, or in-memory stores.
///
/// `VectorStore` provides a unified interface for:
/// - Adding chunks with their embeddings to the store
/// - Searching for similar chunks by embedding vector
/// - Deleting chunks by ID or metadata filter
/// - Querying store statistics
///
/// ## Example Implementation
/// ```swift
/// actor InMemoryVectorStore: VectorStore {
///     let name = "memory"
///     private var storage: [(chunk: Chunk, embedding: Embedding)] = []
///
///     func add(_ chunks: [Chunk], embeddings: [Embedding]) async throws {
///         for (chunk, embedding) in zip(chunks, embeddings) {
///             storage.append((chunk, embedding))
///         }
///     }
///
///     func search(
///         query: Embedding,
///         limit: Int,
///         filter: MetadataFilter?
///     ) async throws -> [RetrievalResult] {
///         // Implementation...
///     }
///
///     // ... other methods
/// }
/// ```
///
/// ## Thread Safety
/// Conforming types must be `Sendable` to ensure safe concurrent access.
/// Consider using an `actor` for implementations that maintain mutable state.
public protocol VectorStore: Sendable {
    /// The name identifier for this vector store implementation.
    ///
    /// This is used for logging, debugging, and configuration purposes.
    /// Examples: "chromadb", "pinecone", "qdrant", "memory"
    var name: String { get }

    /// Adds chunks with their corresponding embeddings to the store.
    ///
    /// The chunks and embeddings arrays must have the same length and be
    /// in corresponding order (i.e., `embeddings[i]` is the embedding for `chunks[i]`).
    ///
    /// - Parameters:
    ///   - chunks: The chunks to store. Each chunk must have a unique ID.
    ///   - embeddings: Corresponding embeddings for each chunk (same order and count).
    ///
    /// - Throws: `ZoniError.insertionFailed` if the insertion fails due to
    ///   connection issues, invalid data, or other store-specific errors.
    ///
    /// - Note: If a chunk with the same ID already exists, implementations
    ///   should either update it or throw an error based on their semantics.
    func add(_ chunks: [Chunk], embeddings: [Embedding]) async throws

    /// Searches for chunks similar to the given query embedding.
    ///
    /// Results are ranked by similarity score, with higher scores indicating
    /// greater relevance to the query.
    ///
    /// - Parameters:
    ///   - query: The query embedding to search for similar vectors.
    ///   - limit: Maximum number of results to return. Must be positive.
    ///   - filter: Optional metadata filter to narrow the search scope.
    ///
    /// - Returns: An array of `RetrievalResult` objects sorted by relevance
    ///   score in descending order (most relevant first).
    ///
    /// - Throws: `ZoniError.searchFailed` if the search fails due to
    ///   connection issues, invalid query, or other store-specific errors.
    func search(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult]

    /// Deletes chunks with the specified IDs from the store.
    ///
    /// IDs that do not exist in the store are silently ignored.
    ///
    /// - Parameter ids: The IDs of chunks to delete.
    ///
    /// - Throws: `ZoniError.insertionFailed` if the deletion fails due to
    ///   connection issues or other store-specific errors.
    func delete(ids: [String]) async throws

    /// Deletes all chunks matching the specified metadata filter.
    ///
    /// This is useful for bulk deletion operations, such as removing all
    /// chunks from a specific document.
    ///
    /// - Parameter filter: The metadata filter specifying which chunks to delete.
    ///
    /// - Throws: `ZoniError.insertionFailed` if the deletion fails due to
    ///   connection issues or other store-specific errors.
    func delete(filter: MetadataFilter) async throws

    /// Returns the total number of chunks stored in the vector store.
    ///
    /// - Returns: The count of chunks currently in the store.
    ///
    /// - Throws: If the count cannot be determined due to connection issues
    ///   or other store-specific errors.
    func count() async throws -> Int

    /// Checks whether the vector store is empty.
    ///
    /// - Returns: `true` if the store contains no chunks, `false` otherwise.
    ///
    /// - Throws: If the emptiness check fails due to connection issues
    ///   or other store-specific errors.
    func isEmpty() async throws -> Bool
}

// MARK: - Default Implementations

extension VectorStore {
    /// Default implementation that checks if the count is zero.
    ///
    /// Override this method if your vector store provides a more efficient
    /// way to check for emptiness.
    ///
    /// - Returns: `true` if the store contains no chunks.
    public func isEmpty() async throws -> Bool {
        try await count() == 0
    }
}
