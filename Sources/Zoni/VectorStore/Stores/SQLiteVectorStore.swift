// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// SQLiteVectorStore.swift - A SQLite-based vector store for local persistence.

import Foundation
import SQLite

// MARK: - SQLiteVectorStore

/// A SQLite-based vector store for persistent local storage on Apple platforms.
///
/// `SQLiteVectorStore` uses SQLite for durable persistence, storing embeddings as binary
/// BLOBs for efficient storage. Similarity search is performed via brute-force cosine
/// similarity computation in Swift (SQLite has no native vector operations).
///
/// ## Use Cases
///
/// - **Local persistence**: Data survives app restarts without external databases
/// - **Offline-first apps**: Full functionality without network connectivity
/// - **Medium datasets**: Optimized for datasets up to ~100k vectors
/// - **iOS/macOS apps**: Native SQLite support on all Apple platforms
///
/// ## Thread Safety
///
/// This store is implemented as an `actor`, ensuring safe concurrent access from
/// multiple tasks. All database operations are serialized through the actor's
/// isolation, preventing data races and SQLite threading issues.
///
/// ## Performance Characteristics
///
/// - **Add**: O(n) where n is the number of chunks being added
/// - **Search**: O(m * d) where m is total chunks and d is embedding dimensions
///   (brute-force scan, as SQLite lacks native vector indexing)
/// - **Delete by ID**: O(k) where k is the number of IDs to delete
/// - **Delete by filter**: O(m) where m is total chunks (must load and filter all)
/// - **Count**: O(1) using SQLite's COUNT
///
/// For larger datasets (>100k vectors) or production workloads requiring sub-linear
/// search complexity, consider using PgVectorStore with proper HNSW indexing or
/// a dedicated vector database like Pinecone or Qdrant.
///
/// ## Database Schema
///
/// The store creates a single table with the following columns:
/// - `id` (TEXT PRIMARY KEY): Unique chunk identifier
/// - `content` (TEXT): The chunk's text content
/// - `embedding` (BLOB): Binary representation of the embedding vector
/// - `document_id` (TEXT): Parent document identifier (indexed)
/// - `chunk_index` (INTEGER): Position within the document (indexed)
/// - `start_offset` (INTEGER): Character start position in source document
/// - `end_offset` (INTEGER): Character end position in source document
/// - `source` (TEXT): Optional source file path or URL
/// - `custom_metadata` (BLOB): JSON-encoded custom metadata dictionary
/// - `created_at` (DATE): Timestamp when the chunk was added
///
/// ## Example Usage
///
/// ```swift
/// // Create a persistent store
/// let store = try SQLiteVectorStore(
///     path: "/path/to/vectors.db",
///     tableName: "embeddings",
///     dimensions: 1536  // OpenAI text-embedding-3-small
/// )
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
/// // Use an in-memory database for testing
/// let testStore = try SQLiteVectorStore(path: ":memory:")
/// ```
///
/// ## Memory Usage
///
/// During search operations, all embeddings are loaded into memory for similarity
/// computation. For very large datasets, consider:
/// - Using `limit` to reduce the result set
/// - Pre-filtering with metadata filters to reduce the search space
/// - Upgrading to a vector database with native similarity search
public actor SQLiteVectorStore: VectorStore {

    // MARK: - Properties

    /// The name identifier for this vector store implementation.
    ///
    /// This is used for logging, debugging, and configuration purposes.
    public nonisolated let name = "sqlite"

    /// The SQLite database connection.
    ///
    /// Marked as `nonisolated(unsafe)` because SQLite.Connection is not Sendable,
    /// but we ensure thread-safety by isolating all access through the actor.
    nonisolated(unsafe) private let connection: Connection

    /// The name of the table storing chunks and embeddings.
    private let tableName: String

    /// The expected embedding dimensions for validation.
    ///
    /// This is primarily used for documentation and debugging purposes.
    /// The store does not enforce dimension matching during operations.
    private let dimensions: Int

    /// The actual dimensions of embeddings stored in the database.
    ///
    /// This is set on the first `add()` call and validated on subsequent calls
    /// to ensure all embeddings have consistent dimensions.
    private var actualDimensions: Int?

    // MARK: - Table Definition

    /// The SQLite table expression for chunks.
    ///
    /// Marked as `nonisolated(unsafe)` because SQLite types are not Sendable,
    /// but they are immutable and safe to access.
    nonisolated(unsafe) private let chunksTable: Table

    // Column expressions
    // Marked as `nonisolated(unsafe)` because SQLite Expression types are not Sendable,
    // but they are immutable and safe to access.
    nonisolated(unsafe) private let idColumn = Expression<String>("id")
    nonisolated(unsafe) private let contentColumn = Expression<String>("content")
    nonisolated(unsafe) private let embeddingColumn = Expression<SQLite.Blob>("embedding")
    nonisolated(unsafe) private let documentIdColumn = Expression<String>("document_id")
    nonisolated(unsafe) private let chunkIndexColumn = Expression<Int>("chunk_index")
    nonisolated(unsafe) private let startOffsetColumn = Expression<Int>("start_offset")
    nonisolated(unsafe) private let endOffsetColumn = Expression<Int>("end_offset")
    nonisolated(unsafe) private let sourceColumn = Expression<String?>("source")
    nonisolated(unsafe) private let customMetadataColumn = Expression<SQLite.Blob>("custom_metadata")
    nonisolated(unsafe) private let createdAtColumn = Expression<Date>("created_at")

    // MARK: - Initialization

    /// Creates a new SQLite vector store.
    ///
    /// This initializer creates the database file (if it doesn't exist) and sets up
    /// the required schema including tables and indexes.
    ///
    /// - Parameters:
    ///   - path: Path to the SQLite database file. Special values:
    ///     - Use `":memory:"` for an in-memory database (useful for testing)
    ///     - Use `""` for a temporary database that's deleted on close
    ///   - tableName: Name of the table to store chunks (default: "zoni_chunks").
    ///     Use different table names to store multiple collections in one database.
    ///   - dimensions: Expected embedding dimensions (default: 1536 for OpenAI).
    ///     This is for documentation purposes and does not enforce constraints.
    ///
    /// - Throws: `ZoniError.vectorStoreConnectionFailed` if the database cannot be
    ///   opened or the schema cannot be created.
    ///
    /// ## Example
    /// ```swift
    /// // Persistent database
    /// let store = try SQLiteVectorStore(path: "/path/to/vectors.db")
    ///
    /// // In-memory for testing
    /// let testStore = try SQLiteVectorStore(path: ":memory:")
    ///
    /// // Custom table name for multiple collections
    /// let docsStore = try SQLiteVectorStore(
    ///     path: "/path/to/app.db",
    ///     tableName: "documents",
    ///     dimensions: 768  // sentence-transformers
    /// )
    /// ```
    public init(
        path: String,
        tableName: String = "zoni_chunks",
        dimensions: Int = 1536
    ) throws {
        // Validate table name - must start with letter and contain only alphanumeric/underscore
        guard !tableName.isEmpty,
              let first = tableName.first,
              first.isLetter,
              tableName.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            throw ZoniError.vectorStoreConnectionFailed(
                reason: "Invalid table name '\(tableName)': must start with a letter and contain only alphanumeric characters and underscores"
            )
        }

        // Validate dimensions
        guard dimensions > 0 else {
            throw ZoniError.vectorStoreConnectionFailed(
                reason: "Invalid dimensions: must be greater than 0"
            )
        }

        do {
            self.connection = try Connection(path)
        } catch {
            throw ZoniError.vectorStoreConnectionFailed(
                reason: "Failed to open SQLite database at '\(path)': \(error.localizedDescription)"
            )
        }

        self.tableName = tableName
        self.dimensions = dimensions
        self.chunksTable = Table(tableName)

        do {
            try createSchemaIfNeeded()
        } catch {
            throw ZoniError.vectorStoreConnectionFailed(
                reason: "Failed to create database schema: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Schema Setup

    /// Creates the database table and indexes if they don't exist.
    ///
    /// This method is called automatically during initialization and is idempotent.
    /// It creates:
    /// - The main chunks table with all required columns
    /// - An index on `document_id` for efficient document-based queries
    /// - An index on `chunk_index` for efficient ordering within documents
    nonisolated private func createSchemaIfNeeded() throws {
        // Create the main table
        try connection.run(chunksTable.create(ifNotExists: true) { table in
            table.column(idColumn, primaryKey: true)
            table.column(contentColumn)
            table.column(embeddingColumn)
            table.column(documentIdColumn)
            table.column(chunkIndexColumn)
            table.column(startOffsetColumn)
            table.column(endOffsetColumn)
            table.column(sourceColumn)
            table.column(customMetadataColumn)
            table.column(createdAtColumn)
        })

        // Create indexes for common query patterns
        // Index on document_id for filtering by document
        try connection.run(
            chunksTable.createIndex(documentIdColumn, ifNotExists: true)
        )

        // Index on chunk_index for ordering within documents
        try connection.run(
            chunksTable.createIndex(chunkIndexColumn, ifNotExists: true)
        )
    }

    // MARK: - VectorStore Protocol

    /// Adds chunks with their corresponding embeddings to the store.
    ///
    /// This method uses upsert semantics (INSERT OR REPLACE): if a chunk with the
    /// same ID already exists, it will be replaced with the new data. The operation
    /// is performed within a single transaction for atomicity.
    ///
    /// - Parameters:
    ///   - chunks: The chunks to store. Each chunk must have a unique ID.
    ///   - embeddings: Corresponding embeddings for each chunk. Must be in the
    ///     same order and have the same count as `chunks`.
    ///
    /// - Throws: `ZoniError.insertionFailed` if:
    ///   - The chunk count does not match the embedding count
    ///   - The custom metadata cannot be JSON-encoded
    ///   - The database operation fails
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

        // Validate embedding dimensions
        if let firstDim = embeddings.first?.dimensions {
            // Check against actual stored dimensions
            if let actual = actualDimensions {
                guard firstDim == actual else {
                    throw ZoniError.insertionFailed(
                        reason: "Embedding dimensions (\(firstDim)) do not match stored dimensions (\(actual))"
                    )
                }
            } else {
                // First add - set actual dimensions
                actualDimensions = firstDim
            }

            // Validate all embeddings have consistent dimensions and finite values
            for (index, embedding) in embeddings.enumerated() {
                guard embedding.dimensions == firstDim else {
                    throw ZoniError.insertionFailed(
                        reason: "Embedding \(index) has \(embedding.dimensions) dimensions, expected \(firstDim)"
                    )
                }

                guard embedding.hasFiniteValues() else {
                    throw ZoniError.insertionFailed(
                        reason: "Embedding \(index) contains non-finite values (NaN or Infinity)"
                    )
                }
            }
        }

        // Perform all insertions in a single transaction for atomicity
        do {
            try connection.transaction {
                for (chunk, embedding) in zip(chunks, embeddings) {
                    // Convert embedding vector to binary data
                    let embeddingData = embedding.vector.withUnsafeBytes { Data($0) }

                    // Encode custom metadata as JSON
                    let customData: Data
                    do {
                        customData = try JSONEncoder().encode(chunk.metadata.custom)
                    } catch {
                        throw ZoniError.insertionFailed(
                            reason: "Failed to encode custom metadata for chunk '\(chunk.id)': \(error.localizedDescription)"
                        )
                    }

                    // Insert or replace existing chunk with same ID
                    try self.connection.run(self.chunksTable.insert(or: .replace,
                        self.idColumn <- chunk.id,
                        self.contentColumn <- chunk.content,
                        self.embeddingColumn <- SQLite.Blob(bytes: [UInt8](embeddingData)),
                        self.documentIdColumn <- chunk.metadata.documentId,
                        self.chunkIndexColumn <- chunk.metadata.index,
                        self.startOffsetColumn <- chunk.metadata.startOffset,
                        self.endOffsetColumn <- chunk.metadata.endOffset,
                        self.sourceColumn <- chunk.metadata.source,
                        self.customMetadataColumn <- SQLite.Blob(bytes: [UInt8](customData)),
                        self.createdAtColumn <- Date()
                    ))
                }
            }
        } catch let error as ZoniError {
            throw error
        } catch {
            throw ZoniError.insertionFailed(
                reason: "Database transaction failed: \(error.localizedDescription)"
            )
        }
    }

    /// Searches for chunks similar to the given query embedding.
    ///
    /// This method performs a brute-force similarity search using cosine similarity,
    /// loading all stored embeddings and computing similarity scores in Swift.
    /// Results are sorted by similarity score in descending order (highest
    /// similarity first).
    ///
    /// Since SQLite has no native vector operations, all rows must be loaded and
    /// compared in memory. For large datasets, consider pre-filtering with metadata
    /// filters to reduce the search space.
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
    /// - Throws: `ZoniError.searchFailed` if the database query fails or
    ///   data cannot be decoded.
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
        // Validate limit parameter
        guard limit > 0 else {
            throw ZoniError.searchFailed(reason: "Limit must be greater than 0, got \(limit)")
        }

        // Validate query embedding dimensions
        guard query.dimensions == dimensions else {
            throw ZoniError.searchFailed(
                reason: "Query embedding has \(query.dimensions) dimensions, expected \(dimensions)"
            )
        }

        var results: [(chunk: Chunk, score: Float)] = []

        do {
            // Load all rows and compute similarity in Swift
            // (SQLite has no native vector operations)
            for row in try connection.prepare(chunksTable) {
                // Check for task cancellation to allow cooperative cancellation
                try Task.checkCancellation()

                // Parse the row into a Chunk
                let chunk: Chunk
                do {
                    chunk = try parseRowToChunk(row)
                } catch {
                    // Skip rows that can't be parsed (log in production)
                    continue
                }

                // Apply metadata filter if provided
                if let filter = filter, !filter.matches(chunk) {
                    continue
                }

                // Extract embedding and compute similarity
                let embedding = try parseRowToEmbedding(row)
                let score = VectorMath.cosineSimilarity(query.vector, embedding.vector)

                results.append((chunk, score))
            }
        } catch let error as ZoniError {
            throw error
        } catch {
            throw ZoniError.searchFailed(
                reason: "Database query failed: \(error.localizedDescription)"
            )
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
    /// IDs that do not exist in the store are silently ignored. The operation
    /// is performed as individual DELETE statements.
    ///
    /// - Parameter ids: The IDs of chunks to delete.
    ///
    /// - Throws: `ZoniError.insertionFailed` if a database operation fails.
    ///
    /// - Complexity: O(k) where k is the number of IDs to delete.
    ///
    /// ## Example
    /// ```swift
    /// // Delete specific chunks by ID
    /// try await store.delete(ids: ["chunk-1", "chunk-2", "chunk-3"])
    /// ```
    public func delete(ids: [String]) async throws {
        guard !ids.isEmpty else { return }

        do {
            try connection.transaction {
                for id in ids {
                    try self.connection.run(self.chunksTable.filter(self.idColumn == id).delete())
                }
            }
        } catch {
            throw ZoniError.insertionFailed(
                reason: "Failed to delete chunks: \(error.localizedDescription)"
            )
        }
    }

    /// Deletes all chunks matching the specified metadata filter.
    ///
    /// This method loads all chunks, evaluates the filter in Swift, and deletes
    /// matching chunks by ID. This is necessary because SQLite doesn't support
    /// complex JSON queries on the custom metadata column.
    ///
    /// - Parameter filter: The metadata filter specifying which chunks to delete.
    ///
    /// - Throws: `ZoniError.insertionFailed` if a database operation fails.
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
        // Collect IDs of chunks that match the filter
        var idsToDelete: [String] = []

        do {
            for row in try connection.prepare(chunksTable) {
                let chunk: Chunk
                do {
                    chunk = try parseRowToChunk(row)
                } catch {
                    // Skip rows that can't be parsed
                    continue
                }

                if filter.matches(chunk) {
                    idsToDelete.append(chunk.id)
                }
            }
        } catch {
            throw ZoniError.insertionFailed(
                reason: "Failed to query chunks for deletion: \(error.localizedDescription)"
            )
        }

        // Delete the matched chunks
        try await delete(ids: idsToDelete)
    }

    /// Returns the total number of chunks stored in the vector store.
    ///
    /// - Returns: The count of chunks currently in the store.
    ///
    /// - Throws: `ZoniError.searchFailed` if the count query fails.
    ///
    /// - Complexity: O(1) using SQLite's optimized COUNT.
    ///
    /// ## Example
    /// ```swift
    /// let totalChunks = try await store.count()
    /// print("Store contains \(totalChunks) chunks")
    /// ```
    public func count() async throws -> Int {
        do {
            return try connection.scalar(chunksTable.count)
        } catch {
            throw ZoniError.searchFailed(
                reason: "Failed to count chunks: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Row Parsing

    /// Parses a SQLite row into a Chunk object.
    ///
    /// - Parameter row: The database row to parse.
    /// - Returns: A Chunk object with all metadata populated.
    /// - Throws: An error if the custom metadata cannot be decoded from JSON.
    private func parseRowToChunk(_ row: Row) throws -> Chunk {
        // Decode custom metadata from JSON blob
        let customData = Data(row[customMetadataColumn].bytes)
        let custom = try JSONDecoder().decode([String: MetadataValue].self, from: customData)

        let metadata = ChunkMetadata(
            documentId: row[documentIdColumn],
            index: row[chunkIndexColumn],
            startOffset: row[startOffsetColumn],
            endOffset: row[endOffsetColumn],
            source: row[sourceColumn],
            custom: custom
        )

        return Chunk(
            id: row[idColumn],
            content: row[contentColumn],
            metadata: metadata
        )
    }

    /// Parses a SQLite row's embedding column into an Embedding object.
    ///
    /// - Parameter row: The database row to parse.
    /// - Returns: An Embedding object with the vector data.
    private func parseRowToEmbedding(_ row: Row) throws -> Embedding {
        let data = Data(row[embeddingColumn].bytes)

        // Convert binary data back to Float array
        let vector = data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }

        return Embedding(vector: vector, model: nil)
    }

    // MARK: - Additional Methods

    /// Retrieves a specific chunk by its ID.
    ///
    /// - Parameter id: The unique identifier of the chunk to retrieve.
    /// - Returns: The chunk if found, or `nil` if no chunk with that ID exists.
    ///
    /// - Throws: `ZoniError.searchFailed` if the database query fails.
    ///
    /// ## Example
    /// ```swift
    /// if let chunk = try await store.chunk(forId: "chunk-123") {
    ///     print("Found: \(chunk.content)")
    /// }
    /// ```
    public func chunk(forId id: String) async throws -> Chunk? {
        do {
            let query = chunksTable.filter(idColumn == id)
            guard let row = try connection.pluck(query) else {
                return nil
            }
            return try parseRowToChunk(row)
        } catch let error as DecodingError {
            throw ZoniError.searchFailed(
                reason: "Failed to decode chunk '\(id)': \(error.localizedDescription)"
            )
        } catch {
            throw ZoniError.searchFailed(
                reason: "Failed to retrieve chunk '\(id)': \(error.localizedDescription)"
            )
        }
    }

    /// Retrieves the embedding for a specific chunk by ID.
    ///
    /// - Parameter id: The unique identifier of the chunk.
    /// - Returns: The embedding if found, or `nil` if no chunk with that ID exists.
    ///
    /// - Throws: `ZoniError.searchFailed` if the database query fails.
    ///
    /// ## Example
    /// ```swift
    /// if let embedding = try await store.embedding(forId: "chunk-123") {
    ///     print("Dimensions: \(embedding.dimensions)")
    /// }
    /// ```
    public func embedding(forId id: String) async throws -> Embedding? {
        do {
            let query = chunksTable.filter(idColumn == id)
            guard let row = try connection.pluck(query) else {
                return nil
            }
            return try parseRowToEmbedding(row)
        } catch {
            throw ZoniError.searchFailed(
                reason: "Failed to retrieve embedding for chunk '\(id)': \(error.localizedDescription)"
            )
        }
    }

    /// Checks if a chunk with the given ID exists in the store.
    ///
    /// - Parameter id: The chunk ID to check.
    /// - Returns: `true` if a chunk with this ID exists, `false` otherwise.
    ///
    /// - Throws: `ZoniError.searchFailed` if the database query fails.
    ///
    /// - Complexity: O(1)
    ///
    /// ## Example
    /// ```swift
    /// if try await store.contains(id: "chunk-123") {
    ///     print("Chunk exists")
    /// }
    /// ```
    public func contains(id: String) async throws -> Bool {
        do {
            let query = chunksTable.filter(idColumn == id).count
            return try connection.scalar(query) > 0
        } catch {
            throw ZoniError.searchFailed(
                reason: "Failed to check for chunk '\(id)': \(error.localizedDescription)"
            )
        }
    }

    /// Returns all chunks from a specific document.
    ///
    /// Chunks are returned in order of their `index` within the document.
    ///
    /// - Parameter documentId: The document ID to filter by.
    /// - Returns: An array of chunks from the specified document, ordered by index.
    ///
    /// - Throws: `ZoniError.searchFailed` if the database query fails.
    ///
    /// ## Example
    /// ```swift
    /// let docChunks = try await store.chunks(forDocument: "doc-123")
    /// for chunk in docChunks {
    ///     print("[\(chunk.metadata.index)] \(chunk.content.prefix(50))...")
    /// }
    /// ```
    public func chunks(forDocument documentId: String) async throws -> [Chunk] {
        var results: [Chunk] = []

        do {
            let query = chunksTable
                .filter(documentIdColumn == documentId)
                .order(chunkIndexColumn.asc)

            for row in try connection.prepare(query) {
                let chunk = try parseRowToChunk(row)
                results.append(chunk)
            }
        } catch let error as DecodingError {
            throw ZoniError.searchFailed(
                reason: "Failed to decode chunks for document '\(documentId)': \(error.localizedDescription)"
            )
        } catch {
            throw ZoniError.searchFailed(
                reason: "Failed to retrieve chunks for document '\(documentId)': \(error.localizedDescription)"
            )
        }

        return results
    }

    /// Deletes all chunks from the store.
    ///
    /// This removes all data from the table but preserves the schema.
    ///
    /// - Throws: `ZoniError.insertionFailed` if the delete operation fails.
    ///
    /// ## Example
    /// ```swift
    /// try await store.clear()
    /// let isEmpty = try await store.isEmpty()
    /// assert(isEmpty) // true
    /// ```
    public func clear() async throws {
        do {
            try connection.run(chunksTable.delete())
        } catch {
            throw ZoniError.insertionFailed(
                reason: "Failed to clear store: \(error.localizedDescription)"
            )
        }
    }

    /// Returns a list of all unique document IDs in the store.
    ///
    /// - Returns: An array of unique document IDs.
    ///
    /// - Throws: `ZoniError.searchFailed` if the database query fails.
    ///
    /// ## Example
    /// ```swift
    /// let documents = try await store.allDocumentIds()
    /// print("Store contains \(documents.count) documents")
    /// ```
    public func allDocumentIds() async throws -> [String] {
        var documentIds: Set<String> = []

        do {
            let query = chunksTable.select(distinct: documentIdColumn)
            for row in try connection.prepare(query) {
                documentIds.insert(row[documentIdColumn])
            }
        } catch {
            throw ZoniError.searchFailed(
                reason: "Failed to retrieve document IDs: \(error.localizedDescription)"
            )
        }

        return Array(documentIds)
    }
}

// MARK: - CustomStringConvertible

extension SQLiteVectorStore: CustomStringConvertible {
    /// A textual representation of the store for debugging.
    nonisolated public var description: String {
        "SQLiteVectorStore(name: \"\(name)\", table: \"\(tableName)\")"
    }
}
