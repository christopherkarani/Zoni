// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// PgVectorStore.swift - PostgreSQL vector store with pgvector extension.

import Foundation
import PostgresNIO
import NIOCore
import NIOSSL
import Logging
import Zoni

// MARK: - ValidationError

/// Validation errors for SQL injection prevention.
private enum ValidationError: Error, LocalizedError {
    case invalidTableName(String)
    case invalidFieldName(String)

    var errorDescription: String? {
        switch self {
        case .invalidTableName(let name):
            return "Invalid table name '\(name)': must start with a letter and contain only alphanumeric characters and underscores"
        case .invalidFieldName(let name):
            return "Invalid field name '\(name)': must contain only alphanumeric characters and underscores"
        }
    }
}

// MARK: - PgVectorStore

/// A PostgreSQL vector store using the pgvector extension for server-side applications.
///
/// `PgVectorStore` is the recommended production vector store for server-side Swift applications.
/// It leverages PostgreSQL's pgvector extension to provide native vector operations and indexing,
/// enabling efficient similarity search at scale.
///
/// ## Prerequisites
///
/// Before using this store, ensure your PostgreSQL database is properly configured:
///
/// 1. **PostgreSQL 15+** with pgvector extension installed
/// 2. Run `CREATE EXTENSION IF NOT EXISTS vector;` on your database
///
/// ## Index Types
///
/// pgvector supports multiple index types for different use cases:
///
/// - **IVFFlat** (default): Inverted File with Flat quantization
///   - Faster to build, good recall
///   - Best for frequently updated data or smaller datasets
///   - Recommended for < 1M vectors
///
/// - **HNSW**: Hierarchical Navigable Small World
///   - Higher recall, slower to build
///   - Best for read-heavy workloads
///   - Recommended for larger datasets requiring highest accuracy
///
/// - **None**: Brute-force search without indexing
///   - Exact results but O(n) search time
///   - Only suitable for very small datasets (< 10k vectors)
///
/// ## Database Schema
///
/// The store creates a table with the following structure:
/// ```sql
/// CREATE TABLE zoni_chunks (
///     id TEXT PRIMARY KEY,
///     content TEXT NOT NULL,
///     embedding vector(1536),
///     document_id TEXT NOT NULL,
///     chunk_index INTEGER NOT NULL,
///     start_offset INTEGER DEFAULT 0,
///     end_offset INTEGER DEFAULT 0,
///     source TEXT,
///     metadata JSONB DEFAULT '{}',
///     created_at TIMESTAMPTZ DEFAULT NOW()
/// );
/// ```
///
/// ## Thread Safety
///
/// This store is implemented as an `actor`, ensuring safe concurrent access from
/// multiple tasks. All database operations are serialized through the actor's
/// isolation.
///
/// ## Performance Characteristics
///
/// - **Add**: O(n) where n is the number of chunks being added
/// - **Search with index**: O(log n) with IVFFlat or HNSW
/// - **Search without index**: O(n * d) brute-force scan
/// - **Delete by ID**: O(1) per ID with primary key index
/// - **Delete by filter**: Depends on filter complexity and indexes
/// - **Count**: O(1) using PostgreSQL's optimized count
///
/// ## Example Usage
///
/// ```swift
/// // Connect using a connection string
/// let store = try await PgVectorStore.connect(
///     connectionString: "postgres://user:pass@localhost:5432/mydb",
///     configuration: PgVectorStore.Configuration(
///         tableName: "embeddings",
///         dimensions: 1536,
///         indexType: .hnsw
///     ),
///     eventLoopGroup: eventLoopGroup
/// )
///
/// // Add chunks with embeddings
/// let chunks = [
///     Chunk(content: "Swift is a powerful language...",
///           metadata: ChunkMetadata(documentId: "doc1", index: 0))
/// ]
/// let embeddings = try await embedder.embed(chunks.map { $0.content })
/// try await store.add(chunks, embeddings: embeddings)
///
/// // Search for similar chunks
/// let queryEmbedding = try await embedder.embed("How does Swift work?")
/// let results = try await store.search(query: queryEmbedding, limit: 5, filter: nil)
///
/// for result in results {
///     print("Score: \(result.score), Content: \(result.chunk.content)")
/// }
/// ```
///
/// ## Error Handling
///
/// The store throws `ZoniError` for all operations:
/// - `ZoniError.vectorStoreConnectionFailed` - Connection issues
/// - `ZoniError.insertionFailed` - Insert/update failures
/// - `ZoniError.searchFailed` - Search query failures
public actor PgVectorStore: VectorStore {

    // MARK: - Properties

    /// The name identifier for this vector store implementation.
    ///
    /// Used for logging, debugging, and configuration purposes.
    public nonisolated let name = "pgvector"

    /// The PostgreSQL connection used for all database operations.
    private let connection: PostgresConnection

    /// Configuration settings for the vector store.
    private let configuration: Configuration

    /// Logger for diagnostic output.
    private let logger: Logger

    // MARK: - Nested Types

    /// Index types supported by pgvector.
    ///
    /// Each index type has different performance characteristics for build time,
    /// search speed, and recall accuracy.
    public enum IndexType: String, Sendable {
        /// No index (brute-force exact search).
        ///
        /// - Pros: Exact results, no index build time
        /// - Cons: O(n) search complexity
        /// - Use case: Very small datasets (< 10k vectors)
        case none

        /// Inverted File with Flat quantization.
        ///
        /// - Pros: Faster to build, good balance of speed/accuracy
        /// - Cons: Lower recall than HNSW for large datasets
        /// - Use case: Frequently updated data, < 1M vectors
        case ivfflat

        /// Hierarchical Navigable Small World graph.
        ///
        /// - Pros: Highest recall, fast search
        /// - Cons: Slower to build, more memory usage
        /// - Use case: Read-heavy workloads, large datasets
        case hnsw
    }

    /// Configuration for the PgVectorStore.
    ///
    /// Customize table name, dimensions, index type, and index-specific parameters
    /// to match your use case.
    public struct Configuration: Sendable {
        /// The name of the database table to store chunks.
        ///
        /// Default: "zoni_chunks"
        public let tableName: String

        /// The number of dimensions in embedding vectors.
        ///
        /// Must match your embedding model's output dimensions:
        /// - OpenAI text-embedding-3-small: 1536
        /// - OpenAI text-embedding-3-large: 3072
        /// - Cohere embed-english-v3.0: 1024
        /// - Sentence Transformers (all-MiniLM-L6-v2): 384
        ///
        /// Default: 1536
        public let dimensions: Int

        /// The type of vector index to create.
        ///
        /// Default: .ivfflat
        public let indexType: IndexType

        /// Number of lists for IVFFlat index.
        ///
        /// Higher values = faster search but lower recall.
        /// Rule of thumb: sqrt(rows) to rows/1000 for good balance.
        ///
        /// Default: 100
        public let ivfflatLists: Int

        /// Maximum connections per layer for HNSW index (m parameter).
        ///
        /// Higher values = better recall but more memory/slower builds.
        /// Recommended: 12-48, higher for higher-dimensional vectors.
        ///
        /// Default: 16
        public let hnswM: Int

        /// Size of dynamic candidate list for HNSW construction.
        ///
        /// Higher values = better index quality but slower builds.
        /// Recommended: 64-200.
        ///
        /// Default: 64
        public let hnswEfConstruction: Int

        /// Creates a new configuration with the specified parameters.
        ///
        /// - Parameters:
        ///   - tableName: Database table name. Default: "zoni_chunks"
        ///   - dimensions: Vector dimensions. Default: 1536
        ///   - indexType: Index type to use. Default: .ivfflat
        ///   - ivfflatLists: IVFFlat lists parameter. Default: 100
        ///   - hnswM: HNSW m parameter. Default: 16
        ///   - hnswEfConstruction: HNSW ef_construction parameter. Default: 64
        ///
        /// - Precondition: The table name must start with a letter and contain only alphanumeric
        ///   characters and underscores.
        public init(
            tableName: String = "zoni_chunks",
            dimensions: Int = 1536,
            indexType: IndexType = .ivfflat,
            ivfflatLists: Int = 100,
            hnswM: Int = 16,
            hnswEfConstruction: Int = 64
        ) {
            // Validate table name to prevent SQL injection
            precondition(
                !tableName.isEmpty &&
                tableName.first?.isLetter == true &&
                tableName.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
                "Invalid table name '\(tableName)': must start with a letter and contain only alphanumeric characters and underscores"
            )
            self.tableName = tableName
            self.dimensions = dimensions
            self.indexType = indexType
            self.ivfflatLists = ivfflatLists
            self.hnswM = hnswM
            self.hnswEfConstruction = hnswEfConstruction
        }

        /// Creates a validated configuration, returning nil if validation fails.
        ///
        /// Use this initializer when the table name comes from user input and you want
        /// to handle invalid names gracefully rather than crashing.
        ///
        /// - Parameters:
        ///   - tableName: Database table name (must be valid SQL identifier)
        ///   - dimensions: Vector dimensions
        ///   - indexType: Index type to use
        /// - Returns: A valid configuration, or nil if the table name is invalid.
        public static func validated(
            tableName: String,
            dimensions: Int = 1536,
            indexType: IndexType = .ivfflat,
            ivfflatLists: Int = 100,
            hnswM: Int = 16,
            hnswEfConstruction: Int = 64
        ) -> Configuration? {
            guard !tableName.isEmpty,
                  let first = tableName.first,
                  first.isLetter,
                  tableName.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
                return nil
            }
            return Configuration(
                tableName: tableName,
                dimensions: dimensions,
                indexType: indexType,
                ivfflatLists: ivfflatLists,
                hnswM: hnswM,
                hnswEfConstruction: hnswEfConstruction
            )
        }
    }

    // MARK: - PostgreSQL Error Types

    /// PostgreSQL-specific error codes for detailed error handling.
    private enum PostgresErrorCode {
        static let undefinedTable = "42P01"
        static let duplicateTable = "42P07"
        static let undefinedFunction = "42883"
        static let invalidTextRepresentation = "22P02"
        static let uniqueViolation = "23505"
        static let connectionFailure = "08006"
        static let connectionDoesNotExist = "08003"
    }

    // MARK: - Initialization

    /// Creates a PgVectorStore with an existing PostgreSQL connection.
    ///
    /// Use this initializer when you already have a PostgresConnection from
    /// your application's connection pool or when managing connections manually.
    ///
    /// - Parameters:
    ///   - connection: An active PostgresConnection
    ///   - configuration: Store configuration settings
    ///   - createTable: If true, creates the table and indexes if they don't exist.
    ///     Set to false if the schema already exists. Default: true
    ///
    /// - Throws: `ZoniError.vectorStoreConnectionFailed` if:
    ///   - The pgvector extension cannot be enabled
    ///   - The table schema cannot be created
    ///   - Index creation fails
    ///
    /// ## Example
    /// ```swift
    /// // Using an existing connection from a pool
    /// let connection = try await pool.getConnection()
    /// let store = try await PgVectorStore(
    ///     connection: connection,
    ///     configuration: Configuration(dimensions: 768),
    ///     createTable: true
    /// )
    /// ```
    public init(
        connection: PostgresConnection,
        configuration: Configuration = Configuration(),
        createTable: Bool = true
    ) async throws {
        self.connection = connection
        self.configuration = configuration
        self.logger = Logger(label: "zoni.pgvector")

        if createTable {
            try await createTableIfNeeded()
        }
    }

    /// TLS configuration options for PostgreSQL connections.
    ///
    /// Controls how TLS/SSL is negotiated with the PostgreSQL server.
    public enum TLSMode: Sendable {
        /// Disable TLS entirely (not recommended for production).
        case disable
        /// Prefer TLS but fall back to unencrypted if unavailable (default).
        case prefer
        /// Require TLS - fail if not available.
        case require
    }

    /// Connects to PostgreSQL and creates a PgVectorStore.
    ///
    /// This is a convenience method that handles connection setup. For production
    /// use, consider using a connection pool and the `init(connection:)` initializer.
    ///
    /// - Parameters:
    ///   - connectionString: PostgreSQL connection string in URL format.
    ///     Format: `postgres://username:password@host:port/database`
    ///   - configuration: Store configuration settings
    ///   - eventLoopGroup: NIO EventLoopGroup to use for the connection
    ///   - tlsMode: TLS configuration for the connection. Default: `.prefer`
    ///
    /// - Returns: A configured PgVectorStore ready for use
    ///
    /// - Throws: `ZoniError.vectorStoreConnectionFailed` if:
    ///   - The connection string is invalid
    ///   - The database is unreachable
    ///   - Authentication fails
    ///   - Schema creation fails
    ///
    /// ## Example
    /// ```swift
    /// let store = try await PgVectorStore.connect(
    ///     connectionString: "postgres://user:pass@localhost:5432/mydb",
    ///     configuration: Configuration(indexType: .hnsw),
    ///     eventLoopGroup: MultiThreadedEventLoopGroup(numberOfThreads: 1)
    /// )
    /// ```
    public static func connect(
        connectionString: String,
        configuration: Configuration = Configuration(),
        eventLoopGroup: EventLoopGroup,
        tlsMode: TLSMode = .prefer
    ) async throws -> PgVectorStore {
        let host = parseHost(connectionString)
        let port = parsePort(connectionString)
        let username = parseUsername(connectionString)
        let password = parsePassword(connectionString)
        let database = parseDatabase(connectionString)

        // Convert TLSMode to PostgresConnection.Configuration.TLS
        let tls: PostgresConnection.Configuration.TLS
        switch tlsMode {
        case .disable:
            tls = .disable
        case .prefer:
            tls = .prefer(try .init(configuration: .clientDefault))
        case .require:
            tls = .require(try .init(configuration: .clientDefault))
        }

        let config = PostgresConnection.Configuration(
            host: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: tls
        )

        let logger = Logger(label: "zoni.pgvector")

        let connection: PostgresConnection
        do {
            connection = try await PostgresConnection.connect(
                configuration: config,
                id: 1,
                logger: logger
            )
        } catch {
            throw ZoniError.vectorStoreConnectionFailed(
                reason: "Failed to connect to PostgreSQL at \(host):\(port): \(error.localizedDescription)"
            )
        }

        return try await PgVectorStore(connection: connection, configuration: configuration)
    }

    // MARK: - Schema Management

    /// Creates the database table and indexes if they don't exist.
    ///
    /// This method is called automatically during initialization when `createTable`
    /// is true. It is idempotent and safe to call multiple times.
    ///
    /// The method performs the following operations:
    /// 1. Enables the pgvector extension
    /// 2. Creates the chunks table with all required columns
    /// 3. Creates the document_id index
    /// 4. Creates the vector similarity index (IVFFlat or HNSW)
    private func createTableIfNeeded() async throws {
        // Enable pgvector extension
        do {
            try await connection.query("CREATE EXTENSION IF NOT EXISTS vector", logger: logger)
        } catch {
            throw ZoniError.vectorStoreConnectionFailed(
                reason: "Failed to enable pgvector extension. Ensure pgvector is installed: \(error.localizedDescription)"
            )
        }

        // Create the chunks table
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS \(configuration.tableName) (
            id TEXT PRIMARY KEY,
            content TEXT NOT NULL,
            embedding vector(\(configuration.dimensions)),
            document_id TEXT NOT NULL,
            chunk_index INTEGER NOT NULL,
            start_offset INTEGER DEFAULT 0,
            end_offset INTEGER DEFAULT 0,
            source TEXT,
            metadata JSONB DEFAULT '{}',
            created_at TIMESTAMPTZ DEFAULT NOW()
        )
        """

        do {
            try await connection.query(PostgresQuery(unsafeSQL: createTableSQL), logger: logger)
        } catch {
            throw ZoniError.vectorStoreConnectionFailed(
                reason: "Failed to create table '\(configuration.tableName)': \(error.localizedDescription)"
            )
        }

        // Create document_id index for efficient filtering
        let documentIdIndexSQL = """
        CREATE INDEX IF NOT EXISTS \(configuration.tableName)_document_id_idx
        ON \(configuration.tableName) (document_id)
        """

        do {
            try await connection.query(PostgresQuery(unsafeSQL: documentIdIndexSQL), logger: logger)
        } catch {
            throw ZoniError.vectorStoreConnectionFailed(
                reason: "Failed to create document_id index: \(error.localizedDescription)"
            )
        }

        // Create vector similarity index based on configuration
        try await createVectorIndex()
    }

    /// Creates the vector similarity index based on the configured index type.
    ///
    /// This method creates either an IVFFlat or HNSW index, or does nothing
    /// if the index type is `.none`.
    private func createVectorIndex() async throws {
        let indexName = "\(configuration.tableName)_embedding_idx"

        switch configuration.indexType {
        case .none:
            // No index - brute-force search
            logger.info("Using brute-force search (no vector index)")
            return

        case .ivfflat:
            let createIndexSQL = """
            CREATE INDEX IF NOT EXISTS \(indexName) ON \(configuration.tableName)
            USING ivfflat (embedding vector_cosine_ops)
            WITH (lists = \(configuration.ivfflatLists))
            """

            do {
                try await connection.query(PostgresQuery(unsafeSQL: createIndexSQL), logger: logger)
                logger.info("Created IVFFlat index with \(configuration.ivfflatLists) lists")
            } catch {
                throw ZoniError.vectorStoreConnectionFailed(
                    reason: "Failed to create IVFFlat index: \(error.localizedDescription)"
                )
            }

        case .hnsw:
            let createIndexSQL = """
            CREATE INDEX IF NOT EXISTS \(indexName) ON \(configuration.tableName)
            USING hnsw (embedding vector_cosine_ops)
            WITH (m = \(configuration.hnswM), ef_construction = \(configuration.hnswEfConstruction))
            """

            do {
                try await connection.query(PostgresQuery(unsafeSQL: createIndexSQL), logger: logger)
                logger.info("Created HNSW index with m=\(configuration.hnswM), ef_construction=\(configuration.hnswEfConstruction)")
            } catch {
                throw ZoniError.vectorStoreConnectionFailed(
                    reason: "Failed to create HNSW index: \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - VectorStore Protocol Implementation

    /// Adds chunks with their corresponding embeddings to the store.
    ///
    /// This method uses upsert semantics (INSERT ... ON CONFLICT DO UPDATE):
    /// if a chunk with the same ID already exists, it will be replaced with
    /// the new data.
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
    /// let chunks = [
    ///     Chunk(content: "Important content...",
    ///           metadata: ChunkMetadata(documentId: "doc-1", index: 0))
    /// ]
    /// let embeddings = [Embedding(vector: [0.1, 0.2, ...])]
    ///
    /// try await store.add(chunks, embeddings: embeddings)
    /// ```
    public func add(_ chunks: [Chunk], embeddings: [Embedding]) async throws {
        guard chunks.count == embeddings.count else {
            throw ZoniError.insertionFailed(
                reason: "Chunk count (\(chunks.count)) does not match embedding count (\(embeddings.count))"
            )
        }

        guard !chunks.isEmpty else {
            return // Nothing to add
        }

        for (chunk, embedding) in zip(chunks, embeddings) {
            // Validate embedding dimensions
            guard embedding.dimensions == configuration.dimensions else {
                throw ZoniError.insertionFailed(
                    reason: "Embedding dimension mismatch for chunk '\(chunk.id)': expected \(configuration.dimensions), got \(embedding.dimensions)"
                )
            }

            // Validate that all values are finite (not NaN or Infinity)
            guard embedding.hasFiniteValues() else {
                throw ZoniError.insertionFailed(
                    reason: "Embedding for chunk '\(chunk.id)' contains non-finite values (NaN or Infinity)"
                )
            }

            // Encode custom metadata as JSON
            let customJSON: String
            do {
                let customData = try JSONEncoder().encode(chunk.metadata.custom)
                customJSON = String(data: customData, encoding: .utf8) ?? "{}"
            } catch {
                throw ZoniError.insertionFailed(
                    reason: "Failed to encode custom metadata for chunk '\(chunk.id)': \(error.localizedDescription)"
                )
            }

            // Format vector as pgvector string: '[0.1,0.2,0.3,...]'
            let vectorString = "[\(embedding.vector.map { String($0) }.joined(separator: ","))]"

            // Build upsert query
            let upsertSQL = """
            INSERT INTO \(configuration.tableName)
            (id, content, embedding, document_id, chunk_index, start_offset, end_offset, source, metadata)
            VALUES ($1, $2, $3::vector, $4, $5, $6, $7, $8, $9::jsonb)
            ON CONFLICT (id) DO UPDATE SET
                content = EXCLUDED.content,
                embedding = EXCLUDED.embedding,
                document_id = EXCLUDED.document_id,
                chunk_index = EXCLUDED.chunk_index,
                start_offset = EXCLUDED.start_offset,
                end_offset = EXCLUDED.end_offset,
                source = EXCLUDED.source,
                metadata = EXCLUDED.metadata,
                created_at = NOW()
            """

            do {
                try await connection.query(
                    PostgresQuery(
                        unsafeSQL: upsertSQL,
                        binds: PostgresBindings(
                            encodable: [
                                chunk.id,
                                chunk.content,
                                vectorString,
                                chunk.metadata.documentId,
                                chunk.metadata.index,
                                chunk.metadata.startOffset,
                                chunk.metadata.endOffset,
                                chunk.metadata.source ?? "",
                                customJSON
                            ]
                        )
                    ),
                    logger: logger
                )
            } catch {
                throw ZoniError.insertionFailed(
                    reason: "Failed to insert chunk '\(chunk.id)': \(error.localizedDescription)"
                )
            }
        }
    }

    /// Searches for chunks similar to the given query embedding.
    ///
    /// This method uses pgvector's cosine distance operator (`<=>`) for similarity
    /// search. Results are ranked by similarity score in descending order (most
    /// similar first).
    ///
    /// The similarity score is computed as `1 - cosine_distance`, giving values
    /// in the range [0, 2] where higher values indicate greater similarity.
    ///
    /// - Parameters:
    ///   - query: The query embedding to search for similar vectors.
    ///   - limit: Maximum number of results to return. Must be positive.
    ///   - filter: Optional metadata filter to narrow the search scope.
    ///
    /// - Returns: An array of `RetrievalResult` objects sorted by relevance
    ///   score in descending order (most relevant first).
    ///
    /// - Throws: `ZoniError.searchFailed` if the database query fails.
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
    /// let filter = MetadataFilter.equals("documentId", "doc-123")
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

        // Validate query dimensions
        guard query.dimensions == configuration.dimensions else {
            throw ZoniError.searchFailed(
                reason: "Query embedding dimension mismatch: expected \(configuration.dimensions), got \(query.dimensions)"
            )
        }

        let vectorString = "[\(query.vector.map { String($0) }.joined(separator: ","))]"

        // Build WHERE clause from filter
        var whereClause = ""
        if let filter = filter {
            let filterSQL = buildFilterSQL(filter)
            if !filterSQL.isEmpty {
                whereClause = "WHERE \(filterSQL)"
            }
        }

        // Use cosine distance: 1 - cosine_distance for similarity score
        // pgvector's <=> operator returns cosine distance (0 = identical, 2 = opposite)
        let searchSQL = """
        SELECT id, content, document_id, chunk_index, start_offset, end_offset, source, metadata::text,
               1 - (embedding <=> $1::vector) AS score
        FROM \(configuration.tableName)
        \(whereClause)
        ORDER BY embedding <=> $1::vector
        LIMIT $2
        """

        do {
            let rows = try await connection.query(
                PostgresQuery(
                    unsafeSQL: searchSQL,
                    binds: PostgresBindings(encodable: [vectorString, limit])
                ),
                logger: logger
            )

            var results: [RetrievalResult] = []

            for try await row in rows {
                do {
                    let (chunk, score) = try decodeSearchResultRow(row)
                    results.append(RetrievalResult(chunk: chunk, score: score))
                } catch {
                    // Log and skip malformed rows
                    logger.warning("Failed to decode search result row: \(error)")
                    continue
                }
            }

            return results
        } catch let error as ZoniError {
            throw error
        } catch {
            throw ZoniError.searchFailed(
                reason: "Database search query failed: \(error.localizedDescription)"
            )
        }
    }

    /// Decodes a search result row into a Chunk and score.
    ///
    /// The row must contain columns: id, content, document_id, chunk_index,
    /// start_offset, end_offset, source, metadata, score
    private func decodeSearchResultRow(_ row: PostgresRow) throws -> (Chunk, Float) {
        // Decode all columns including score as a tuple
        let (id, content, documentId, chunkIndex, startOffset, endOffset, source, metadataJSON, score) = try row.decode(
            (String, String, String, Int, Int, Int, String?, String, Float).self,
            context: .default
        )

        // Decode custom metadata from JSON
        var custom: [String: MetadataValue] = [:]
        if let metadataData = metadataJSON.data(using: .utf8) {
            do {
                custom = try JSONDecoder().decode([String: MetadataValue].self, from: metadataData)
            } catch {
                logger.warning("Failed to decode metadata JSON for chunk '\(id)': \(error)")
            }
        }

        let metadata = ChunkMetadata(
            documentId: documentId,
            index: chunkIndex,
            startOffset: startOffset,
            endOffset: endOffset,
            source: source,
            custom: custom
        )

        let chunk = Chunk(id: id, content: content, metadata: metadata)
        return (chunk, score)
    }

    /// Deletes chunks with the specified IDs from the store.
    ///
    /// IDs that do not exist in the store are silently ignored.
    ///
    /// - Parameter ids: The IDs of chunks to delete.
    ///
    /// - Throws: `ZoniError.insertionFailed` if the database operation fails.
    ///
    /// - Complexity: O(k) where k is the number of IDs to delete.
    ///
    /// ## Example
    /// ```swift
    /// try await store.delete(ids: ["chunk-1", "chunk-2", "chunk-3"])
    /// ```
    public func delete(ids: [String]) async throws {
        guard !ids.isEmpty else {
            return
        }

        // Use batch deletion with IN clause for better performance
        let placeholders = (1...ids.count).map { "$\($0)" }.joined(separator: ", ")
        let deleteSQL = "DELETE FROM \(configuration.tableName) WHERE id IN (\(placeholders))"

        do {
            try await connection.query(
                PostgresQuery(unsafeSQL: deleteSQL, binds: PostgresBindings(encodable: ids)),
                logger: logger
            )
        } catch {
            throw ZoniError.insertionFailed(
                reason: "Failed to delete \(ids.count) chunks: \(error.localizedDescription)"
            )
        }
    }

    /// Deletes all chunks matching the specified metadata filter.
    ///
    /// This is useful for bulk deletion operations, such as removing all
    /// chunks from a specific document.
    ///
    /// - Parameter filter: The metadata filter specifying which chunks to delete.
    ///
    /// - Throws: `ZoniError.insertionFailed` if the database operation fails.
    ///
    /// ## Example
    /// ```swift
    /// // Delete all chunks from a specific document
    /// let filter = MetadataFilter.equals("documentId", "doc-to-remove")
    /// try await store.delete(filter: filter)
    /// ```
    public func delete(filter: MetadataFilter) async throws {
        let filterSQL = buildFilterSQL(filter)
        guard !filterSQL.isEmpty else {
            throw ZoniError.insertionFailed(
                reason: "Cannot delete with empty filter - this would delete all records"
            )
        }

        let deleteSQL = "DELETE FROM \(configuration.tableName) WHERE \(filterSQL)"

        do {
            try await connection.query(PostgresQuery(unsafeSQL: deleteSQL), logger: logger)
        } catch {
            throw ZoniError.insertionFailed(
                reason: "Failed to delete chunks with filter: \(error.localizedDescription)"
            )
        }
    }

    /// Returns the total number of chunks stored in the vector store.
    ///
    /// - Returns: The count of chunks currently in the store.
    ///
    /// - Throws: `ZoniError.searchFailed` if the count query fails.
    ///
    /// - Complexity: O(1) using PostgreSQL's optimized count.
    public func count() async throws -> Int {
        let countSQL = "SELECT COUNT(*) FROM \(configuration.tableName)"

        do {
            let rows = try await connection.query(PostgresQuery(unsafeSQL: countSQL), logger: logger)

            for try await row in rows {
                return try row.decode(Int.self, context: .default)
            }

            return 0
        } catch {
            throw ZoniError.searchFailed(
                reason: "Failed to count chunks: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Maintenance Operations

    /// Runs VACUUM ANALYZE on the chunks table.
    ///
    /// This reclaims storage space from deleted rows and updates table statistics
    /// for the query planner. Run periodically after bulk deletes or updates.
    ///
    /// - Note: This operation may take time on large tables and acquires locks.
    ///
    /// - Throws: `ZoniError.insertionFailed` if the vacuum operation fails.
    public func vacuum() async throws {
        let vacuumSQL = "VACUUM ANALYZE \(configuration.tableName)"

        do {
            try await connection.query(PostgresQuery(unsafeSQL: vacuumSQL), logger: logger)
            logger.info("Completed VACUUM ANALYZE on \(configuration.tableName)")
        } catch {
            throw ZoniError.insertionFailed(
                reason: "Failed to vacuum table: \(error.localizedDescription)"
            )
        }
    }

    /// Rebuilds the vector index.
    ///
    /// This can improve search performance after significant data changes.
    /// The operation blocks writes to the index during rebuild.
    ///
    /// - Throws: `ZoniError.insertionFailed` if the reindex operation fails.
    public func reindex() async throws {
        guard configuration.indexType != .none else {
            logger.info("No vector index to rebuild (index type is none)")
            return
        }

        let indexName = "\(configuration.tableName)_embedding_idx"
        let reindexSQL = "REINDEX INDEX \(indexName)"

        do {
            try await connection.query(PostgresQuery(unsafeSQL: reindexSQL), logger: logger)
            logger.info("Rebuilt index \(indexName)")
        } catch {
            throw ZoniError.insertionFailed(
                reason: "Failed to rebuild index: \(error.localizedDescription)"
            )
        }
    }

    /// Deletes all chunks from the store.
    ///
    /// This removes all data from the table but preserves the schema and indexes.
    ///
    /// - Throws: `ZoniError.insertionFailed` if the truncate operation fails.
    public func clear() async throws {
        let truncateSQL = "TRUNCATE TABLE \(configuration.tableName)"

        do {
            try await connection.query(PostgresQuery(unsafeSQL: truncateSQL), logger: logger)
            logger.info("Cleared all data from \(configuration.tableName)")
        } catch {
            throw ZoniError.insertionFailed(
                reason: "Failed to clear table: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Filter SQL Generation

    /// Builds a SQL WHERE clause from a MetadataFilter.
    private func buildFilterSQL(_ filter: MetadataFilter) -> String {
        let clauses = filter.conditions.map { conditionToSQL($0) }
        return clauses.joined(separator: " AND ")
    }

    /// Converts a single filter condition to SQL.
    ///
    /// Field names are validated to prevent SQL injection. Invalid field names
    /// result in a `TRUE` condition (no filtering) to fail safely.
    private func conditionToSQL(_ condition: MetadataFilter.Operator) -> String {
        switch condition {
        case .equals(let field, let value):
            guard isValidFieldName(field) else { return "TRUE" }
            if isReservedField(field) {
                return "\(sqlFieldName(field)) = \(sqlValue(value))"
            }
            return "metadata->>'\(escapeString(field))' = \(sqlTextValue(value))"

        case .notEquals(let field, let value):
            guard isValidFieldName(field) else { return "TRUE" }
            if isReservedField(field) {
                return "\(sqlFieldName(field)) != \(sqlValue(value))"
            }
            return "metadata->>'\(escapeString(field))' != \(sqlTextValue(value))"

        case .greaterThan(let field, let value):
            guard isValidFieldName(field) else { return "TRUE" }
            if isReservedField(field) {
                return "\(sqlFieldName(field)) > \(value)"
            }
            return "(metadata->>'\(escapeString(field))')::float > \(value)"

        case .lessThan(let field, let value):
            guard isValidFieldName(field) else { return "TRUE" }
            if isReservedField(field) {
                return "\(sqlFieldName(field)) < \(value)"
            }
            return "(metadata->>'\(escapeString(field))')::float < \(value)"

        case .greaterThanOrEqual(let field, let value):
            guard isValidFieldName(field) else { return "TRUE" }
            if isReservedField(field) {
                return "\(sqlFieldName(field)) >= \(value)"
            }
            return "(metadata->>'\(escapeString(field))')::float >= \(value)"

        case .lessThanOrEqual(let field, let value):
            guard isValidFieldName(field) else { return "TRUE" }
            if isReservedField(field) {
                return "\(sqlFieldName(field)) <= \(value)"
            }
            return "(metadata->>'\(escapeString(field))')::float <= \(value)"

        case .in(let field, let values):
            guard isValidFieldName(field) else { return "TRUE" }
            let valueList = values.map { sqlValue($0) }.joined(separator: ", ")
            if isReservedField(field) {
                return "\(sqlFieldName(field)) IN (\(valueList))"
            }
            return "metadata->>'\(escapeString(field))' IN (\(values.map { sqlTextValue($0) }.joined(separator: ", ")))"

        case .notIn(let field, let values):
            guard isValidFieldName(field) else { return "TRUE" }
            let valueList = values.map { sqlValue($0) }.joined(separator: ", ")
            if isReservedField(field) {
                return "\(sqlFieldName(field)) NOT IN (\(valueList))"
            }
            return "metadata->>'\(escapeString(field))' NOT IN (\(values.map { sqlTextValue($0) }.joined(separator: ", ")))"

        case .contains(let field, let substring):
            guard isValidFieldName(field) else { return "TRUE" }
            if isReservedField(field) {
                return "\(sqlFieldName(field)) LIKE '%\(escapeLikePattern(substring))%' ESCAPE '\\'"
            }
            return "metadata->>'\(escapeString(field))' LIKE '%\(escapeLikePattern(substring))%' ESCAPE '\\'"

        case .startsWith(let field, let prefix):
            guard isValidFieldName(field) else { return "TRUE" }
            if isReservedField(field) {
                return "\(sqlFieldName(field)) LIKE '\(escapeLikePattern(prefix))%' ESCAPE '\\'"
            }
            return "metadata->>'\(escapeString(field))' LIKE '\(escapeLikePattern(prefix))%' ESCAPE '\\'"

        case .endsWith(let field, let suffix):
            guard isValidFieldName(field) else { return "TRUE" }
            if isReservedField(field) {
                return "\(sqlFieldName(field)) LIKE '%\(escapeLikePattern(suffix))' ESCAPE '\\'"
            }
            return "metadata->>'\(escapeString(field))' LIKE '%\(escapeLikePattern(suffix))' ESCAPE '\\'"

        case .exists(let field):
            guard isValidFieldName(field) else { return "TRUE" }
            if isReservedField(field) {
                return "\(sqlFieldName(field)) IS NOT NULL"
            }
            return "metadata ? '\(escapeString(field))'"

        case .notExists(let field):
            guard isValidFieldName(field) else { return "TRUE" }
            if isReservedField(field) {
                return "\(sqlFieldName(field)) IS NULL"
            }
            return "NOT (metadata ? '\(escapeString(field))')"

        case .and(let filters):
            let parts = filters.flatMap { $0.conditions.map { conditionToSQL($0) } }
            return "(" + parts.joined(separator: " AND ") + ")"

        case .or(let filters):
            let parts = filters.flatMap { $0.conditions.map { conditionToSQL($0) } }
            return "(" + parts.joined(separator: " OR ") + ")"

        case .not(let filter):
            let parts = filter.conditions.map { conditionToSQL($0) }
            return "NOT (" + parts.joined(separator: " AND ") + ")"
        }
    }

    /// Checks if a field name is a reserved table column.
    private func isReservedField(_ field: String) -> Bool {
        ["documentId", "index", "startOffset", "endOffset", "source", "id", "content"].contains(field)
    }

    /// Validates that a field name contains only safe characters.
    ///
    /// - Parameter field: The field name to validate.
    /// - Returns: `true` if the field name is valid (alphanumeric and underscores only).
    private func isValidFieldName(_ field: String) -> Bool {
        !field.isEmpty && field.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Maps logical field names to SQL column names.
    private func sqlFieldName(_ field: String) -> String {
        switch field {
        case "documentId": return "document_id"
        case "index": return "chunk_index"
        case "startOffset": return "start_offset"
        case "endOffset": return "end_offset"
        default: return field
        }
    }

    /// Converts a MetadataValue to a SQL literal.
    private func sqlValue(_ value: MetadataValue) -> String {
        switch value {
        case .null: return "NULL"
        case .bool(let v): return v ? "TRUE" : "FALSE"
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .string(let v): return "'\(escapeString(v))'"
        case .array, .dictionary: return "'{}'"
        }
    }

    /// Converts a MetadataValue to a SQL text literal for JSONB text comparisons.
    private func sqlTextValue(_ value: MetadataValue) -> String {
        switch value {
        case .null: return "NULL"
        case .bool(let v): return "'\(v ? "true" : "false")'"
        case .int(let v): return "'\(v)'"
        case .double(let v): return "'\(v)'"
        case .string(let v): return "'\(escapeString(v))'"
        case .array, .dictionary: return "'{}'"
        }
    }

    /// Escapes a string for safe inclusion in SQL.
    private func escapeString(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "''")
         .replacingOccurrences(of: "\\", with: "\\\\")
    }

    /// Escapes a string for safe use in LIKE patterns.
    ///
    /// This escapes SQL string characters (single quotes, backslashes) as well as
    /// LIKE metacharacters (% and _) to prevent SQL injection via pattern matching.
    private func escapeLikePattern(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "''")
         .replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "%", with: "\\%")
         .replacingOccurrences(of: "_", with: "\\_")
    }

    // MARK: - Connection String Parsing

    /// Parses the host from a PostgreSQL connection string.
    private static func parseHost(_ connectionString: String) -> String {
        guard let url = URL(string: connectionString) else { return "localhost" }
        return url.host ?? "localhost"
    }

    /// Parses the port from a PostgreSQL connection string.
    private static func parsePort(_ connectionString: String) -> Int {
        guard let url = URL(string: connectionString) else { return 5432 }
        return url.port ?? 5432
    }

    /// Parses the username from a PostgreSQL connection string.
    private static func parseUsername(_ connectionString: String) -> String {
        guard let url = URL(string: connectionString) else { return "postgres" }
        return url.user ?? "postgres"
    }

    /// Parses the password from a PostgreSQL connection string.
    private static func parsePassword(_ connectionString: String) -> String? {
        guard let url = URL(string: connectionString) else { return nil }
        return url.password
    }

    /// Parses the database name from a PostgreSQL connection string.
    private static func parseDatabase(_ connectionString: String) -> String {
        guard let url = URL(string: connectionString) else { return "postgres" }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? "postgres" : path
    }

    // MARK: - Connection Lifecycle

    /// Closes the PostgreSQL connection.
    ///
    /// This method should be called when you're done using the store to properly
    /// release database resources. After calling `close()`, the store should not
    /// be used for any further operations.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let store = try await PgVectorStore.connect(...)
    /// defer {
    ///     Task {
    ///         await store.close()
    ///     }
    /// }
    ///
    /// // Use the store...
    /// try await store.add(chunks, embeddings: embeddings)
    /// ```
    ///
    /// - Note: This is an async operation as it may need to finish any pending
    ///   database operations before closing the connection.
    public func close() async {
        await connection.close()
    }
}

// MARK: - CustomStringConvertible

extension PgVectorStore: CustomStringConvertible {
    /// A textual representation of the store for debugging.
    nonisolated public var description: String {
        "PgVectorStore(name: \"\(name)\")"
    }
}

// MARK: - PostgresBindings Extension

/// Extension to create PostgresBindings from an array of encodable values.
extension PostgresBindings {
    /// Creates bindings from an array of string-convertible values.
    init(encodable values: [Any]) {
        var bindings = PostgresBindings()
        for value in values {
            switch value {
            case let s as String:
                bindings.append(s)
            case let i as Int:
                bindings.append(i)
            case let f as Float:
                bindings.append(Double(f))
            case let d as Double:
                bindings.append(d)
            case let b as Bool:
                bindings.append(b)
            default:
                bindings.append(String(describing: value))
            }
        }
        self = bindings
    }
}
