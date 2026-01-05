// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// Reranker.swift - Protocol for reranking retrieval results

import Foundation

// MARK: - Reranker

/// A protocol for reranking retrieval results.
///
/// Rerankers take an initial set of retrieved results and reorder them
/// based on more sophisticated relevance scoring. This is typically done
/// using cross-encoder models that jointly encode the query and each document.
///
/// ## Common Use Cases
///
/// 1. **Cross-encoder reranking**: Use neural models like BERT to score
///    query-document pairs more accurately than bi-encoder similarity.
///
/// 2. **Feature-based reranking**: Combine multiple signals (BM25, semantic
///    similarity, metadata) into a learned ranking function.
///
/// 3. **Diversity reranking**: Reorder results to maximize coverage of
///    different topics or subtopics.
///
/// ## Example Implementation
///
/// ```swift
/// actor MyReranker: Reranker {
///     nonisolated let name = "my_reranker"
///
///     func rerank(query: String, results: [RetrievalResult]) async throws -> [RetrievalResult] {
///         // Score each result against the query
///         var scored = results.map { result -> (RetrievalResult, Float) in
///             let newScore = computeRelevance(query, result.chunk.content)
///             return (result, newScore)
///         }
///
///         // Sort by new scores
///         scored.sort { $0.1 > $1.1 }
///
///         // Return with updated scores
///         return scored.map { RetrievalResult(chunk: $0.0.chunk, score: $0.1) }
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// All conforming types must be `Sendable` to ensure safe concurrent usage.
/// Consider using `actor` for implementations with mutable state.
public protocol Reranker: Sendable {

    /// The name identifying this reranker.
    ///
    /// Used for logging, debugging, and configuration selection.
    var name: String { get }

    /// Reranks retrieval results based on query relevance.
    ///
    /// This method takes the initial results from a retriever and reorders
    /// them based on more accurate relevance scoring. The implementation
    /// may use cross-encoders, learned ranking functions, or other techniques.
    ///
    /// - Parameters:
    ///   - query: The original search query.
    ///   - results: The initial retrieval results to rerank.
    /// - Returns: Reranked results with updated scores, sorted by relevance.
    /// - Throws: `ZoniError.retrievalFailed` if reranking fails.
    func rerank(query: String, results: [RetrievalResult]) async throws -> [RetrievalResult]
}
