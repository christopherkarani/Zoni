// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// InMemoryVectorStore.swift - An in-memory vector store for testing and small datasets.

import Foundation

// MARK: - InMemoryVectorStore

/// An in-memory vector store for testing, prototyping, and small datasets.
///
/// `InMemoryVectorStore` keeps all chunks and embeddings in memory using Swift
/// dictionaries, providing fast access without external dependencies. This makes
/// it ideal for:
/// - **Testing**: Write unit tests without setting up external vector databases
/// - **Prototyping**: Quickly iterate on RAG pipeline configurations
/// - **Small datasets**: Handle datasets that fit comfortably in memory
/// - **Development**: Work offline without database connectivity
///
/// ## Thread Safety
///
/// This store is implemented as an `actor`, ensuring safe concurrent access
/// from multiple tasks. All mutations are serialized through the actor's
/// isolation, preventing data races.
///
/// ## Performance Characteristics
///
/// - **Add**: O(n) where n is the number of chunks being added
/// - **Search**: O(m * d) where m is total chunks and d is embedding dimensions
/// - **Delete by ID**: O(k) where k is the number of IDs to delete
/// - **Delete by filter**: O(m) where m is total chunks (must scan all)
/// - **Count**: O(1)
///
/// For large datasets (>10,000 chunks) or production workloads, consider using
/// a dedicated vector database like ChromaDB, Pinecone, or Qdrant.
///
/// ## Example Usage
///
/// ```swift
/// // Create an in-memory store
/// let store = InMemoryVectorStore()
///
/// // Add chunks with embeddings
/// let chunks = [
///     Chunk(content: "Swift is a powerful language...",
///           metadata: ChunkMetadata(documentId: "doc1", index: 0)),
///     Chunk(content: "Concurrency in Swift uses async/await...",
///           metadata: ChunkMetadata(documentId: "doc1", index: 1))
/// ]
/// let embeddings = try await embedder.embed(chunks.map { $0.content })
/// try await store.add(chunks, embeddings: embeddings)
///
/// // Search for similar chunks
/// let queryEmbedding = try await embedder.embed("How does Swift handle concurrency?")
/// let results = try await store.search(query: queryEmbedding, limit: 5, filter: nil)
///
/// for result in results {
///     print("Score: \(result.score), Content: \(result.chunk.content)")
/// }
///
/// // Filter by metadata
/// let filter = MetadataFilter.equals("documentId", "doc1")
/// let filteredResults = try await store.search(query: queryEmbedding, limit: 5, filter: filter)
///
/// // Persist to disk for later use
/// try await store.save(to: URL(fileURLWithPath: "/path/to/store.json"))
///
/// // Load from disk
/// let loadedStore = InMemoryVectorStore()
/// try await loadedStore.load(from: URL(fileURLWithPath: "/path/to/store.json"))
/// ```
///
/// ## Persistence
///
/// While primarily an in-memory store, `InMemoryVectorStore` supports JSON-based
/// persistence through the `save(to:)` and `load(from:)` methods. This allows
/// you to:
/// - Save state between application launches
/// - Share test fixtures across test suites
/// - Create snapshots for debugging
///
/// Note that persistence is not automatic - you must explicitly call `save(to:)`
/// to persist changes.
public actor InMemoryVectorStore: VectorStore {

    // MARK: - Properties

    /// The name identifier for this vector store implementation.
    ///
    /// This is used for logging, debugging, and configuration purposes.
    public nonisolated let name = "in_memory"

    /// Storage for chunks indexed by their unique ID.
    private var chunks: [String: Chunk] = [:]

    /// Storage for embeddings indexed by the corresponding chunk ID.
    private var embeddings: [String: Embedding] = [:]

    /// The expected number of dimensions for embeddings in this store.
    ///
    /// This is set on the first `add()` call and validated on subsequent calls
    /// to ensure all embeddings have consistent dimensions.
    private var expectedDimensions: Int?

    /// Maximum file size for loading (100 MB by default).
    ///
    /// This limit prevents loading excessively large files that could cause
    /// memory issues.
    private static let maxLoadFileSize = 100 * 1024 * 1024

    // MARK: - Initialization

    /// Creates a new empty in-memory vector store.
    ///
    /// The store starts with no data. Use `add(_:embeddings:)` to populate
    /// it with chunks, or `load(from:)` to restore from a saved state.
    public init() {}

    // MARK: - VectorStore Protocol

    /// Adds chunks with their corresponding embeddings to the store.
    ///
    /// This method uses upsert semantics: if a chunk with the same ID already
    /// exists, it will be replaced with the new chunk and embedding.
    ///
    /// - Parameters:
    ///   - chunks: The chunks to store. Each chunk must have a unique ID.
    ///   - embeddings: Corresponding embeddings for each chunk. Must be in the
    ///     same order and have the same count as `chunks`.
    ///
    /// - Throws: `ZoniError.insertionFailed` if the chunk count does not match
    ///   the embedding count.
    ///
    /// - Complexity: O(n) where n is the number of chunks being added.
    ///
    /// ## Example
    /// ```swift
    /// let chunk = Chunk(
    ///     content: "Important document content...",
    ///     metadata: ChunkMetadata(documentId: "doc-123", index: 0)
    /// )
    /// let embedding = Embedding(vector: [0.1, 0.2, 0.3, ...])
    ///
    /// try await store.add([chunk], embeddings: [embedding])
    /// ```
    public func add(_ chunks: [Chunk], embeddings: [Embedding]) async throws {
        // Validate that counts match
        guard chunks.count == embeddings.count else {
            throw ZoniError.insertionFailed(
                reason: "Chunk count (\(chunks.count)) does not match embedding count (\(embeddings.count))"
            )
        }

        // Validate consistent dimensions across all embeddings
        if let firstDim = embeddings.first?.dimensions {
            for (index, embedding) in embeddings.enumerated() {
                guard embedding.dimensions == firstDim else {
                    throw ZoniError.insertionFailed(
                        reason: "Inconsistent embedding dimensions: index \(index) has \(embedding.dimensions), expected \(firstDim)"
                    )
                }
            }

            // Check against expected dimensions (set on first add)
            if let expectedDim = self.expectedDimensions {
                guard firstDim == expectedDim else {
                    throw ZoniError.insertionFailed(
                        reason: "Embedding dimensions (\(firstDim)) do not match expected dimensions (\(expectedDim))"
                    )
                }
            } else {
                // First add - set expected dimensions
                self.expectedDimensions = firstDim
            }
        }

        // Upsert: store by ID (replaces if exists)
        for (chunk, embedding) in zip(chunks, embeddings) {
            self.chunks[chunk.id] = chunk
            self.embeddings[chunk.id] = embedding
        }
    }

    /// Searches for chunks similar to the given query embedding.
    ///
    /// This method performs a brute-force similarity search using cosine
    /// similarity, comparing the query embedding against all stored embeddings.
    /// Results are sorted by similarity score in descending order (highest
    /// similarity first).
    ///
    /// - Parameters:
    ///   - query: The query embedding to search for similar vectors.
    ///   - limit: Maximum number of results to return. Must be positive.
    ///   - filter: Optional metadata filter to narrow the search scope.
    ///     Only chunks matching the filter will be considered.
    ///
    /// - Returns: An array of `RetrievalResult` objects sorted by relevance
    ///   score in descending order (most relevant first).
    ///
    /// - Complexity: O(m * d) where m is the number of stored chunks and d is
    ///   the embedding dimension.
    ///
    /// ## Example
    /// ```swift
    /// // Basic search
    /// let results = try await store.search(
    ///     query: queryEmbedding,
    ///     limit: 10,
    ///     filter: nil
    /// )
    ///
    /// // Search with metadata filter
    /// let filter = MetadataFilter.and([
    ///     .equals("documentId", "doc-123"),
    ///     .greaterThan("index", 5.0)
    /// ])
    /// let filteredResults = try await store.search(
    ///     query: queryEmbedding,
    ///     limit: 5,
    ///     filter: filter
    /// )
    /// ```
    public func search(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        // Collect all matching chunks with their similarity scores
        var results: [(chunk: Chunk, score: Float)] = []

        for (id, chunk) in chunks {
            // Check for task cancellation to support cooperative cancellation
            try Task.checkCancellation()

            // Apply filter if provided
            if let filter = filter, !filter.matches(chunk) {
                continue
            }

            // Get the embedding for this chunk
            guard let embedding = embeddings[id] else {
                continue
            }

            // Compute cosine similarity using SIMD-optimized VectorMath
            let score = VectorMath.cosineSimilarity(query.vector, embedding.vector)
            results.append((chunk, score))
        }

        // Sort by score descending (higher similarity = more relevant)
        results.sort { $0.score > $1.score }

        // Take the top N results
        let topResults = results.prefix(limit)

        // Convert to RetrievalResult objects
        return topResults.map { RetrievalResult(chunk: $0.chunk, score: $0.score) }
    }

    /// Deletes chunks with the specified IDs from the store.
    ///
    /// IDs that do not exist in the store are silently ignored. Both the chunk
    /// and its corresponding embedding are removed.
    ///
    /// - Parameter ids: The IDs of chunks to delete.
    ///
    /// - Complexity: O(k) where k is the number of IDs to delete.
    ///
    /// ## Example
    /// ```swift
    /// // Delete specific chunks by ID
    /// try await store.delete(ids: ["chunk-1", "chunk-2", "chunk-3"])
    /// ```
    public func delete(ids: [String]) async throws {
        for id in ids {
            chunks.removeValue(forKey: id)
            embeddings.removeValue(forKey: id)
        }
    }

    /// Deletes all chunks matching the specified metadata filter.
    ///
    /// This is useful for bulk deletion operations, such as removing all chunks
    /// from a specific document or clearing chunks with certain attributes.
    ///
    /// - Parameter filter: The metadata filter specifying which chunks to delete.
    ///
    /// - Complexity: O(m) where m is the total number of chunks (must evaluate
    ///   the filter against all chunks).
    ///
    /// ## Example
    /// ```swift
    /// // Delete all chunks from a specific document
    /// let filter = MetadataFilter.equals("documentId", "doc-to-remove")
    /// try await store.delete(filter: filter)
    ///
    /// // Delete chunks matching multiple criteria
    /// let complexFilter = MetadataFilter.and([
    ///     .equals("source", "outdated.txt"),
    ///     .lessThan("index", 10.0)
    /// ])
    /// try await store.delete(filter: complexFilter)
    /// ```
    public func delete(filter: MetadataFilter) async throws {
        // Find all chunk IDs that match the filter
        let idsToDelete = chunks.values
            .filter { filter.matches($0) }
            .map { $0.id }

        // Remove matched chunks and their embeddings
        for id in idsToDelete {
            chunks.removeValue(forKey: id)
            embeddings.removeValue(forKey: id)
        }
    }

    /// Returns the total number of chunks stored in the vector store.
    ///
    /// - Returns: The count of chunks currently in the store.
    ///
    /// - Complexity: O(1)
    ///
    /// ## Example
    /// ```swift
    /// let totalChunks = try await store.count()
    /// print("Store contains \(totalChunks) chunks")
    /// ```
    public func count() async throws -> Int {
        chunks.count
    }

    // MARK: - Persistence

    /// Saves the store contents to a URL as JSON.
    ///
    /// The data is saved in a human-readable JSON format with pretty printing.
    /// This includes all chunks and their embeddings, allowing full restoration
    /// of the store state via `load(from:)`.
    ///
    /// - Parameter url: The file URL to save to. Parent directories must exist.
    ///
    /// - Throws: An error if encoding fails or the file cannot be written.
    ///
    /// ## Example
    /// ```swift
    /// // Save to a file
    /// let saveURL = URL(fileURLWithPath: "/path/to/vector_store.json")
    /// try await store.save(to: saveURL)
    ///
    /// // Save to Documents directory
    /// let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    /// let storeURL = documents.appendingPathComponent("rag_store.json")
    /// try await store.save(to: storeURL)
    /// ```
    ///
    /// - Note: Large stores may produce large JSON files. Consider compression
    ///   for production use cases.
    public func save(to url: URL) async throws {
        let data = StorageData(
            chunks: Array(chunks.values),
            embeddings: embeddings
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let jsonData = try encoder.encode(data)
        try jsonData.write(to: url)
    }

    /// Loads store contents from a JSON file.
    ///
    /// This method replaces all current data in the store with the loaded data.
    /// The file must have been created by `save(to:)` or follow the same format.
    ///
    /// - Parameter url: The file URL to load from.
    ///
    /// - Throws: An error if the file cannot be read or the JSON is invalid.
    ///
    /// ## Example
    /// ```swift
    /// // Load from a file
    /// let store = InMemoryVectorStore()
    /// let loadURL = URL(fileURLWithPath: "/path/to/vector_store.json")
    /// try await store.load(from: loadURL)
    ///
    /// // Verify loaded data
    /// let count = try await store.count()
    /// print("Loaded \(count) chunks from disk")
    /// ```
    ///
    /// - Warning: This method replaces all existing data in the store. Any
    ///   unsaved changes will be lost.
    public func load(from url: URL) async throws {
        // Check file size before loading to prevent memory issues
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let fileSize = attributes[.size] as? Int, fileSize > Self.maxLoadFileSize {
            throw ZoniError.vectorStoreConnectionFailed(
                reason: "File too large (\(fileSize) bytes). Maximum allowed: \(Self.maxLoadFileSize) bytes"
            )
        }

        let jsonData = try Data(contentsOf: url)

        let decoder = JSONDecoder()
        let data = try decoder.decode(StorageData.self, from: jsonData)

        // Rebuild dictionaries from loaded data
        let loadedChunks = Dictionary(uniqueKeysWithValues: data.chunks.map { ($0.id, $0) })

        // Validate data consistency: every chunk must have a corresponding embedding
        for chunk in loadedChunks.values {
            guard data.embeddings[chunk.id] != nil else {
                throw ZoniError.invalidData(
                    reason: "Chunk '\(chunk.id)' has no corresponding embedding in loaded data"
                )
            }
        }

        // Check for orphaned embeddings (embeddings without chunks)
        for embeddingId in data.embeddings.keys {
            guard loadedChunks[embeddingId] != nil else {
                throw ZoniError.invalidData(
                    reason: "Embedding '\(embeddingId)' has no corresponding chunk in loaded data"
                )
            }
        }

        // Data is consistent, safe to assign
        self.chunks = loadedChunks
        self.embeddings = data.embeddings
    }

    /// Clears all data from the store.
    ///
    /// This removes all chunks and embeddings, returning the store to its
    /// initial empty state. This operation cannot be undone.
    ///
    /// ## Example
    /// ```swift
    /// // Clear the store
    /// await store.clear()
    ///
    /// // Verify the store is empty
    /// let isEmpty = try await store.isEmpty()
    /// assert(isEmpty) // true
    /// ```
    public func clear() async {
        chunks.removeAll()
        embeddings.removeAll()
    }

    // MARK: - Inspection Methods

    /// Returns all chunks currently stored.
    ///
    /// This is primarily useful for testing and debugging. For production
    /// use cases, prefer `search(query:limit:filter:)` for retrieval.
    ///
    /// - Returns: An array of all stored chunks.
    ///
    /// - Complexity: O(n) where n is the number of chunks.
    public func allChunks() async -> [Chunk] {
        Array(chunks.values)
    }

    /// Returns the embedding for a specific chunk ID.
    ///
    /// - Parameter id: The chunk ID to look up.
    /// - Returns: The embedding if found, or `nil` if the ID doesn't exist.
    ///
    /// - Complexity: O(1)
    public func embedding(for id: String) async -> Embedding? {
        embeddings[id]
    }

    /// Checks if a chunk with the given ID exists in the store.
    ///
    /// - Parameter id: The chunk ID to check.
    /// - Returns: `true` if a chunk with this ID exists, `false` otherwise.
    ///
    /// - Complexity: O(1)
    public func contains(id: String) async -> Bool {
        chunks[id] != nil
    }
}

// MARK: - Storage Data Structure

/// Internal data structure for JSON serialization of store contents.
///
/// This struct is `Codable` to enable saving and loading the store to/from
/// JSON files. It captures the complete state of an `InMemoryVectorStore`.
private struct StorageData: Codable {
    /// All chunks stored in the vector store.
    let chunks: [Chunk]

    /// Embeddings keyed by chunk ID.
    let embeddings: [String: Embedding]
}

// MARK: - CustomStringConvertible

extension InMemoryVectorStore: CustomStringConvertible {
    /// A textual representation of the store for debugging.
    nonisolated public var description: String {
        "InMemoryVectorStore(name: \"\(name)\")"
    }
}
