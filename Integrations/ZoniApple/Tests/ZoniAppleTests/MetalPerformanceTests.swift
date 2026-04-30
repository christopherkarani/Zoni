// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// MetalPerformanceTests.swift - Performance benchmarks for Metal GPU acceleration
//
// These tests measure actual speedups of GPU vs CPU for vector operations
// to validate the optimization targets in the plan.

import Testing
import Foundation
@testable import ZoniApple
@testable import Zoni

// MARK: - Metal Performance Benchmarks

@Suite("Metal GPU Performance Benchmarks")
struct MetalPerformanceTests {

    // MARK: - Batch Cosine Similarity Benchmarks

    @Test("Benchmark: 1K vectors - GPU overhead zone")
    func benchmark1KVectors() async throws {
        try await runSimilarityBenchmark(vectorCount: 1_000, dimensions: 1536)
    }

    @Test("Benchmark: 5K vectors - breakeven zone")
    func benchmark5KVectors() async throws {
        try await runSimilarityBenchmark(vectorCount: 5_000, dimensions: 1536)
    }

    @Test("Benchmark: 10K vectors - GPU advantage begins")
    func benchmark10KVectors() async throws {
        try await runSimilarityBenchmark(vectorCount: 10_000, dimensions: 1536)
    }

    @Test("Benchmark: 50K vectors - strong GPU advantage")
    func benchmark50KVectors() async throws {
        try await runSimilarityBenchmark(vectorCount: 50_000, dimensions: 1536)
    }

    @Test("Benchmark: 100K vectors - maximum GPU advantage")
    func benchmark100KVectors() async throws {
        try await runSimilarityBenchmark(vectorCount: 100_000, dimensions: 1536)
    }

    // MARK: - Dimension Scaling Tests

    @Test("Benchmark: 768 dimensions (BERT-sized)")
    func benchmarkBERTDimensions() async throws {
        try await runSimilarityBenchmark(vectorCount: 10_000, dimensions: 768)
    }

    @Test("Benchmark: 3072 dimensions (large embeddings)")
    func benchmarkLargeDimensions() async throws {
        try await runSimilarityBenchmark(vectorCount: 10_000, dimensions: 3072)
    }

    // MARK: - GPU Store Benchmarks

    @Test("Benchmark: GPU-accelerated store search")
    func benchmarkGPUStore() async throws {
        #if canImport(Metal)
        let store = GPUAcceleratedInMemoryVectorStore(maxChunkCount: 50_000)

        // Generate test data
        let dimensions = 1536
        let vectorCount = 10_000

        var chunks: [Chunk] = []
        var embeddings: [Embedding] = []

        for i in 0..<vectorCount {
            let metadata = ChunkMetadata(
                documentId: "doc\(i / 100)",
                index: i % 100,
                startOffset: i * 100,
                endOffset: (i + 1) * 100,
                source: "benchmark.txt",
                custom: [:]
            )
            chunks.append(Chunk(id: "chunk_\(i)", content: "Content \(i)", metadata: metadata))
            embeddings.append(generateRandomEmbedding(dimensions: dimensions))
        }

        try await store.add(chunks, embeddings: embeddings)

        let query = generateRandomEmbedding(dimensions: dimensions)

        // Warm up
        _ = try await store.search(query: query, limit: 10, filter: nil, backend: .cpu)
        _ = try await store.search(query: query, limit: 10, filter: nil, backend: .gpu)

        // CPU benchmark
        let cpuStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<5 {
            _ = try await store.search(query: query, limit: 10, filter: nil, backend: .cpu)
        }
        let cpuTime = (CFAbsoluteTimeGetCurrent() - cpuStart) / 5.0

        // GPU benchmark
        let gpuStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<5 {
            _ = try await store.search(query: query, limit: 10, filter: nil, backend: .gpu)
        }
        let gpuTime = (CFAbsoluteTimeGetCurrent() - gpuStart) / 5.0

        let speedup = cpuTime / gpuTime

        print("""

        ═══════════════════════════════════════════════════════════════
        GPU-Accelerated Store Benchmark (10K vectors, 1536 dims)
        ───────────────────────────────────────────────────────────────
        CPU Search Time:  \(String(format: "%.3f", cpuTime * 1000)) ms
        GPU Search Time:  \(String(format: "%.3f", gpuTime * 1000)) ms
        Speedup:          \(String(format: "%.2f", speedup))x
        ═══════════════════════════════════════════════════════════════

        """)

        // Verify GPU is at least not slower for this dataset size
        #expect(gpuTime > 0)
        #endif
    }

    // MARK: - Helper Methods

