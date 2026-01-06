// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RAGPipeline+Apple.swift - Apple platform factory methods for RAGPipeline

import Foundation
import Zoni
import NaturalLanguage

// MARK: - Apple Platform Factory Methods

extension RAGPipeline {

    /// Creates a privacy-first on-device RAG pipeline using Apple frameworks.
    ///
    /// This factory creates a pipeline optimized for Apple platforms with:
    /// - `NLEmbeddingProvider` for free, private on-device embeddings
    /// - `SQLiteVectorStore` for persistent local storage
    /// - Default `RecursiveChunker` for document chunking
    /// - Default `LoaderRegistry` with common loaders
    ///
    /// The Apple configuration is ideal for:
    /// - **Privacy-first apps**: All processing happens on-device
    /// - **Offline-first apps**: Full functionality without network connectivity
    /// - **Zero API costs**: No embedding API fees or rate limits
    /// - **iOS/macOS apps**: Native SQLite support on all Apple platforms
    ///
    /// ## Supported Languages
    ///
    /// NLEmbedding provides 512-dimensional embeddings for:
    /// - English, Spanish, French, German, Italian, Portuguese
    /// - Chinese, Japanese, Korean
    /// - Dutch, Russian, Polish, Turkish
    ///
    /// ## Example Usage
    ///
    /// ```swift
    /// // Create an on-device pipeline with English embeddings
    /// let documentsURL = FileManager.default.urls(
    ///     for: .documentDirectory,
    ///     in: .userDomainMask
    /// )[0].appendingPathComponent("vectors.db")
    ///
    /// let pipeline = try await RAGPipeline.apple(
    ///     databasePath: documentsURL,
    ///     llm: myLLMProvider  // Your LLM provider
    /// )
    ///
    /// // Ingest documents (stored locally)
    /// try await pipeline.ingest(document)
    ///
    /// // Query with on-device semantic search
    /// let response = try await pipeline.query("What is this about?")
    ///
    /// // Custom language for non-English content
    /// let frenchPipeline = try await RAGPipeline.apple(
    ///     databasePath: frenchDbURL,
    ///     llm: llm,
    ///     language: .french
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - databasePath: Path to the SQLite database file. The directory must exist.
    ///     Use `FileManager.urls(for:in:)` for platform-appropriate paths.
    ///   - llm: The LLM provider for generating responses.
    ///   - language: NLEmbedding language. Defaults to `.english`.
    ///     Must match the primary language of your documents.
    ///   - tableName: Name of the database table. Defaults to "zoni_chunks".
    ///   - chunker: Optional chunking strategy. Defaults to `RecursiveChunker`.
    /// - Returns: A configured `RAGPipeline` instance.
    /// - Throws: `AppleMLError.modelNotAvailable` if the NLEmbedding model is not
    ///   available for the specified language, or `ZoniError.vectorStoreConnectionFailed`
    ///   if the SQLite database cannot be created.
    ///
    /// - Note: Apple's NLEmbedding provides 512-dimensional vectors. If your use case
    ///   requires higher dimensions (e.g., 1536 for OpenAI compatibility), consider
    ///   using a different embedding provider. NLEmbedding produces 512-dimensional
    ///   vectors, which may have lower semantic resolution than cloud-based embedding
    ///   models. For highest accuracy, consider using cloud embeddings.
    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
    public static func apple(
        databasePath: URL,
        llm: any LLMProvider,
        language: NLEmbeddingProvider.Language = .english,
        tableName: String = "zoni_chunks",
        chunker: (any ChunkingStrategy)? = nil
    ) async throws -> RAGPipeline {
        // Create the NLEmbedding provider for on-device embeddings
        let embedding = try NLEmbeddingProvider(language: language)

        // NLEmbedding produces 512-dimensional vectors
        let vectorStore = try SQLiteVectorStore(
            path: databasePath.path,
            tableName: tableName,
            dimensions: 512
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

    /// Creates a privacy-first on-device RAG pipeline with a custom embedding provider.
    ///
    /// This overload allows using any embedding provider while still benefiting from
    /// local SQLite storage. Use this when you need:
    /// - Higher-dimensional embeddings (e.g., MLXEmbeddingProvider)
    /// - Cloud embeddings with local storage
    /// - Custom embedding models
    ///
    /// ## Example Usage
    ///
    /// ```swift
    /// // Use MLX embeddings with SQLite storage
    /// let mlxEmbedding = try MLXEmbeddingProvider()
    /// let pipeline = try await RAGPipeline.apple(
    ///     databasePath: documentsURL,
    ///     embedding: mlxEmbedding,
    ///     llm: llm
    /// )
    ///
    /// // Use cloud embeddings with local storage
    /// let openAIEmbedding = OpenAIEmbeddingProvider(apiKey: "...")
    /// let hybridPipeline = try await RAGPipeline.apple(
    ///     databasePath: documentsURL,
    ///     embedding: openAIEmbedding,
    ///     llm: llm,
    ///     dimensions: 1536  // OpenAI text-embedding-3-small
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - databasePath: Path to the SQLite database file.
    ///   - embedding: The embedding provider for generating vectors.
    ///   - llm: The LLM provider for generating responses.
    ///   - tableName: Name of the database table. Defaults to "zoni_chunks".
    ///   - dimensions: Embedding vector dimensions. Defaults to provider's dimensions.
    ///   - chunker: Optional chunking strategy. Defaults to `RecursiveChunker`.
    /// - Returns: A configured `RAGPipeline` instance.
    /// - Throws: `ZoniError.embeddingDimensionMismatch` if explicit dimensions don't match
    ///   the embedding provider's dimensions, or `ZoniError.vectorStoreConnectionFailed`
    ///   if SQLite database creation fails.
    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
    public static func apple(
        databasePath: URL,
        embedding: any EmbeddingProvider,
        llm: any LLMProvider,
        tableName: String = "zoni_chunks",
        dimensions: Int? = nil,
        chunker: (any ChunkingStrategy)? = nil
    ) async throws -> RAGPipeline {
        let actualDimensions = dimensions ?? embedding.dimensions

        // Validate dimension match if user provided explicit dimensions
        if let userDimensions = dimensions, userDimensions != embedding.dimensions {
            throw ZoniError.embeddingDimensionMismatch(
                expected: userDimensions,
                got: embedding.dimensions
            )
        }

        let vectorStore = try SQLiteVectorStore(
            path: databasePath.path,
            tableName: tableName,
            dimensions: actualDimensions
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
