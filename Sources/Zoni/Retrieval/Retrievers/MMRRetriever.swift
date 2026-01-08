// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// MMRRetriever.swift - Maximal Marginal Relevance retrieval strategy

import Foundation

// MARK: - MMRRetriever

/// A retriever that uses Maximal Marginal Relevance for diverse results.
///
/// `MMRRetriever` wraps a base retriever and reranks results to balance
/// relevance with diversity. This helps avoid returning multiple
/// near-duplicate chunks.
///
/// ## Algorithm
///
/// MMR iteratively selects documents that maximize:
/// ```
/// MMR(d) = λ * Sim(d, query) - (1-λ) * max[Sim(d, d_i)]
/// ```
///
/// Where:
/// - λ (lambda) = balance parameter (1.0 = pure relevance, 0.0 = pure diversity)
/// - Sim(d, query) = similarity to the query
/// - max[Sim(d, d_i)] = maximum similarity to already selected documents
///
/// ## Example Usage
///
/// ```swift
/// let mmrRetriever = MMRRetriever(
///     baseRetriever: vectorRetriever,
///     embeddingProvider: embedder,
///     lambda: 0.5  // Balance relevance and diversity
/// )
///
/// let results = try await mmrRetriever.retrieve(
///     query: "Swift programming",
///     limit: 10,
///     filter: nil
/// )
/// ```
public actor MMRRetriever: Retriever {

    // MARK: - Properties

    /// The name identifying this retriever.
    public nonisolated let name = "mmr"

    /// The base retriever to get initial candidates.
    private let baseRetriever: any Retriever

    /// The embedding provider for similarity calculations.
    private let embeddingProvider: any EmbeddingProvider

    /// Lambda: balance between relevance (1.0) and diversity (0.0).
    public var lambda: Float

    /// Multiplier for candidate fetching (fetch limit * multiplier candidates).
    public var candidateMultiplier: Int

    // MARK: - Initialization

    /// Creates a new MMR retriever.
    ///
    /// - Parameters:
    ///   - baseRetriever: The retriever to get initial candidates from.
    ///   - embeddingProvider: The provider for generating embeddings.
    ///   - lambda: Balance parameter (0.0 to 1.0). Default: 0.5
    ///   - candidateMultiplier: How many extra candidates to fetch. Default: 3
    public init(
        baseRetriever: any Retriever,
        embeddingProvider: any EmbeddingProvider,
        lambda: Float = 0.5,
        candidateMultiplier: Int = 3
    ) {
        self.baseRetriever = baseRetriever
        self.embeddingProvider = embeddingProvider
        // Clamp lambda to valid range [0.0, 1.0]
        self.lambda = max(0.0, min(1.0, lambda))
        // Ensure candidateMultiplier is at least 2 for meaningful diversity
        self.candidateMultiplier = max(2, candidateMultiplier)
    }

    // MARK: - Configuration

    /// Sets the lambda parameter.
    public func setLambda(_ lambda: Float) {
        self.lambda = lambda
    }

    /// Sets the candidate multiplier.
    public func setCandidateMultiplier(_ multiplier: Int) {
        self.candidateMultiplier = multiplier
    }

    // MARK: - Retriever Protocol

    /// Retrieves relevant and diverse chunks using MMR.
    ///
    /// - Parameters:
    ///   - query: The search query text.
    ///   - limit: Maximum number of results to return.
    ///   - filter: Optional metadata filter to apply.
    /// - Returns: Diverse results sorted by MMR score.
    /// - Throws: `ZoniError.retrievalFailed` if retrieval fails.
    public func retrieve(
        query: String,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        // Get more candidates than needed
        let candidates = try await baseRetriever.retrieve(
            query: query,
            limit: limit * candidateMultiplier,
            filter: filter
        )

        guard !candidates.isEmpty else { return [] }

        // Embed query and all candidates
        let queryEmbedding: Embedding
        let candidateEmbeddings: [Embedding]

        do {
            queryEmbedding = try await embeddingProvider.embed(query)
            let candidateTexts = candidates.map { $0.chunk.content }
            candidateEmbeddings = try await embeddingProvider.embed(candidateTexts)
        } catch {
            throw ZoniError.retrievalFailed(reason: "Failed to embed for MMR: \(error.localizedDescription)")
        }

        // MMR selection
        var selected: [RetrievalResult] = []
        var selectedEmbeddings: [Embedding] = []
        var remaining = Array(zip(candidates, candidateEmbeddings))

        while selected.count < limit && !remaining.isEmpty {
            var bestScore: Float = -.infinity
            var bestIndex = 0

            for (i, (_, embedding)) in remaining.enumerated() {
                // Relevance to query
                let relevance = queryEmbedding.cosineSimilarity(to: embedding)

                // Max similarity to already selected (diversity penalty)
                let maxSimilarity: Float
                if selectedEmbeddings.isEmpty {
                    maxSimilarity = 0
                } else {
                    maxSimilarity = selectedEmbeddings
                        .map { embedding.cosineSimilarity(to: $0) }
                        .max() ?? 0
                }

                // MMR score: λ * relevance - (1-λ) * maxSimilarity
                let mmrScore = lambda * relevance - (1 - lambda) * maxSimilarity

                if mmrScore > bestScore {
                    bestScore = mmrScore
                    bestIndex = i
                }
            }

            let (bestResult, bestEmbedding) = remaining.remove(at: bestIndex)
            selected.append(RetrievalResult(
                chunk: bestResult.chunk,
                score: bestScore,
                metadata: bestResult.metadata
            ))
            selectedEmbeddings.append(bestEmbedding)
        }

        return selected
    }
}