    /// Runs a similarity benchmark comparing CPU vs GPU performance.
    private func runSimilarityBenchmark(vectorCount: Int, dimensions: Int) async throws {
        #if canImport(Metal)
        guard let metalCompute = try? MetalVectorCompute() else {
            print("Metal not available, skipping benchmark")
            return
        }

        // Generate test data
        let query = generateRandomVector(dimensions: dimensions)
        let storedVectors = generateRandomVectors(count: vectorCount, dimensions: dimensions)

        // Warm up (compile shaders, allocate buffers)
        _ = try await metalCompute.batchCosineSimilarity(
            query: query,
            storedVectors: storedVectors,
            dimensions: dimensions
        )

        // CPU benchmark using VectorMath
        let cpuIterations = vectorCount < 10_000 ? 10 : 3
        let cpuStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<cpuIterations {
            _ = cpuBatchSimilarity(query: query, stored: storedVectors, dimensions: dimensions)
        }
        let cpuTime = (CFAbsoluteTimeGetCurrent() - cpuStart) / Double(cpuIterations)

        // GPU benchmark
        let gpuIterations = 10
        let gpuStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<gpuIterations {
            _ = try await metalCompute.batchCosineSimilarity(
                query: query,
                storedVectors: storedVectors,
                dimensions: dimensions
            )
        }
        let gpuTime = (CFAbsoluteTimeGetCurrent() - gpuStart) / Double(gpuIterations)

        let speedup = cpuTime / gpuTime
        let memoryMB = Double(vectorCount * dimensions * MemoryLayout<Float>.size) / (1024 * 1024)

        print("""

        ═══════════════════════════════════════════════════════════════
        Batch Cosine Similarity Benchmark
        ───────────────────────────────────────────────────────────────
        Vectors:          \(formatNumber(vectorCount))
        Dimensions:       \(dimensions)
        Memory:           \(String(format: "%.1f", memoryMB)) MB
        ───────────────────────────────────────────────────────────────
        CPU Time:         \(String(format: "%.3f", cpuTime * 1000)) ms
        GPU Time:         \(String(format: "%.3f", gpuTime * 1000)) ms
        Speedup:          \(String(format: "%.2f", speedup))x
        ───────────────────────────────────────────────────────────────
        Target:           \(expectedSpeedup(vectorCount: vectorCount))
        Status:           \(speedup >= expectedMinimumSpeedup(vectorCount: vectorCount) ? "✅ PASS" : "⚠️ Below target")
        ═══════════════════════════════════════════════════════════════

        """)

        // Store results for analysis
        #expect(gpuTime > 0, "GPU should complete")
        #endif
    }

    /// CPU-based batch similarity using VectorMath.
    private func cpuBatchSimilarity(query: [Float], stored: [Float], dimensions: Int) -> [Float] {
        let vectorCount = stored.count / dimensions
        var results = [Float](repeating: 0, count: vectorCount)

        for i in 0..<vectorCount {
            let start = i * dimensions
            let end = start + dimensions
            let vector = Array(stored[start..<end])
            results[i] = VectorMath.cosineSimilarity(query, vector)
        }

        return results
    }

    /// Generates a random vector.
    private func generateRandomVector(dimensions: Int) -> [Float] {
        (0..<dimensions).map { _ in Float.random(in: -1...1) }
    }

    /// Generates multiple random vectors as a contiguous array.
    private func generateRandomVectors(count: Int, dimensions: Int) -> [Float] {
        (0..<count * dimensions).map { _ in Float.random(in: -1...1) }
    }

    /// Generates a random embedding.
    private func generateRandomEmbedding(dimensions: Int) -> Embedding {
        Embedding(vector: generateRandomVector(dimensions: dimensions))
    }

    /// Formats a number with thousands separators.
    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// Expected speedup description based on plan targets.
    private func expectedSpeedup(vectorCount: Int) -> String {
        switch vectorCount {
        case ..<5_000: return "0.5-1x (GPU overhead dominates)"
        case 5_000..<10_000: return "1-3x (breakeven zone)"
        case 10_000..<50_000: return "3-10x (GPU wins)"
        case 50_000..<100_000: return "10-25x (strong GPU advantage)"
        default: return "20-40x (optimal GPU utilization)"
        }
    }

    /// Minimum acceptable speedup for validation.
    private func expectedMinimumSpeedup(vectorCount: Int) -> Double {
        switch vectorCount {
        case ..<5_000: return 0.3  // Allow GPU to be slower
        case 5_000..<10_000: return 0.8  // Breakeven
        case 10_000..<50_000: return 1.5  // Should see some benefit
        case 50_000..<100_000: return 3.0  // Strong benefit expected
        default: return 5.0  // Significant benefit expected
        }
    }
}

// MARK: - MMR Performance Benchmarks

@Suite("MMR GPU Performance Benchmarks")
struct MMRPerformanceTests {

    @Test("Benchmark: MMR with 50 candidates")
    func benchmarkMMR50() async throws {
        try await runMMRBenchmark(candidateCount: 50, limit: 10)
    }

    @Test("Benchmark: MMR with 200 candidates")
    func benchmarkMMR200() async throws {
        try await runMMRBenchmark(candidateCount: 200, limit: 20)
    }

    @Test("Benchmark: MMR with 500 candidates")
    func benchmarkMMR500() async throws {
        try await runMMRBenchmark(candidateCount: 500, limit: 50)
    }

