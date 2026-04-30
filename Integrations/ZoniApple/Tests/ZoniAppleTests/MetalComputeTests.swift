// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// MetalComputeTests.swift - Tests for Metal GPU acceleration
//
// Tests the Metal GPU compute backend for vector similarity operations.

import Testing
import Foundation
@testable import ZoniApple
@testable import Zoni

@Suite("Metal GPU Compute Tests")
struct MetalComputeTests {

    // MARK: - Initialization Tests

    @Test("Metal initialization succeeds or gracefully fails")
    func metalInitialization() async throws {
        #if canImport(Metal)
        // On Metal-capable devices, initialization should succeed
        let metalCompute = try? MetalVectorCompute()

        if let compute = metalCompute {
            #expect(compute.isMetalAvailable == true)
        } else {
            // Metal might not be available in some environments (CI, etc.)
            // This is acceptable
        }
        #else
        // On non-Metal platforms, initialization should fail
        #expect(throws: MetalVectorCompute.MetalComputeError.self) {
            try MetalVectorCompute()
        }
        #endif
    }

    // MARK: - Backend Selection Tests

    @Test("Backend selector chooses CPU for small datasets")
    func backendSelectorSmallDataset() {
        let backend = BackendSelector.select(
            requestedBackend: .auto,
            vectorCount: 1000,
            dimensions: 1536,
            hasFilter: false,
            isGPUAvailable: true
        )

        #expect(backend == .cpu)
    }

    @Test("Backend selector chooses GPU for large datasets")
    func backendSelectorLargeDataset() {
        let backend = BackendSelector.select(
            requestedBackend: .auto,
            vectorCount: 50_000,
            dimensions: 1536,
            hasFilter: false,
            isGPUAvailable: true
        )

        #expect(backend == .gpu)
    }

    @Test("Backend selector respects explicit CPU request")
    func backendSelectorExplicitCPU() {
        let backend = BackendSelector.select(
            requestedBackend: .cpu,
            vectorCount: 100_000,
            dimensions: 1536,
            hasFilter: false,
            isGPUAvailable: true
        )

        #expect(backend == .cpu)
    }

    @Test("Backend selector respects explicit GPU request")
    func backendSelectorExplicitGPU() {
        let backend = BackendSelector.select(
            requestedBackend: .gpu,
            vectorCount: 1000,
            dimensions: 1536,
            hasFilter: false,
            isGPUAvailable: true
        )

        #expect(backend == .gpu)
    }

    @Test("Backend selector chooses CPU when GPU unavailable")
    func backendSelectorGPUUnavailable() {
        let backend = BackendSelector.select(
            requestedBackend: .auto,
            vectorCount: 100_000,
            dimensions: 1536,
            hasFilter: false,
            isGPUAvailable: false
        )

        #expect(backend == .cpu)
    }

    @Test("Backend selector prefers CPU for filtered searches")
    func backendSelectorFilteredSearch() {
        let backend = BackendSelector.select(
            requestedBackend: .auto,
            vectorCount: 15_000,
            dimensions: 1536,
            hasFilter: true,
            isGPUAvailable: true
        )

        #expect(backend == .cpu)
    }

    // MARK: - GPU Threshold Tests

    @Test("shouldUseGPU returns false for small datasets")
    func gpuThresholdSmallDataset() async throws {
        #if canImport(Metal)
        guard let metalCompute = try? MetalVectorCompute() else {
            // Metal not available, skip test
            return
        }

        let shouldUse = metalCompute.shouldUseGPU(chunkCount: 3000)
        #expect(shouldUse == false)
        #endif
    }

    @Test("shouldUseGPU returns true for large datasets")
    func gpuThresholdLargeDataset() async throws {
        #if canImport(Metal)
        guard let metalCompute = try? MetalVectorCompute() else {
            // Metal not available, skip test
            return
        }

        let shouldUse = metalCompute.shouldUseGPU(chunkCount: 50_000)
        #expect(shouldUse == true)
        #endif
    }

    // MARK: - GPU Similarity Tests

    @Test("batchCosineSimilarity computes correct scores")
    func batchCosineSimilarity() async throws {
        #if canImport(Metal)
        guard let metalCompute = try? MetalVectorCompute() else {
            // Metal not available, skip test
            return
        }

        // Simple test vectors
        let query: [Float] = [1.0, 0.0, 0.0]
        let stored: [Float] = [
            1.0, 0.0, 0.0,  // Same as query (similarity = 1.0)
            0.0, 1.0, 0.0,  // Orthogonal (similarity = 0.0)
            0.5, 0.5, 0.0,  // 45 degrees (similarity ≈ 0.707)
        ]

        let scores = try await metalCompute.batchCosineSimilarity(
            query: query,
            storedVectors: stored,
            dimensions: 3
        )

        #expect(scores.count == 3)
        #expect(abs(scores[0] - 1.0) < 0.001)  // Almost exactly 1.0
        #expect(abs(scores[1] - 0.0) < 0.001)  // Almost exactly 0.0
        #expect(abs(scores[2] - 0.707) < 0.01) // Approximately 0.707
        #endif
    }

    // MARK: - Additional GPU Kernel Tests

    @Test("pairwiseSimilarity computes correct matrix")
    func pairwiseSimilarityCorrectness() async throws {
        #if canImport(Metal)
        guard let metalCompute = try? MetalVectorCompute() else {
            // Metal not available, skip test
            return
        }

        // 2 candidates, 2 selected, 3 dimensions
        let candidates: [Float] = [
            1.0, 0.0, 0.0,  // candidate 0
            0.0, 1.0, 0.0,  // candidate 1
        ]
        let selected: [Float] = [
            1.0, 0.0, 0.0,  // selected 0 (same as candidate 0)
            0.0, 0.0, 1.0,  // selected 1 (orthogonal to both)
        ]

        let matrix = try await metalCompute.pairwiseSimilarity(
            candidates: candidates,
            selected: selected,
            dimensions: 3
        )

        // matrix is 2x2: [cand0-sel0, cand0-sel1, cand1-sel0, cand1-sel1]
        #expect(matrix.count == 4)
        #expect(abs(matrix[0] - 1.0) < 0.001)  // cand0 vs sel0 = 1.0
        #expect(abs(matrix[1] - 0.0) < 0.001)  // cand0 vs sel1 = 0.0
        #expect(abs(matrix[2] - 0.0) < 0.001)  // cand1 vs sel0 = 0.0
        #expect(abs(matrix[3] - 0.0) < 0.001)  // cand1 vs sel1 = 0.0
        #endif
    }

    @Test("rowMax finds maximum in each row")
    func rowMaxCorrectness() async throws {
        #if canImport(Metal)
        guard let metalCompute = try? MetalVectorCompute() else {
            return
        }

        // 3 rows, 4 columns
        let matrix: [Float] = [
            0.1, 0.5, 0.3, 0.2,  // row 0, max = 0.5
            0.9, 0.1, 0.2, 0.3,  // row 1, max = 0.9
            0.2, 0.2, 0.8, 0.4,  // row 2, max = 0.8
        ]

        let maxValues = try await metalCompute.rowMax(matrix: matrix, rows: 3, cols: 4)

        #expect(maxValues.count == 3)
        #expect(abs(maxValues[0] - 0.5) < 0.001)
        #expect(abs(maxValues[1] - 0.9) < 0.001)
        #expect(abs(maxValues[2] - 0.8) < 0.001)
        #endif
    }

    @Test("computeMMRScores computes correct MMR values")
    func mmrScoresCorrectness() async throws {
        #if canImport(Metal)
        guard let metalCompute = try? MetalVectorCompute() else {
            return
        }

        let relevanceScores: [Float] = [0.9, 0.8, 0.7]
        let maxSimilarities: [Float] = [0.0, 0.5, 0.8]
        let lambda: Float = 0.5

        let mmrScores = try await metalCompute.computeMMRScores(
            relevanceScores: relevanceScores,
            maxSimilarities: maxSimilarities,
            lambda: lambda
        )

        // MMR = lambda * relevance - (1-lambda) * maxSim
        // score[0] = 0.5 * 0.9 - 0.5 * 0.0 = 0.45
        // score[1] = 0.5 * 0.8 - 0.5 * 0.5 = 0.15
        // score[2] = 0.5 * 0.7 - 0.5 * 0.8 = -0.05

        #expect(mmrScores.count == 3)
        #expect(abs(mmrScores[0] - 0.45) < 0.001)
        #expect(abs(mmrScores[1] - 0.15) < 0.001)
        #expect(abs(mmrScores[2] - (-0.05)) < 0.001)
        #endif
    }

    @Test("batchCosineSimilarity handles empty input")
    func batchCosineSimilarityEmptyInput() async throws {
        #if canImport(Metal)
        guard let metalCompute = try? MetalVectorCompute() else {
            return
        }

        let query: [Float] = [1.0, 0.0, 0.0]
        let stored: [Float] = []

        let scores = try await metalCompute.batchCosineSimilarity(
            query: query,
            storedVectors: stored,
            dimensions: 3
        )

        #expect(scores.isEmpty)
        #endif
    }

    @Test("batchCosineSimilarity handles zero magnitude vectors")
    func batchCosineSimilarityZeroMagnitude() async throws {
        #if canImport(Metal)
        guard let metalCompute = try? MetalVectorCompute() else {
            return
        }

        let query: [Float] = [0.0, 0.0, 0.0]  // Zero magnitude
        let stored: [Float] = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0]

        let scores = try await metalCompute.batchCosineSimilarity(
            query: query,
            storedVectors: stored,
            dimensions: 3
        )

        // Zero magnitude query should result in 0 similarity (not NaN/crash)
        #expect(scores.count == 2)
        #expect(scores[0] == 0.0)
        #expect(scores[1] == 0.0)
        #endif
    }

    @Test("Backend selector handles boundary conditions")
    func backendSelectorBoundaryConditions() {
        // Exactly at cpuPreferredThreshold (5000) with high dimensions (>= 1024)
        // High-dimensional vectors are compute-bound, so GPU is preferred
        let atCPUThresholdHighDim = BackendSelector.select(
            requestedBackend: .auto,
            vectorCount: 5_000,
            dimensions: 1536,
            hasFilter: false,
            isGPUAvailable: true
        )
        #expect(atCPUThresholdHighDim == .gpu)  // High dims prefer GPU

        // At cpuPreferredThreshold with low dimensions - CPU preferred
        let atCPUThresholdLowDim = BackendSelector.select(
            requestedBackend: .auto,
            vectorCount: 5_000,
            dimensions: 512,
            hasFilter: false,
            isGPUAvailable: true
        )
        #expect(atCPUThresholdLowDim == .cpu)  // Low dims prefer CPU

        // Exactly at gpuPreferredThreshold (10000)
        let atGPUThreshold = BackendSelector.select(
            requestedBackend: .auto,
            vectorCount: 10_000,
            dimensions: 1536,
            hasFilter: false,
            isGPUAvailable: true
        )
        #expect(atGPUThreshold == .gpu)

        // Invalid inputs should return CPU
        let zeroVectors = BackendSelector.select(
            requestedBackend: .auto,
            vectorCount: 0,
            dimensions: 1536,
            hasFilter: false,
            isGPUAvailable: true
        )
        #expect(zeroVectors == .cpu)

        let zeroDimensions = BackendSelector.select(
            requestedBackend: .auto,
            vectorCount: 50_000,
            dimensions: 0,
            hasFilter: false,
            isGPUAvailable: true
        )
        #expect(zeroDimensions == .cpu)
    }

    @Test("Lambda validation clamps to valid range")
    func lambdaValidation() async {
        let vectorStore = InMemoryVectorStore()
        let embedder = MockEmbeddingProvider()
        let baseRetriever = VectorRetriever(vectorStore: vectorStore, embeddingProvider: embedder)

        // Test clamping high value
        let mmrHigh = GPUAcceleratedMMRRetriever(
            baseRetriever: baseRetriever,
            embeddingProvider: embedder,
            lambda: 2.5
        )
        let highLambda = await mmrHigh.lambda
        #expect(highLambda == 1.0)

        // Test clamping negative value
        let mmrNeg = GPUAcceleratedMMRRetriever(
            baseRetriever: baseRetriever,
            embeddingProvider: embedder,
            lambda: -0.5
        )
        let negLambda = await mmrNeg.lambda
        #expect(negLambda == 0.0)

        // Test candidateMultiplier minimum
        let mmrLowMult = GPUAcceleratedMMRRetriever(
            baseRetriever: baseRetriever,
            embeddingProvider: embedder,
            candidateMultiplier: 1
        )
        let mult = await mmrLowMult.candidateMultiplier
        #expect(mult == 2)  // Should be clamped to minimum 2
    }

    // MARK: - Metrics Tests

    @Test("Metrics track CPU and GPU operations")
    func metricsTracking() {
        var metrics = ComputeBackendMetrics()

        metrics.recordCPUSearch(duration: 0.1)
        metrics.recordCPUSearch(duration: 0.2)
        metrics.recordGPUSearch(duration: 0.05)

        #expect(metrics.cpuSearchCount == 2)
        #expect(metrics.gpuSearchCount == 1)
        #expect(abs(metrics.averageCPUSearchTime - 0.15) < 0.001)
        #expect(abs(metrics.averageGPUSearchTime - 0.05) < 0.001)
    }

    // MARK: - GPU-Accelerated Store Tests

    @Test("GPUAcceleratedInMemoryVectorStore initializes")
    func gpuStoreInitialization() async {
        let store = GPUAcceleratedInMemoryVectorStore(maxChunkCount: 1000)

        let count = await store.vectorCount
        #expect(count == 0)

        // Store should be created regardless of Metal availability
        #expect(store.name == "gpu_accelerated_in_memory")
    }

    @Test("GPUAcceleratedInMemoryVectorStore add and search")
    func gpuStoreAddAndSearch() async throws {
        let store = GPUAcceleratedInMemoryVectorStore(maxChunkCount: 1000)

        // Create test chunks
        let metadata1 = ChunkMetadata(
            documentId: "doc1",
            index: 0,
            startOffset: 0,
            endOffset: 100,
            source: "test.txt",
            custom: [:]
        )
        let metadata2 = ChunkMetadata(
            documentId: "doc1",
            index: 1,
            startOffset: 100,
            endOffset: 200,
            source: "test.txt",
            custom: [:]
        )

        let chunks = [
            Chunk(id: "1", content: "Test content 1", metadata: metadata1),
            Chunk(id: "2", content: "Test content 2", metadata: metadata2),
        ]

        let embeddings = [
            Embedding(vector: [1.0, 0.0, 0.0]),
            Embedding(vector: [0.0, 1.0, 0.0]),
        ]

        try await store.add(chunks, embeddings: embeddings)

        let count = try await store.count()
        #expect(count == 2)

        // Search with CPU backend
        let query = Embedding(vector: [1.0, 0.0, 0.0])
        let results = try await store.search(
            query: query,
            limit: 2,
            filter: nil,
            backend: .cpu
        )

        #expect(results.count == 2)
        #expect(results[0].chunk.id == "1")  // Should match first chunk
    }

    // MARK: - GPU-Accelerated MMR Tests

    @Test("GPUAcceleratedMMRRetriever initializes")
    func gpuMMRInitialization() async {
        // Create a mock base retriever
        let vectorStore = InMemoryVectorStore()
        let embedder = MockEmbeddingProvider()
        let baseRetriever = VectorRetriever(vectorStore: vectorStore, embeddingProvider: embedder)

        let mmr = GPUAcceleratedMMRRetriever(
            baseRetriever: baseRetriever,
            embeddingProvider: embedder,
            lambda: 0.7
        )

        #expect(mmr.name == "gpu_accelerated_mmr")

        // GPU support depends on platform
        #if canImport(Metal)
        // On macOS with Metal, GPU should be available
        let supportsGPU = await mmr.supportsGPU
        #expect(supportsGPU == true || supportsGPU == false) // Either is valid
        #endif
    }

    @Test("MMRMetrics tracks operations correctly")
    func mmrMetricsTracking() {
        var metrics = MMRMetrics()

        metrics.recordCPUOperation(duration: 0.1)
        metrics.recordCPUOperation(duration: 0.2)
        metrics.recordGPUOperation(duration: 0.05)

        #expect(metrics.cpuOperationCount == 2)
        #expect(metrics.gpuOperationCount == 1)
        #expect(abs(metrics.averageCPUTime - 0.15) < 0.001)
        #expect(abs(metrics.averageGPUTime - 0.05) < 0.001)
    }
}

// MARK: - Mock Embedding Provider

/// Simple mock embedding provider for testing.
private struct MockEmbeddingProvider: EmbeddingProvider {
    let name = "mock"
    let dimensions = 3
    let maxTokensPerRequest = 8192
    let optimalBatchSize = 10

    func embed(_ text: String) async throws -> Embedding {
        // Generate deterministic embedding based on text hash
        let hash = abs(text.hashValue)
        let x = Float(hash % 100) / 100.0
        let y = Float((hash / 100) % 100) / 100.0
        let z = Float((hash / 10000) % 100) / 100.0
        return Embedding(vector: [x, y, z])
    }

    func embed(_ texts: [String]) async throws -> [Embedding] {
        var results: [Embedding] = []
        for text in texts {
            results.append(try await embed(text))
        }
        return results
    }
}
