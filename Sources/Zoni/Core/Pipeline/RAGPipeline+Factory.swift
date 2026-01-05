// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RAGPipeline+Factory.swift - Convenience factory methods for RAGPipeline

import Foundation

// MARK: - Factory Methods

extension RAGPipeline {

    /// Creates an in-memory RAG pipeline for development and testing.
    ///
    /// This factory creates a pipeline with:
    /// - `InMemoryVectorStore` for fast, volatile storage
    /// - Default `RecursiveChunker` for document chunking
    /// - Default `LoaderRegistry` with common loaders (text, markdown, HTML, JSON, CSV, PDF)
    ///
    /// The in-memory configuration is ideal for:
    /// - **Development**: Quick iteration without database setup
    /// - **Testing**: Isolated test cases with no side effects
    /// - **Prototyping**: Fast exploration of RAG configurations
    /// - **Small datasets**: Datasets that fit comfortably in memory
    ///
    /// ## Example Usage
    ///
    /// ```swift
    /// // Create an in-memory pipeline with default chunking
    /// let pipeline = await RAGPipeline.inMemory(
    ///     embedding: OpenAIEmbeddingProvider(apiKey: "..."),
    ///     llm: OpenAIProvider(model: "gpt-4")
    /// )
    ///
    /// // Ingest and query
    /// try await pipeline.ingest(document)
    /// let response = try await pipeline.query("What is this about?")
    ///
    /// // Custom chunking for code documents
    /// let codePipeline = await RAGPipeline.inMemory(
    ///     embedding: embedding,
    ///     llm: llm,
    ///     chunker: RecursiveChunker(chunkSize: 500, chunkOverlap: 50)
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - embedding: The embedding provider for generating vectors.
    ///   - llm: The LLM provider for generating responses.
    ///   - chunker: Optional chunking strategy. Defaults to `RecursiveChunker`
    ///     with 1000 character chunks and 200 character overlap.
    /// - Returns: A configured `RAGPipeline` instance ready for use.
    ///
    /// - Note: Data stored in the in-memory vector store is not persisted and
    ///   will be lost when the pipeline is deallocated. Use `SQLiteVectorStore`
    ///   or `PgVectorStore` for persistent storage.
    public static func inMemory(
        embedding: any EmbeddingProvider,
        llm: any LLMProvider,
        chunker: (any ChunkingStrategy)? = nil
    ) async -> RAGPipeline {
        let vectorStore = InMemoryVectorStore()
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