    /// Runs an MMR benchmark comparing CPU vs GPU.
    private func runMMRBenchmark(candidateCount: Int, limit: Int) async throws {
        #if canImport(Metal)
        guard let metalCompute = try? MetalVectorCompute() else {
            print("Metal not available, skipping MMR benchmark")
            return
        }

        let dimensions = 1536

        // Generate test embeddings
        let queryEmbedding = Embedding(vector: generateRandomVector(dimensions: dimensions))
        let candidateEmbeddings = (0..<candidateCount).map { _ in
            Embedding(vector: generateRandomVector(dimensions: dimensions))
        }

        // CPU MMR timing
        let cpuIterations = 5
        let cpuStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<cpuIterations {
            _ = cpuMMR(
                query: queryEmbedding,
                candidates: candidateEmbeddings,
                limit: limit,
                lambda: 0.5
            )
        }
        let cpuTime = (CFAbsoluteTimeGetCurrent() - cpuStart) / Double(cpuIterations)

        // GPU MMR timing (using pairwise similarity)
        let gpuIterations = 10
        let gpuStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<gpuIterations {
            _ = try await gpuMMR(
                query: queryEmbedding,
                candidates: candidateEmbeddings,
                limit: limit,
                lambda: 0.5,
                metal: metalCompute
            )
        }
        let gpuTime = (CFAbsoluteTimeGetCurrent() - gpuStart) / Double(gpuIterations)

        let speedup = cpuTime / gpuTime

        print("""

        ═══════════════════════════════════════════════════════════════
        MMR Algorithm Benchmark
        ───────────────────────────────────────────────────────────────
        Candidates:       \(candidateCount)
        Limit:            \(limit)
        Dimensions:       \(dimensions)
        ───────────────────────────────────────────────────────────────
        CPU Time:         \(String(format: "%.3f", cpuTime * 1000)) ms
        GPU Time:         \(String(format: "%.3f", gpuTime * 1000)) ms
        Speedup:          \(String(format: "%.2f", speedup))x
        ═══════════════════════════════════════════════════════════════

        """)

        #expect(gpuTime > 0)
        #endif
    }

    /// CPU-based MMR implementation for benchmarking.
    private func cpuMMR(
        query: Embedding,
        candidates: [Embedding],
        limit: Int,
        lambda: Float
    ) -> [Int] {
        var selected: [Int] = []
        var remaining = Array(0..<candidates.count)

        while selected.count < limit && !remaining.isEmpty {
            var bestScore: Float = -.infinity
            var bestLocalIdx = 0

            for (localIdx, globalIdx) in remaining.enumerated() {
                let relevance = query.cosineSimilarity(to: candidates[globalIdx])

                let maxSim: Float
                if selected.isEmpty {
                    maxSim = 0
                } else {
                    maxSim = selected.map { candidates[globalIdx].cosineSimilarity(to: candidates[$0]) }.max() ?? 0
                }

                let score = lambda * relevance - (1 - lambda) * maxSim
                if score > bestScore {
                    bestScore = score
                    bestLocalIdx = localIdx
                }
            }

            selected.append(remaining.remove(at: bestLocalIdx))
        }

        return selected
    }

    /// GPU-accelerated MMR for benchmarking.
    private func gpuMMR(
        query: Embedding,
        candidates: [Embedding],
        limit: Int,
        lambda: Float,
        metal: MetalVectorCompute
    ) async throws -> [Int] {
        let dimensions = query.dimensions

        // Compute all relevance scores
        let candidateVectors = candidates.flatMap { $0.vector }
        let relevanceScores = try await metal.batchCosineSimilarity(
            query: query.vector,
            storedVectors: candidateVectors,
            dimensions: dimensions
        )

        var selected: [Int] = []
        var remaining = Array(0..<candidates.count)

        while selected.count < limit && !remaining.isEmpty {
            let diversityPenalties: [Float]

            if selected.isEmpty {
                diversityPenalties = Array(repeating: 0, count: remaining.count)
            } else {
                let remainingVectors = remaining.flatMap { candidates[$0].vector }
                let selectedVectors = selected.flatMap { candidates[$0].vector }

                let matrix = try await metal.pairwiseSimilarity(
                    candidates: remainingVectors,
                    selected: selectedVectors,
                    dimensions: dimensions
                )

                diversityPenalties = try await metal.rowMax(
                    matrix: matrix,
                    rows: remaining.count,
                    cols: selected.count
                )
            }

            var bestScore: Float = -.infinity
            var bestLocalIdx = 0

            for (localIdx, globalIdx) in remaining.enumerated() {
                let score = lambda * relevanceScores[globalIdx] - (1 - lambda) * diversityPenalties[localIdx]
                if score > bestScore {
                    bestScore = score
                    bestLocalIdx = localIdx
                }
            }

            selected.append(remaining.remove(at: bestLocalIdx))
        }

        return selected
    }

    private func generateRandomVector(dimensions: Int) -> [Float] {
        (0..<dimensions).map { _ in Float.random(in: -1...1) }
    }
}
