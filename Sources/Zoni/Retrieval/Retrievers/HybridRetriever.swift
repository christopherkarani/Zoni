// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// HybridRetriever.swift - Hybrid vector + keyword retrieval strategy

import Foundation

// MARK: - HybridRetriever

/// A retriever that combines vector and keyword search.
///
/// `HybridRetriever` performs both semantic (vector) and lexical (keyword)
/// search, then fuses the results using configurable methods.
///
/// ## Fusion Methods
///
/// - **Reciprocal Rank Fusion (RRF)**: Default method. Combines rankings
///   using `score = sum(1 / (k + rank))`. Robust and parameter-free.
///
/// - **Weighted Sum**: Normalizes scores to [0,1] and computes weighted
///   average based on `vectorWeight`.
///
/// - **Distribution-Based**: Uses z-score normalization for fairer
///   comparison of different score distributions.
///
/// ## Example Usage
///
/// ```swift
/// let hybrid = HybridRetriever(
///     vectorRetriever: vectorRetriever,
///     keywordRetriever: keywordRetriever,
///     vectorWeight: 0.7
/// )
///
/// let results = try await hybrid.retrieve(
///     query: "Swift concurrency",
///     limit: 10,
///     filter: nil
/// )
/// ```
public actor HybridRetriever: Retriever {

    // MARK: - FusionMethod

    /// Methods for fusing vector and keyword results.
    public enum FusionMethod: Sendable, Equatable {
        /// Weighted average of normalized scores.
        case weightedSum

        /// Reciprocal Rank Fusion with parameter k.
        /// Score = sum(1 / (k + rank))
        case reciprocalRankFusion(k: Int = 60)

        /// Z-score normalization for distribution-based fusion.
        case distributionBased
    }

    // MARK: - Properties

    /// The name identifying this retriever.
    public nonisolated let name = "hybrid"

    /// The vector similarity retriever.
    private let vectorRetriever: VectorRetriever

    /// The BM25 keyword retriever.
    private let keywordRetriever: KeywordRetriever

    /// Weight for vector results (keyword weight = 1 - vectorWeight).
    public var vectorWeight: Float

    /// The fusion method to use.
    public var fusionMethod: FusionMethod

    // MARK: - Initialization

    /// Creates a new hybrid retriever.
    ///
    /// - Parameters:
    ///   - vectorRetriever: The vector similarity retriever.
    ///   - keywordRetriever: The keyword retriever.
    ///   - vectorWeight: Weight for vector results (0.0 to 1.0). Default: 0.7
    ///   - fusionMethod: The fusion method. Default: `.reciprocalRankFusion()`
    public init(
        vectorRetriever: VectorRetriever,
        keywordRetriever: KeywordRetriever,
        vectorWeight: Float = 0.7,
        fusionMethod: FusionMethod = .reciprocalRankFusion()
    ) {
        self.vectorRetriever = vectorRetriever
        self.keywordRetriever = keywordRetriever
        self.vectorWeight = vectorWeight
        self.fusionMethod = fusionMethod
    }

    // MARK: - Configuration

    /// Sets the fusion method.
    ///
    /// - Parameter method: The fusion method to use.
    /// - Note: For RRF, k must be > 0. Invalid values are clamped to minimum 1.
    public func setFusionMethod(_ method: FusionMethod) {
        // Validate RRF parameter k > 0
        if case .reciprocalRankFusion(let k) = method, k < 1 {
            self.fusionMethod = .reciprocalRankFusion(k: max(1, k))
        } else {
            self.fusionMethod = method
        }
    }

    /// Sets the vector weight.
    ///
    /// - Parameter weight: Weight for vector results, clamped to [0, 1].
    public func setVectorWeight(_ weight: Float) {
        self.vectorWeight = min(1.0, max(0.0, weight))
    }

    // MARK: - Retriever Protocol

    /// Retrieves relevant chunks using hybrid search.
    ///
    /// - Parameters:
    ///   - query: The search query text.
    ///   - limit: Maximum number of results to return.
    ///   - filter: Optional metadata filter to apply.
    /// - Returns: Fused results sorted by combined score.
    /// - Throws: `ZoniError.retrievalFailed` if retrieval fails.
    public func retrieve(
        query: String,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        // Fetch more candidates for fusion
        let fetchLimit = limit * 2

        // Run both retrievers in parallel
        async let vectorResults = vectorRetriever.retrieve(
            query: query,
            limit: fetchLimit,
            filter: filter
        )
        async let keywordResults = keywordRetriever.retrieve(
            query: query,
            limit: fetchLimit,
            filter: filter
        )

        let (vResults, kResults) = try await (vectorResults, keywordResults)

        // Fuse results
        let fused = fuse(vector: vResults, keyword: kResults)

        return Array(fused.prefix(limit))
    }

    // MARK: - Fusion Methods

    private func fuse(
        vector: [RetrievalResult],
        keyword: [RetrievalResult]
    ) -> [RetrievalResult] {
        switch fusionMethod {
        case .weightedSum:
            return weightedSumFusion(vector: vector, keyword: keyword)
        case .reciprocalRankFusion(let k):
            return rrfFusion(vector: vector, keyword: keyword, k: k)
        case .distributionBased:
            return distributionFusion(vector: vector, keyword: keyword)
        }
    }

    /// Reciprocal Rank Fusion: score = sum(1 / (k + rank))
    private func rrfFusion(
        vector: [RetrievalResult],
        keyword: [RetrievalResult],
        k: Int
    ) -> [RetrievalResult] {
        var scores: [String: Float] = [:]
        var chunks: [String: Chunk] = [:]
        var metadata: [String: [String: MetadataValue]] = [:]

        // Score from vector results
        for (rank, result) in vector.enumerated() {
            scores[result.id, default: 0] += 1.0 / Float(k + rank + 1) * vectorWeight
            chunks[result.id] = result.chunk
            metadata[result.id] = result.metadata
        }

        // Score from keyword results
        for (rank, result) in keyword.enumerated() {
            scores[result.id, default: 0] += 1.0 / Float(k + rank + 1) * (1 - vectorWeight)
            chunks[result.id] = result.chunk
            if metadata[result.id] == nil {
                metadata[result.id] = result.metadata
            }
        }

        return scores
            .sorted { $0.value > $1.value }
            .compactMap { id, score in
                guard let chunk = chunks[id] else { return nil }
                return RetrievalResult(chunk: chunk, score: score, metadata: metadata[id] ?? [:])
            }
    }

    /// Weighted sum of normalized scores.
    private func weightedSumFusion(
        vector: [RetrievalResult],
        keyword: [RetrievalResult]
    ) -> [RetrievalResult] {
        let vNorm = normalize(vector)
        let kNorm = normalize(keyword)

        var scores: [String: Float] = [:]
        var chunks: [String: Chunk] = [:]
        var metadata: [String: [String: MetadataValue]] = [:]

        for result in vNorm {
            scores[result.id, default: 0] += result.score * vectorWeight
            chunks[result.id] = result.chunk
            metadata[result.id] = result.metadata
        }

        for result in kNorm {
            scores[result.id, default: 0] += result.score * (1 - vectorWeight)
            chunks[result.id] = result.chunk
            if metadata[result.id] == nil {
                metadata[result.id] = result.metadata
            }
        }

        return scores
            .sorted { $0.value > $1.value }
            .compactMap { id, score in
                guard let chunk = chunks[id] else { return nil }
                return RetrievalResult(chunk: chunk, score: score, metadata: metadata[id] ?? [:])
            }
    }

    /// Distribution-based fusion using z-score normalization.
    private func distributionFusion(
        vector: [RetrievalResult],
        keyword: [RetrievalResult]
    ) -> [RetrievalResult] {
        let vZScore = zScoreNormalize(vector)
        let kZScore = zScoreNormalize(keyword)

        var scores: [String: Float] = [:]
        var chunks: [String: Chunk] = [:]
        var metadata: [String: [String: MetadataValue]] = [:]

        for result in vZScore {
            scores[result.id, default: 0] += result.score * vectorWeight
            chunks[result.id] = result.chunk
            metadata[result.id] = result.metadata
        }

        for result in kZScore {
            scores[result.id, default: 0] += result.score * (1 - vectorWeight)
            chunks[result.id] = result.chunk
            if metadata[result.id] == nil {
                metadata[result.id] = result.metadata
            }
        }

        return scores
            .sorted { $0.value > $1.value }
            .compactMap { id, score in
                guard let chunk = chunks[id] else { return nil }
                return RetrievalResult(chunk: chunk, score: score, metadata: metadata[id] ?? [:])
            }
    }

    // MARK: - Normalization Helpers

    /// Normalizes scores to [0, 1] range.
    private func normalize(_ results: [RetrievalResult]) -> [RetrievalResult] {
        guard !results.isEmpty else { return results }

        let scores = results.map(\.score)
        guard let maxScore = scores.max(), let minScore = scores.min() else {
            return results
        }

        // If all scores are equal, normalize to 1.0 (perfect match)
        guard maxScore > minScore else {
            return results.map {
                RetrievalResult(
                    chunk: $0.chunk,
                    score: 1.0,
                    metadata: $0.metadata
                )
            }
        }

        return results.map {
            RetrievalResult(
                chunk: $0.chunk,
                score: ($0.score - minScore) / (maxScore - minScore),
                metadata: $0.metadata
            )
        }
    }

    /// Z-score normalization.
    private func zScoreNormalize(_ results: [RetrievalResult]) -> [RetrievalResult] {
        guard !results.isEmpty else { return results }

        let scores = results.map(\.score)
        let count = Float(scores.count)
        let mean = scores.reduce(0, +) / count
        let variance = scores.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / count
        let stdDev = sqrt(variance)

        guard stdDev > 0 else { return results }

        return results.map {
            RetrievalResult(
                chunk: $0.chunk,
                score: ($0.score - mean) / stdDev,
                metadata: $0.metadata
            )
        }
    }
}
