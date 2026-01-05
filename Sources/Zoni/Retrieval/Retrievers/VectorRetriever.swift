// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// VectorRetriever.swift - Vector similarity retrieval strategy

import Foundation

// MARK: - VectorRetriever

/// A retriever that uses vector similarity search.
///
/// `VectorRetriever` combines an embedding provider and vector store to
/// perform semantic search. It embeds the query text and searches for
/// similar chunks in the vector store.
///
/// Example usage:
/// ```swift
/// let retriever = VectorRetriever(
///     vectorStore: store,
///     embeddingProvider: embedder,
///     similarityThreshold: 0.7
/// )
///
/// let results = try await retriever.retrieve(
///     query: "What is Swift concurrency?",
///     limit: 10,
///     filter: .equals("category", "swift")
/// )
/// ```
public actor VectorRetriever: Retriever {

    // MARK: - Properties

    /// The name identifying this retriever.
    public nonisolated let name = "vector"

    /// The vector store to search.
    private let vectorStore: any VectorStore

    /// The embedding provider for query embedding.
    private let embeddingProvider: any EmbeddingProvider

    /// Optional minimum similarity threshold for results.
    ///
    /// Results with scores below this threshold are filtered out.
    /// Set to `nil` to disable threshold filtering.
    public var similarityThreshold: Float?

    // MARK: - Initialization

    /// Creates a new vector retriever.
    ///
    /// - Parameters:
    ///   - vectorStore: The vector store to search.
    ///   - embeddingProvider: The provider for generating query embeddings.
    ///   - similarityThreshold: Optional minimum score threshold.
    public init(
        vectorStore: any VectorStore,
        embeddingProvider: any EmbeddingProvider,
        similarityThreshold: Float? = nil
    ) {
        self.vectorStore = vectorStore
        self.embeddingProvider = embeddingProvider
        self.similarityThreshold = similarityThreshold
    }

    // MARK: - Retriever Protocol

    /// Retrieves relevant chunks using vector similarity search.
    ///
    /// The retrieval process:
    /// 1. Embeds the query text using the embedding provider
    /// 2. Searches the vector store for similar chunks
    /// 3. Optionally filters results below the similarity threshold
    ///
    /// - Parameters:
    ///   - query: The search query text.
    ///   - limit: Maximum number of results to return.
    ///   - filter: Optional metadata filter to apply.
    /// - Returns: Matching chunks sorted by similarity score (descending).
    /// - Throws: `ZoniError.retrievalFailed` if retrieval fails.
    public func retrieve(
        query: String,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        // Embed the query
        let queryEmbedding: Embedding
        do {
            queryEmbedding = try await embeddingProvider.embed(query)
        } catch {
            throw ZoniError.retrievalFailed(reason: "Failed to embed query: \(error.localizedDescription)")
        }

        // Search the vector store
        var results: [RetrievalResult]
        do {
            results = try await vectorStore.search(
                query: queryEmbedding,
                limit: limit,
                filter: filter
            )
        } catch {
            throw ZoniError.retrievalFailed(reason: "Vector store search failed: \(error.localizedDescription)")
        }

        // Apply similarity threshold if set
        if let threshold = similarityThreshold {
            results = results.filter { $0.score >= threshold }
        }

        return results
    }

    // MARK: - Configuration

    /// Sets the similarity threshold.
    ///
    /// - Parameter threshold: The new threshold value, or `nil` to disable.
    public func setSimilarityThreshold(_ threshold: Float?) {
        self.similarityThreshold = threshold
    }
}
