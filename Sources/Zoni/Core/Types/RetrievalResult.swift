// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RetrievalResult.swift - Results from vector similarity search operations.

// MARK: - RetrievalResult

/// A chunk retrieved from a vector store with its relevance score.
///
/// `RetrievalResult` wraps a `Chunk` with a similarity score and optional
/// additional metadata from the retrieval operation. Results are typically
/// sorted by score in descending order (higher scores = more relevant).
///
/// Example usage:
/// ```swift
/// let results = try await vectorStore.search(query: queryEmbedding, limit: 5)
///
/// // Results are sorted by relevance
/// for result in results.sorted(by: >) {
///     print("Score: \(result.score)")
///     print("Content: \(result.chunk.content)")
/// }
/// ```
public struct RetrievalResult: Sendable, Identifiable, Equatable {
    /// The unique identifier, derived from the underlying chunk.
    public var id: String { chunk.id }

    /// The retrieved chunk containing the text content.
    public let chunk: Chunk

    /// The relevance score from the similarity search.
    ///
    /// Higher scores indicate greater relevance to the query. The exact
    /// range depends on the similarity metric used:
    /// - Cosine similarity: -1.0 to 1.0 (typically 0.0 to 1.0 for normalized vectors)
    /// - Dot product: unbounded, higher is more similar
    /// - Euclidean distance: 0.0 to infinity (converted to similarity score)
    public let score: Float

    /// Additional metadata from the retrieval operation.
    ///
    /// This may include information such as:
    /// - Retrieval method used
    /// - Reranking score if applicable
    /// - Debug information from the vector store
    public let metadata: [String: MetadataValue]

    /// Creates a new retrieval result.
    ///
    /// - Parameters:
    ///   - chunk: The retrieved chunk.
    ///   - score: The relevance score (higher = more relevant).
    ///   - metadata: Additional metadata from retrieval. Defaults to empty.
    public init(
        chunk: Chunk,
        score: Float,
        metadata: [String: MetadataValue] = [:]
    ) {
        self.chunk = chunk
        self.score = score
        self.metadata = metadata
    }
}

// MARK: - Comparable

extension RetrievalResult: Comparable {
    /// Compares two retrieval results by their relevance scores.
    ///
    /// Results with lower scores are considered "less than" results with higher
    /// scores. This allows sorting in ascending order with `.sorted()` or
    /// descending order with `.sorted(by: >)`.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand side result.
    ///   - rhs: The right-hand side result.
    /// - Returns: `true` if the left result has a lower score.
    public static func < (lhs: RetrievalResult, rhs: RetrievalResult) -> Bool {
        lhs.score < rhs.score
    }
}

// MARK: - Hashable

extension RetrievalResult: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(chunk.id)
        hasher.combine(score)
    }
}

// MARK: - CustomStringConvertible

extension RetrievalResult: CustomStringConvertible {
    public var description: String {
        let preview = chunk.content.prefix(40)
        let truncated = chunk.content.count > 40 ? "..." : ""
        return "RetrievalResult(score: \(String(format: "%.4f", score)), content: \"\(preview)\(truncated)\")"
    }
}
