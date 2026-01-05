// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RerankerRetriever.swift - Retriever with cross-encoder reranking

import Foundation

// MARK: - RerankerRetriever

/// A retriever that applies reranking to improve result precision.
///
/// `RerankerRetriever` wraps a base retriever and uses a cross-encoder
/// reranker to reorder results based on more accurate relevance scoring.
///
/// ## How It Works
///
/// 1. Fetches candidates from the base retriever (more than needed)
/// 2. Passes candidates through the reranker for scoring
/// 3. Returns top-k reranked results
///
/// This approach combines the efficiency of bi-encoder retrieval with
/// the accuracy of cross-encoder scoring.
///
/// ## Example Usage
///
/// ```swift
/// let rerankerRetriever = RerankerRetriever(
///     baseRetriever: vectorRetriever,
///     reranker: cohereReranker,
///     initialLimit: 50  // Fetch 50 candidates for reranking
/// )
///
/// let results = try await rerankerRetriever.retrieve(
///     query: "What is Swift?",
///     limit: 10,
///     filter: nil
/// )
/// ```
public actor RerankerRetriever: Retriever {

    // MARK: - Properties

    /// The name identifying this retriever.
    ///
    /// Includes the base retriever name for clarity in logs.
    public nonisolated var name: String {
        "reranker_\(baseRetrieverName)"
    }

    /// The base retriever name (captured at init for nonisolated access).
    private let baseRetrieverName: String

    /// The base retriever to get initial candidates.
    private let baseRetriever: any Retriever

    /// The reranker for scoring candidates.
    private let reranker: any Reranker

    /// How many candidates to fetch before reranking.
    ///
    /// If `nil`, uses `limit * 3` as default.
    public var initialLimit: Int?

    // MARK: - Initialization

    /// Creates a new reranker retriever.
    ///
    /// - Parameters:
    ///   - baseRetriever: The retriever to get initial candidates from.
    ///   - reranker: The reranker to score candidates.
    ///   - initialLimit: Optional candidate limit. Default: `limit * 3`
    public init(
        baseRetriever: any Retriever,
        reranker: any Reranker,
        initialLimit: Int? = nil
    ) {
        self.baseRetriever = baseRetriever
        self.baseRetrieverName = baseRetriever.name
        self.reranker = reranker
        self.initialLimit = initialLimit
    }

    // MARK: - Configuration

    /// Sets the initial limit for candidate fetching.
    public func setInitialLimit(_ limit: Int?) {
        self.initialLimit = limit
    }

    // MARK: - Retriever Protocol

    /// Retrieves and reranks relevant chunks.
    ///
    /// - Parameters:
    ///   - query: The search query text.
    ///   - limit: Maximum number of results to return.
    ///   - filter: Optional metadata filter to apply.
    /// - Returns: Reranked results sorted by relevance.
    /// - Throws: `ZoniError.retrievalFailed` if retrieval or reranking fails.
    public func retrieve(
        query: String,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        let fetchLimit = initialLimit ?? limit * 3

        // Get initial candidates
        let candidates = try await baseRetriever.retrieve(
            query: query,
            limit: fetchLimit,
            filter: filter
        )

        guard !candidates.isEmpty else { return [] }

        // Rerank candidates
        let reranked: [RetrievalResult]
        do {
            reranked = try await reranker.rerank(query: query, results: candidates)
        } catch {
            throw ZoniError.retrievalFailed(reason: "Reranking failed: \(error.localizedDescription)")
        }

        return Array(reranked.prefix(limit))
    }
}
