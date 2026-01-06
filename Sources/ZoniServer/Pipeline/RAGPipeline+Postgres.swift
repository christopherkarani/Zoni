// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RAGPipeline+Postgres.swift - PostgreSQL factory methods for RAGPipeline

import Foundation
import Zoni
import NIOCore

// MARK: - PostgreSQL Factory Methods

extension RAGPipeline {

    /// Creates a RAG pipeline backed by PostgreSQL with pgvector.
    ///
    /// This factory creates a production-ready pipeline with:
    /// - `PgVectorStore` for scalable, persistent vector storage
    /// - Default `RecursiveChunker` for document chunking
    /// - Default `LoaderRegistry` with common loaders
    ///
    /// The PostgreSQL configuration is ideal for:
    /// - **Production deployments**: Scalable, durable storage
    /// - **Large datasets**: Efficient vector indexing (IVFFlat/HNSW)
    /// - **Multi-instance apps**: Shared database across instances
    /// - **Server-side Swift**: Vapor, Hummingbird applications
    ///
    /// ## Prerequisites
    ///
    /// Ensure your PostgreSQL database is properly configured:
    /// 1. PostgreSQL 15+ with pgvector extension installed
    /// 2. Run `CREATE EXTENSION IF NOT EXISTS vector;` on your database
    ///
    /// ## Example Usage
    ///
    /// ```swift
    /// // Create a PostgreSQL-backed pipeline
    /// let pipeline = try await RAGPipeline.postgres(
    ///     connectionString: "postgres://user:pass@localhost:5432/mydb",
    ///     embedding: OpenAIEmbeddingProvider(apiKey: "..."),
    ///     llm: OpenAIProvider(model: "gpt-4"),
    ///     eventLoopGroup: app.eventLoopGroup
    /// )
    ///
    /// // Ingest documents (persisted in PostgreSQL)
    /// try await pipeline.ingest(document)
    ///
    /// // Query with semantic search (uses pgvector indexes)
    /// let response = try await pipeline.query("What is this about?")
    ///
    /// // Custom table name for multi-tenant apps
    /// let tenantPipeline = try await RAGPipeline.postgres(
    ///     connectionString: connectionString,
    ///     embedding: embedding,
    ///     llm: llm,
    ///     tableName: "tenant_\(tenantId)_chunks",
    ///     eventLoopGroup: eventLoopGroup
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - connectionString: PostgreSQL connection string in URL format.
    ///     Format: `postgres://username:password@host:port/database`
    ///   - embedding: The embedding provider for generating vectors.
    ///   - llm: The LLM provider for generating responses.
    ///   - tableName: Name of the database table. Defaults to "zoni_chunks".
    ///     Use different table names for multi-tenant isolation.
    ///   - dimensions: Embedding vector dimensions. Defaults to 1536 (OpenAI).
    ///     Must match your embedding provider's output dimensions.
    ///   - indexType: Vector index type. Defaults to `.ivfflat`.
    ///     Use `.hnsw` for higher recall on large datasets.
    ///   - chunker: Optional chunking strategy. Defaults to `RecursiveChunker`.
    ///   - eventLoopGroup: NIO EventLoopGroup for database connections.
    ///   - tlsMode: TLS configuration. Defaults to `.prefer`.
    /// - Returns: A configured `RAGPipeline` instance.
    /// - Throws: `ZoniError.vectorStoreConnectionFailed` if database connection fails
    ///   or schema creation fails.
    ///
    /// - Note: For production workloads with high concurrency, consider implementing
    ///   a connection pool pattern. See `PgVectorStore` documentation for details.
    public static func postgres(
        connectionString: String,
        embedding: any EmbeddingProvider,
        llm: any LLMProvider,
        tableName: String = "zoni_chunks",
        dimensions: Int = 1536,
        indexType: PgVectorStore.IndexType = .ivfflat,
        chunker: (any ChunkingStrategy)? = nil,
        eventLoopGroup: EventLoopGroup,
        tlsMode: PgVectorStore.TLSMode = .prefer
    ) async throws -> RAGPipeline {
        // Validate connection string format
        guard connectionString.hasPrefix("postgres://") || connectionString.hasPrefix("postgresql://") else {
            throw ZoniError.vectorStoreConnectionFailed(
                reason: "Invalid connection string: must start with 'postgres://' or 'postgresql://'"
            )
        }

        // Basic URL validation
        guard URL(string: connectionString) != nil else {
            throw ZoniError.vectorStoreConnectionFailed(
                reason: "Invalid connection string: malformed URL"
            )
        }

        let configuration = PgVectorStore.Configuration(
            tableName: tableName,
            dimensions: dimensions,
            indexType: indexType
        )

        let vectorStore = try await PgVectorStore.connect(
            connectionString: connectionString,
            configuration: configuration,
            eventLoopGroup: eventLoopGroup,
            tlsMode: tlsMode
        )

        let loaderRegistry = await LoaderRegistry.defaultRegistry()
        let actualChunker = chunker ?? RecursiveChunker()

        return RAGPipeline(
            embedding: embedding,
            vectorStore: vectorStore,
            llm: llm,
            chunker: actualChunker,
            loaderRegistry: loaderRegistry
        )
    }
}
