// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// GPUAcceleratedMMRRetriever.swift - GPU-accelerated Maximal Marginal Relevance retrieval
//
// This actor wraps an MMRRetriever and provides GPU acceleration for the
// pairwise similarity computations that dominate the MMR algorithm.

#if canImport(Metal)
import Metal
#endif
import Foundation
import Zoni

// MARK: - GPUAcceleratedMMRRetriever

/// GPU-accelerated MMR retriever for diverse, relevant results.
///
/// This actor wraps a base retriever and uses Metal GPU acceleration for
/// the O(n×k×d) pairwise similarity computations in the MMR algorithm.
/// Falls back to CPU for small candidate sets where GPU overhead dominates.
///
/// ## Performance Characteristics
/// - **< 100 candidates**: CPU is faster (GPU dispatch overhead)
/// - **100-500 candidates**: Breakeven zone
/// - **> 500 candidates**: GPU provides significant speedup
///
/// ## Algorithm
/// MMR iteratively selects documents maximizing:
/// ```
/// MMR(d) = λ × Sim(d, query) - (1-λ) × max[Sim(d, selected)]
/// ```
///
/// ## Example Usage
/// ```swift
/// let gpuMMR = try GPUAcceleratedMMRRetriever(
///     baseRetriever: vectorRetriever,
///     embeddingProvider: embedder,
///     lambda: 0.7
/// )
///
/// let results = try await gpuMMR.retrieve(query: "Swift concurrency", limit: 10)
/// ```
public actor GPUAcceleratedMMRRetriever: Retriever {

    // MARK: - Properties

    /// The name identifying this retriever.
    public nonisolated let name = "gpu_accelerated_mmr"

    /// The base retriever to get initial candidates.
    private let baseRetriever: any Retriever

    /// The embedding provider for similarity calculations.
    private let embeddingProvider: any EmbeddingProvider

    /// Lambda: balance between relevance (1.0) and diversity (0.0).
    public var lambda: Float

    /// Multiplier for candidate fetching.
    public var candidateMultiplier: Int

    /// Metal compute instance (nil if Metal unavailable).
    #if canImport(Metal)
    private var metalCompute: MetalVectorCompute?
    #endif

    /// Performance metrics.
    public private(set) var metrics = MMRMetrics()

    /// Threshold: use GPU for candidate counts above this.
    public static let gpuThreshold = 100

    // MARK: - Initialization

    /// Creates a GPU-accelerated MMR retriever.
    ///
    /// - Parameters:
    ///   - baseRetriever: The retriever to get initial candidates from.
    ///   - embeddingProvider: The provider for generating embeddings.
    ///   - lambda: Balance parameter (0.0 to 1.0). Default: 0.5. Values outside range are clamped.
    ///   - candidateMultiplier: How many extra candidates to fetch. Default: 3. Must be positive.
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

        #if canImport(Metal)
        self.metalCompute = try? MetalVectorCompute()
        #endif
    }

    // MARK: - Configuration

    /// Whether GPU acceleration is available.
    public var supportsGPU: Bool {
        #if canImport(Metal)
        return metalCompute?.isMetalAvailable ?? false
        #else
        return false
        #endif
    }

    // MARK: - Retriever Protocol

    /// Retrieves relevant and diverse chunks using GPU-accelerated MMR.
    public func retrieve(
        query: String,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        // Get candidates from base retriever
        let candidates = try await baseRetriever.retrieve(
            query: query,
            limit: limit * candidateMultiplier,
            filter: filter
        )

        guard !candidates.isEmpty else { return [] }

        // Embed query and candidates
        let queryEmbedding: Embedding
        let candidateEmbeddings: [Embedding]

        do {
            queryEmbedding = try await embeddingProvider.embed(query)
            let candidateTexts = candidates.map { $0.chunk.content }
            candidateEmbeddings = try await embeddingProvider.embed(candidateTexts)
        } catch {
            throw ZoniError.retrievalFailed(reason: "Failed to embed for MMR: \(error.localizedDescription)")
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Select backend based on candidate count
        #if canImport(Metal)
        if let metal = metalCompute, candidates.count >= Self.gpuThreshold {
            let results = try await gpuMMR(
                candidates: candidates,
                queryEmbedding: queryEmbedding,
                candidateEmbeddings: candidateEmbeddings,
                limit: limit,
                metal: metal
            )
            metrics.recordGPUOperation(duration: CFAbsoluteTimeGetCurrent() - startTime)
            return results
        }
        #endif

        // CPU fallback
        let results = cpuMMR(
            candidates: candidates,
            queryEmbedding: queryEmbedding,
            candidateEmbeddings: candidateEmbeddings,
            limit: limit
        )
        metrics.recordCPUOperation(duration: CFAbsoluteTimeGetCurrent() - startTime)
        return results
    }

    // MARK: - CPU Implementation

    /// CPU-based MMR selection.
    private func cpuMMR(
        candidates: [RetrievalResult],
        queryEmbedding: Embedding,
        candidateEmbeddings: [Embedding],
        limit: Int
    ) -> [RetrievalResult] {
        var selected: [RetrievalResult] = []
        var selectedEmbeddings: [Embedding] = []
        var remaining = Array(zip(candidates, candidateEmbeddings))

        while selected.count < limit && !remaining.isEmpty {
            var bestScore: Float = -.infinity
            var bestIndex = 0

            for (i, (_, embedding)) in remaining.enumerated() {
                let relevance = queryEmbedding.cosineSimilarity(to: embedding)

                let maxSimilarity: Float
                if selectedEmbeddings.isEmpty {
                    maxSimilarity = 0
                } else {
                    maxSimilarity = selectedEmbeddings
                        .map { embedding.cosineSimilarity(to: $0) }
                        .max() ?? 0
                }

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

    // MARK: - GPU Implementation

    #if canImport(Metal)
    /// GPU-accelerated MMR selection.
    ///
    /// Uses Metal compute shaders to parallelize pairwise similarity computation.
    private func gpuMMR(
        candidates: [RetrievalResult],
        queryEmbedding: Embedding,
        candidateEmbeddings: [Embedding],
        limit: Int,
        metal: MetalVectorCompute
    ) async throws -> [RetrievalResult] {
        let dimensions = queryEmbedding.dimensions

        // Precompute relevance scores (query vs all candidates) on GPU
        let candidateVectors = candidateEmbeddings.flatMap { $0.vector }
        let relevanceScores = try await metal.batchCosineSimilarity(
            query: queryEmbedding.vector,
            storedVectors: candidateVectors,
            dimensions: dimensions
        )

        // Iterative MMR selection (GPU for pairwise, CPU for selection)
        var selected: [RetrievalResult] = []
        var selectedIndices: [Int] = []
        var remainingIndices = Array(0..<candidates.count)

        while selected.count < limit && !remainingIndices.isEmpty {
            let diversityPenalties: [Float]

            if selectedIndices.isEmpty {
                // No selected items yet, no diversity penalty
                diversityPenalties = Array(repeating: 0, count: remainingIndices.count)
            } else {
                // Compute pairwise similarity matrix: remaining × selected
                let remainingVectors = remainingIndices.flatMap { candidateEmbeddings[$0].vector }
                let selectedVectors = selectedIndices.flatMap { candidateEmbeddings[$0].vector }

                let similarityMatrix = try await metal.pairwiseSimilarity(
                    candidates: remainingVectors,
                    selected: selectedVectors,
                    dimensions: dimensions
                )

                // Find max similarity per remaining candidate (row-wise max)
                diversityPenalties = try await metal.rowMax(
                    matrix: similarityMatrix,
                    rows: remainingIndices.count,
                    cols: selectedIndices.count
                )
            }

            // Compute MMR scores for remaining candidates
            var bestScore: Float = -.infinity
            var bestLocalIndex = 0

            for (localIdx, globalIdx) in remainingIndices.enumerated() {
                let relevance = relevanceScores[globalIdx]
                let maxSim = diversityPenalties[localIdx]
                let mmrScore = lambda * relevance - (1 - lambda) * maxSim

                if mmrScore > bestScore {
                    bestScore = mmrScore
                    bestLocalIndex = localIdx
                }
            }

            // Select best candidate
            let selectedGlobalIdx = remainingIndices.remove(at: bestLocalIndex)
            selectedIndices.append(selectedGlobalIdx)

            let result = candidates[selectedGlobalIdx]
            selected.append(RetrievalResult(
                chunk: result.chunk,
                score: bestScore,
                metadata: result.metadata
            ))
        }

        return selected
    }
    #endif
}

// MARK: - MMRMetrics

/// Metrics for MMR performance monitoring.
public struct MMRMetrics: Sendable {
    /// Total CPU operations performed.
    public var cpuOperationCount: Int = 0

    /// Total GPU operations performed.
    public var gpuOperationCount: Int = 0

    /// Total CPU operation time in seconds.
    public var cpuOperationTime: Double = 0.0

    /// Total GPU operation time in seconds.
    public var gpuOperationTime: Double = 0.0

    /// Average CPU operation time.
    public var averageCPUTime: Double {
        cpuOperationCount > 0 ? cpuOperationTime / Double(cpuOperationCount) : 0
    }

    /// Average GPU operation time.
    public var averageGPUTime: Double {
        gpuOperationCount > 0 ? gpuOperationTime / Double(gpuOperationCount) : 0
    }

    /// Records a CPU operation.
    public mutating func recordCPUOperation(duration: Double) {
        cpuOperationCount += 1
        cpuOperationTime += duration
    }

    /// Records a GPU operation.
    public mutating func recordGPUOperation(duration: Double) {
        gpuOperationCount += 1
        gpuOperationTime += duration
    }
}
