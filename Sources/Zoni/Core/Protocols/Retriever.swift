// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// Retriever protocol for high-level document retrieval operations.

// MARK: - Retriever

/// A protocol for high-level document retrieval.
///
/// Retrievers combine embedding generation and vector search
/// into a single query interface. They can also implement
/// hybrid retrieval strategies (vector + keyword).
///
/// Example usage:
/// ```swift
/// let retriever = MyRetriever(vectorStore: store, embedder: embedder)
///
/// // Retrieve relevant documents for a query
/// let results = try await retriever.retrieve(
///     query: "How does Swift concurrency work?",
///     limit: 10,
///     filter: .equals("category", "swift")
/// )
///
/// for result in results {
///     print("Score: \(result.score)")
///     print("Content: \(result.chunk.content)")
/// }
/// ```
public protocol Retriever: Sendable {
    /// The name identifying this retriever.
    ///
    /// This can be used for logging, debugging, or selecting between
    /// multiple retrievers in a hybrid retrieval setup.
    var name: String { get }

    /// Retrieves relevant chunks for a text query.
    ///
    /// This method performs the full retrieval pipeline:
    /// 1. Generates an embedding for the query text
    /// 2. Searches the vector store for similar chunks
    /// 3. Applies optional metadata filtering
    /// 4. Returns ranked results by relevance
    ///
    /// - Parameters:
    ///   - query: The search query text.
    ///   - limit: Maximum number of results to return.
    ///   - filter: Optional metadata filter to apply to results.
    /// - Returns: An array of retrieval results, ranked by relevance score.
    /// - Throws: `ZoniError.retrievalFailed` if retrieval fails.
    func retrieve(
        query: String,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult]
}

// MARK: - Convenience Extensions

extension Retriever {
    /// Retrieves relevant chunks with a default limit of 5.
    ///
    /// This is a convenience method that calls the full `retrieve` method
    /// with a default limit of 5 results.
    ///
    /// - Parameters:
    ///   - query: The search query text.
    ///   - filter: Optional metadata filter to apply to results. Defaults to `nil`.
    /// - Returns: An array of retrieval results, ranked by relevance score.
    /// - Throws: `ZoniError.retrievalFailed` if retrieval fails.
    public func retrieve(
        query: String,
        filter: MetadataFilter? = nil
    ) async throws -> [RetrievalResult] {
        try await retrieve(query: query, limit: 5, filter: filter)
    }
}
