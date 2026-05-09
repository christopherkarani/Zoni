// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// MetalVectorCompute.swift - GPU-accelerated vector similarity computation
//
// This actor provides thread-safe access to Metal GPU compute resources for
// high-performance vector similarity search. It automatically handles buffer
// management, shader compilation, and provides an async Swift interface.

#if canImport(Metal)
import Metal
#endif
import Foundation
import Zoni
import Accelerate

// MARK: - MetalVectorCompute

/// GPU-accelerated vector similarity computation using Metal.
///
/// `MetalVectorCompute` provides high-performance batch similarity computation
/// for vector stores with large datasets. It automatically manages GPU buffers
/// and provides an async interface compatible with Swift concurrency.
///
/// ## Performance Characteristics
/// - **< 5k vectors**: CPU may be faster (GPU dispatch overhead)
/// - **5k-10k vectors**: Breakeven zone
/// - **> 10k vectors**: GPU provides significant speedup (3-50x depending on scale)
///
/// ## Thread Safety
/// Implemented as an `actor` to ensure safe concurrent access. All Metal
/// operations are serialized through the actor's isolation.
///
/// ## Example Usage
/// ```swift
/// let metalCompute = try MetalVectorCompute()
///
/// // Check if GPU is available and beneficial
/// if metalCompute.shouldUseGPU(chunkCount: 50_000) {
///     let scores = try await metalCompute.batchCosineSimilarity(
///         query: queryVector,
///         storedVectors: embeddingsMatrix,
///         dimensions: 1536
///     )
/// }
/// ```
public actor MetalVectorCompute {

    // MARK: - Types

    /// Errors specific to Metal compute operations.
    public enum MetalComputeError: Error, LocalizedError {
        case metalNotAvailable
        case deviceCreationFailed
        case commandQueueCreationFailed
        case shaderCompilationFailed(String)
        case pipelineCreationFailed(String)
        case bufferCreationFailed(String)
        case commandBufferFailed(String)
        case invalidDimensions(String)

        public var errorDescription: String? {
            switch self {
            case .metalNotAvailable:
                return "Metal is not available on this device"
            case .deviceCreationFailed:
                return "Failed to create Metal device"
            case .commandQueueCreationFailed:
                return "Failed to create Metal command queue"
            case .shaderCompilationFailed(let reason):
                return "Shader compilation failed: \(reason)"
            case .pipelineCreationFailed(let reason):
                return "Pipeline creation failed: \(reason)"
            case .bufferCreationFailed(let reason):
                return "Buffer creation failed: \(reason)"
            case .commandBufferFailed(let reason):
                return "Command buffer execution failed: \(reason)"
            case .invalidDimensions(let reason):
                return "Invalid dimensions: \(reason)"
            }
        }
    }

    // MARK: - Properties

    #if canImport(Metal)
    /// The Metal device (GPU).
    /// Note: Metal types are thread-safe and documented as safe for concurrent access.
    /// Using nonisolated(unsafe) is appropriate because these are immutable after init.
    private nonisolated(unsafe) let device: MTLDevice

    /// Command queue for submitting GPU work.
    private nonisolated(unsafe) let commandQueue: MTLCommandQueue

    /// Compute pipeline for batch cosine similarity.
    private nonisolated(unsafe) let cosineSimilarityPipeline: MTLComputePipelineState

    /// Compute pipeline for batch dot product.
    private nonisolated(unsafe) let dotProductPipeline: MTLComputePipelineState

    /// Compute pipeline for pairwise similarity (MMR).
    private nonisolated(unsafe) let pairwiseSimilarityPipeline: MTLComputePipelineState

    /// Compute pipeline for row-wise max (MMR).
    private nonisolated(unsafe) let rowMaxPipeline: MTLComputePipelineState

    /// Compute pipeline for MMR score computation.
    private nonisolated(unsafe) let mmrScoresPipeline: MTLComputePipelineState

    /// Compute pipeline for batch magnitude.
    private nonisolated(unsafe) let magnitudePipeline: MTLComputePipelineState

    /// Compute pipeline for adjacent vector similarity.
    private nonisolated(unsafe) let adjacentSimilarityPipeline: MTLComputePipelineState

    /// Maximum threads per threadgroup for this device.
    private let maxThreadsPerThreadgroup: Int
    #endif

    /// Whether Metal is available on this device.
    public nonisolated let isMetalAvailable: Bool

    /// Threshold for GPU usage (vectors below this use CPU).
    public static let gpuThreshold: Int = 10_000

    /// Threshold below which GPU overhead makes it slower than CPU.
    public static let gpuMinimumEffectiveCount: Int = 5_000

    // MARK: - Initialization

    /// Creates a new MetalVectorCompute instance.
    ///
    /// - Throws: `MetalComputeError` if Metal initialization fails.
    public init() throws {
        #if canImport(Metal)
        // Get the default Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            self.isMetalAvailable = false
            throw MetalComputeError.metalNotAvailable
        }
        self.device = device

        // Create command queue
        guard let commandQueue = device.makeCommandQueue() else {
            self.isMetalAvailable = false
            throw MetalComputeError.commandQueueCreationFailed
        }
        self.commandQueue = commandQueue

        // Compile shader library from source
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            self.isMetalAvailable = false
            throw MetalComputeError.shaderCompilationFailed(error.localizedDescription)
        }

        // Create compute pipelines for each kernel
        func makePipeline(_ name: String) throws -> MTLComputePipelineState {
            guard let function = library.makeFunction(name: name) else {
                throw MetalComputeError.pipelineCreationFailed("Function '\(name)' not found")
            }
            return try device.makeComputePipelineState(function: function)
        }

        self.cosineSimilarityPipeline = try makePipeline("batchCosineSimilarity")
        self.dotProductPipeline = try makePipeline("batchDotProduct")
        self.pairwiseSimilarityPipeline = try makePipeline("pairwiseSimilarity")
        self.rowMaxPipeline = try makePipeline("rowMax")
        self.mmrScoresPipeline = try makePipeline("computeMMRScores")
        self.magnitudePipeline = try makePipeline("batchMagnitude")
        self.adjacentSimilarityPipeline = try makePipeline("adjacentCosineSimilarity")

        self.maxThreadsPerThreadgroup = cosineSimilarityPipeline.maxTotalThreadsPerThreadgroup
        self.isMetalAvailable = true

        #else
        self.isMetalAvailable = false
        throw MetalComputeError.metalNotAvailable
        #endif
    }

    // MARK: - Public API

    /// Determines whether GPU should be used for the given workload.
    ///
    /// - Parameters:
    ///   - chunkCount: Number of vectors to compare against.
    ///   - hasFilter: Whether a metadata filter is applied.
    /// - Returns: `true` if GPU would be beneficial, `false` for CPU.
    public nonisolated func shouldUseGPU(chunkCount: Int, hasFilter: Bool = false) -> Bool {
        // Filters require CPU evaluation, so GPU is only beneficial for large filtered sets
        guard isMetalAvailable else { return false }
        guard !hasFilter else { return chunkCount >= Self.gpuThreshold * 2 }
        return chunkCount >= Self.gpuMinimumEffectiveCount
    }

    /// Computes cosine similarity between a query vector and multiple stored vectors.
    ///
    /// This is the primary search operation. Each stored vector is compared against
    /// the query in parallel on the GPU.
    ///
    /// - Parameters:
    ///   - query: The query vector (length = dimensions).
    ///   - storedVectors: Contiguous array of stored vectors (length = count × dimensions).
    ///   - dimensions: Number of dimensions per vector.
    /// - Returns: Array of similarity scores (one per stored vector).
    /// - Throws: `MetalComputeError` if GPU computation fails.
    #if canImport(Metal)
    public func batchCosineSimilarity(
        query: [Float],
        storedVectors: [Float],
        dimensions: Int
    ) async throws -> [Float] {
        guard !storedVectors.isEmpty else { return [] }
        guard query.count == dimensions else {
            throw MetalComputeError.invalidDimensions(
                "Query has \(query.count) dimensions, expected \(dimensions)"
            )
        }

        let vectorCount = storedVectors.count / dimensions
        guard storedVectors.count == vectorCount * dimensions else {
            throw MetalComputeError.invalidDimensions(
                "Stored vectors length \(storedVectors.count) is not divisible by dimensions \(dimensions)"
            )
        }

        // Precompute query magnitude on CPU (avoids redundant GPU computation)
        var queryMagnitude: Float = 0.0
        vDSP_svesq(query, 1, &queryMagnitude, vDSP_Length(query.count))
        queryMagnitude = sqrt(queryMagnitude)

        // Create GPU buffers
        guard let queryBuffer = device.makeBuffer(
            bytes: query,
            length: query.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        ) else {
            throw MetalComputeError.bufferCreationFailed("Query buffer")
        }

        guard let storedBuffer = device.makeBuffer(
            bytes: storedVectors,
            length: storedVectors.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        ) else {
            throw MetalComputeError.bufferCreationFailed("Stored vectors buffer")
        }

        guard let resultsBuffer = device.makeBuffer(
            length: vectorCount * MemoryLayout<Float>.size,
            options: .storageModeShared
        ) else {
            throw MetalComputeError.bufferCreationFailed("Results buffer")
        }

        // Parameters struct
        var params = CosineSimilarityParams(
            dimensions: UInt32(dimensions),
            vectorCount: UInt32(vectorCount),
            queryMagnitude: queryMagnitude
        )

        guard let paramsBuffer = device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<CosineSimilarityParams>.size,
            options: .storageModeShared
        ) else {
            throw MetalComputeError.bufferCreationFailed("Params buffer")
        }

        // Execute compute
        try await executeCompute(
            pipeline: cosineSimilarityPipeline,
            buffers: [queryBuffer, storedBuffer, resultsBuffer, paramsBuffer],
            threadCount: vectorCount
        )

        // Read results
        let resultsPointer = resultsBuffer.contents().bindMemory(to: Float.self, capacity: vectorCount)
        return Array(UnsafeBufferPointer(start: resultsPointer, count: vectorCount))
    }
    #endif

    /// Computes pairwise similarity matrix between candidates and selected vectors.
    ///
    /// Used by MMR for computing diversity penalties.
    ///
    /// - Parameters:
    ///   - candidates: Candidate vectors (n × d flattened).
    ///   - selected: Already-selected vectors (k × d flattened).
    ///   - dimensions: Vector dimensions.
    /// - Returns: Flattened n×k similarity matrix (row-major).
    #if canImport(Metal)
    public func pairwiseSimilarity(
        candidates: [Float],
        selected: [Float],
        dimensions: Int
    ) async throws -> [Float] {
        let n = candidates.count / dimensions
        let k = selected.count / dimensions

        guard n > 0 && k > 0 else { return [] }

        // Create buffers
        guard let candidatesBuffer = device.makeBuffer(
            bytes: candidates,
            length: candidates.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        ),
        let selectedBuffer = device.makeBuffer(
            bytes: selected,
            length: selected.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        ),
        let resultsBuffer = device.makeBuffer(
            length: n * k * MemoryLayout<Float>.size,
            options: .storageModeShared
        ) else {
            throw MetalComputeError.bufferCreationFailed("Pairwise similarity buffers")
        }

        var params = PairwiseSimilarityParams(
            dimensions: UInt32(dimensions),
            candidateCount: UInt32(n),
            selectedCount: UInt32(k)
        )

        guard let paramsBuffer = device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<PairwiseSimilarityParams>.size,
            options: .storageModeShared
        ) else {
            throw MetalComputeError.bufferCreationFailed("Params buffer")
        }

        // Execute with 2D grid
        try await executeCompute2D(
            pipeline: pairwiseSimilarityPipeline,
            buffers: [candidatesBuffer, selectedBuffer, resultsBuffer, paramsBuffer],
            width: n,
            height: k
        )

        let resultsPointer = resultsBuffer.contents().bindMemory(to: Float.self, capacity: n * k)
        return Array(UnsafeBufferPointer(start: resultsPointer, count: n * k))
    }
    #endif

    /// Computes the maximum value in each row of a matrix.
    ///
    /// Used after pairwiseSimilarity for MMR diversity penalty.
    #if canImport(Metal)
    public func rowMax(matrix: [Float], rows: Int, cols: Int) async throws -> [Float] {
        guard rows > 0 && cols > 0 else { return [] }

        guard let matrixBuffer = device.makeBuffer(
            bytes: matrix,
            length: matrix.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        ),
        let resultsBuffer = device.makeBuffer(
            length: rows * MemoryLayout<Float>.size,
            options: .storageModeShared
        ) else {
            throw MetalComputeError.bufferCreationFailed("Row max buffers")
        }

        var n = UInt32(rows)
        var k = UInt32(cols)

        guard let nBuffer = device.makeBuffer(bytes: &n, length: 4, options: .storageModeShared),
              let kBuffer = device.makeBuffer(bytes: &k, length: 4, options: .storageModeShared) else {
            throw MetalComputeError.bufferCreationFailed("Row max param buffers")
        }

        try await executeCompute(
            pipeline: rowMaxPipeline,
            buffers: [matrixBuffer, resultsBuffer, nBuffer, kBuffer],
            threadCount: rows
        )

        let resultsPointer = resultsBuffer.contents().bindMemory(to: Float.self, capacity: rows)
        return Array(UnsafeBufferPointer(start: resultsPointer, count: rows))
    }
    #endif

    /// Computes MMR scores from relevance and diversity components.
    #if canImport(Metal)
    public func computeMMRScores(
        relevanceScores: [Float],
        maxSimilarities: [Float],
        lambda: Float
    ) async throws -> [Float] {
        let n = relevanceScores.count
        guard n == maxSimilarities.count else {
            throw MetalComputeError.invalidDimensions("Relevance and similarity arrays must match")
        }
        guard n > 0 else { return [] }

        guard let relevanceBuffer = device.makeBuffer(
            bytes: relevanceScores,
            length: n * MemoryLayout<Float>.size,
            options: .storageModeShared
        ),
        let similarityBuffer = device.makeBuffer(
            bytes: maxSimilarities,
            length: n * MemoryLayout<Float>.size,
            options: .storageModeShared
        ),
        let resultsBuffer = device.makeBuffer(
            length: n * MemoryLayout<Float>.size,
            options: .storageModeShared
        ) else {
            throw MetalComputeError.bufferCreationFailed("MMR score buffers")
        }

        var lambdaVal = lambda
        var count = UInt32(n)

        guard let lambdaBuffer = device.makeBuffer(bytes: &lambdaVal, length: 4, options: .storageModeShared),
              let countBuffer = device.makeBuffer(bytes: &count, length: 4, options: .storageModeShared) else {
            throw MetalComputeError.bufferCreationFailed("MMR param buffers")
        }

        try await executeCompute(
            pipeline: mmrScoresPipeline,
            buffers: [relevanceBuffer, similarityBuffer, resultsBuffer, lambdaBuffer, countBuffer],
            threadCount: n
        )

        let resultsPointer = resultsBuffer.contents().bindMemory(to: Float.self, capacity: n)
        return Array(UnsafeBufferPointer(start: resultsPointer, count: n))
    }
    #endif


    /// Computes cosine similarity between adjacent pairs of vectors (v[i] vs v[i+1]).
    /// Returns N-1 scores.
    #if canImport(Metal)
    public func adjacentCosineSimilarity(
        vectors: [Float],
        dimensions: Int
    ) async throws -> [Float] {
        let vectorCount = vectors.count / dimensions
        guard vectorCount >= 2 else { return [] }
        let comparisonCount = vectorCount - 1
        
        guard let vectorBuffer = device.makeBuffer(
            bytes: vectors,
            length: vectors.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        ),
        let resultsBuffer = device.makeBuffer(
            length: comparisonCount * MemoryLayout<Float>.size,
            options: .storageModeShared
        ) else {
            throw MetalComputeError.bufferCreationFailed("Adjacent similarity buffers")
        }
        
        var params = AdjacentSimilarityParams(
            dimensions: UInt32(dimensions),
            comparisonCount: UInt32(comparisonCount)
        )
        
        guard let paramsBuffer = device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<AdjacentSimilarityParams>.size,
            options: .storageModeShared
        ) else {
            throw MetalComputeError.bufferCreationFailed("Params buffer")
        }
        
        try await executeCompute(
            pipeline: adjacentSimilarityPipeline,
            buffers: [vectorBuffer, resultsBuffer, paramsBuffer],
            threadCount: comparisonCount
        )
        
        let resultsPointer = resultsBuffer.contents().bindMemory(to: Float.self, capacity: comparisonCount)
        return Array(UnsafeBufferPointer(start: resultsPointer, count: comparisonCount))
    }
    #endif

    // MARK: - Private Implementation

    #if canImport(Metal)
    /// Executes a 1D compute kernel.
    private func executeCompute(
        pipeline: MTLComputePipelineState,
        buffers: [MTLBuffer],
        threadCount: Int
    ) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                continuation.resume(throwing: MetalComputeError.commandBufferFailed("Creation"))
                return
            }

            guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
                continuation.resume(throwing: MetalComputeError.commandBufferFailed("Encoder creation"))
                return
            }

            encoder.setComputePipelineState(pipeline)

            for (index, buffer) in buffers.enumerated() {
                encoder.setBuffer(buffer, offset: 0, index: index)
            }

            let threadsPerGroup = min(maxThreadsPerThreadgroup, threadCount)
            let threadgroupCount = (threadCount + threadsPerGroup - 1) / threadsPerGroup

            encoder.dispatchThreadgroups(
                MTLSize(width: threadgroupCount, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: threadsPerGroup, height: 1, depth: 1)
            )

            encoder.endEncoding()

            commandBuffer.addCompletedHandler { buffer in
                if let error = buffer.error {
                    continuation.resume(throwing: MetalComputeError.commandBufferFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }

            commandBuffer.commit()
        }
    }

    /// Executes a 2D compute kernel.
    private func executeCompute2D(
        pipeline: MTLComputePipelineState,
        buffers: [MTLBuffer],
        width: Int,
        height: Int
    ) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                continuation.resume(throwing: MetalComputeError.commandBufferFailed("Creation"))
                return
            }

            guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
                continuation.resume(throwing: MetalComputeError.commandBufferFailed("Encoder creation"))
                return
            }

            encoder.setComputePipelineState(pipeline)

            for (index, buffer) in buffers.enumerated() {
                encoder.setBuffer(buffer, offset: 0, index: index)
            }

            let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
            let threadgroupCount = MTLSize(
                width: (width + 15) / 16,
                height: (height + 15) / 16,
                depth: 1
            )

            encoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
            encoder.endEncoding()

            commandBuffer.addCompletedHandler { buffer in
                if let error = buffer.error {
                    continuation.resume(throwing: MetalComputeError.commandBufferFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }

            commandBuffer.commit()
        }
    }
    #endif
}

// MARK: - Parameter Structs (Swift-side)

#if canImport(Metal)
/// Parameters for batch cosine similarity (must match Metal struct layout).
private struct CosineSimilarityParams {
    let dimensions: UInt32
    let vectorCount: UInt32
    let queryMagnitude: Float
}

/// Parameters for pairwise similarity (must match Metal struct layout).
private struct PairwiseSimilarityParams {
    let dimensions: UInt32
    let candidateCount: UInt32
    let selectedCount: UInt32
}

/// Parameters for adjacent similarity.
private struct AdjacentSimilarityParams {
    let dimensions: UInt32
    let comparisonCount: UInt32
}
#endif

// MARK: - Shader Source

extension MetalVectorCompute {
    /// Metal shader source code compiled at runtime.
    ///
    /// This approach is used because Swift Package Manager doesn't natively
    /// support Metal shader precompilation. Runtime compilation has negligible
    /// overhead as it only happens once during initialization.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct CosineSimilarityParams {
        uint dimensions;
        uint vectorCount;
        float queryMagnitude;
    };

    struct PairwiseSimilarityParams {
        uint dimensions;
        uint candidateCount;
        uint selectedCount;
    };

    struct AdjacentSimilarityParams {
        uint dimensions;
        uint comparisonCount;
    };

    kernel void batchCosineSimilarity(
        device const float* queryVector [[buffer(0)]],
        device const float* storedVectors [[buffer(1)]],
        device float* similarities [[buffer(2)]],
        constant CosineSimilarityParams& params [[buffer(3)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= params.vectorCount) return;

        device const float* stored = storedVectors + gid * params.dimensions;

        float dotProduct = 0.0f;
        float storedMagSq = 0.0f;

        for (uint i = 0; i < params.dimensions; i++) {
            float q = queryVector[i];
            float s = stored[i];
            dotProduct += q * s;
            storedMagSq += s * s;
        }

        float denom = params.queryMagnitude * sqrt(storedMagSq);
        // Use epsilon to avoid precision issues with very small magnitudes
        const float epsilon = 1e-8f;
        similarities[gid] = (denom > epsilon) ? (dotProduct / denom) : 0.0f;
    }

    kernel void batchDotProduct(
        device const float* queryVector [[buffer(0)]],
        device const float* storedVectors [[buffer(1)]],
        device float* dotProducts [[buffer(2)]],
        constant uint& dimensions [[buffer(3)]],
        constant uint& vectorCount [[buffer(4)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= vectorCount) return;

        device const float* stored = storedVectors + gid * dimensions;

        float result = 0.0f;
        for (uint i = 0; i < dimensions; i++) {
            result += queryVector[i] * stored[i];
        }

        dotProducts[gid] = result;
    }

    kernel void pairwiseSimilarity(
        device const float* candidateVectors [[buffer(0)]],
        device const float* selectedVectors [[buffer(1)]],
        device float* similarities [[buffer(2)]],
        constant PairwiseSimilarityParams& params [[buffer(3)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        uint candidateIdx = gid.x;
        uint selectedIdx = gid.y;

        if (candidateIdx >= params.candidateCount || selectedIdx >= params.selectedCount) return;

        device const float* candidate = candidateVectors + candidateIdx * params.dimensions;
        device const float* selected = selectedVectors + selectedIdx * params.dimensions;

        float dotProduct = 0.0f;
        float candMagSq = 0.0f;
        float selMagSq = 0.0f;

        for (uint i = 0; i < params.dimensions; i++) {
            float c = candidate[i];
            float s = selected[i];
            dotProduct += c * s;
            candMagSq += c * c;
            selMagSq += s * s;
        }

        float denom = sqrt(candMagSq) * sqrt(selMagSq);
        // Use epsilon to avoid precision issues with very small magnitudes
        const float epsilon = 1e-8f;
        float similarity = (denom > epsilon) ? (dotProduct / denom) : 0.0f;

        similarities[candidateIdx * params.selectedCount + selectedIdx] = similarity;
    }

    kernel void rowMax(
        device const float* matrix [[buffer(0)]],
        device float* maxValues [[buffer(1)]],
        constant uint& n [[buffer(2)]],
        constant uint& k [[buffer(3)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= n) return;

        device const float* row = matrix + gid * k;

        float maxVal = -INFINITY;
        for (uint i = 0; i < k; i++) {
            maxVal = max(maxVal, row[i]);
        }

        maxValues[gid] = maxVal;
    }

    kernel void computeMMRScores(
        device const float* relevanceScores [[buffer(0)]],
        device const float* maxSimilarities [[buffer(1)]],
        device float* mmrScores [[buffer(2)]],
        constant float& lambda [[buffer(3)]],
        constant uint& n [[buffer(4)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= n) return;

        float relevance = relevanceScores[gid];
        float maxSim = maxSimilarities[gid];

        mmrScores[gid] = lambda * relevance - (1.0f - lambda) * maxSim;
    }

    kernel void batchMagnitude(
        device const float* vectors [[buffer(0)]],
        device float* magnitudes [[buffer(1)]],
        constant uint& dimensions [[buffer(2)]],
        constant uint& vectorCount [[buffer(3)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= vectorCount) return;

        device const float* vec = vectors + gid * dimensions;

        float sumSq = 0.0f;
        for (uint i = 0; i < dimensions; i++) {
            float v = vec[i];
            sumSq += v * v;
        }

        magnitudes[gid] = sqrt(sumSq);
    }

    kernel void adjacentCosineSimilarity(
        device const float* vectors [[buffer(0)]],
        device float* similarities [[buffer(1)]],
        constant AdjacentSimilarityParams& params [[buffer(2)]],
        uint gid [[thread_position_in_grid]]
    ) {
        if (gid >= params.comparisonCount) return;

        // Compare vector[gid] with vector[gid + 1]
        device const float* vecA = vectors + gid * params.dimensions;
        device const float* vecB = vectors + (gid + 1) * params.dimensions;

        float dotProduct = 0.0f;
        float magASq = 0.0f;
        float magBSq = 0.0f;

        for (uint i = 0; i < params.dimensions; i++) {
            float a = vecA[i];
            float b = vecB[i];
            dotProduct += a * b;
            magASq += a * a;
            magBSq += b * b;
        }

        float denom = sqrt(magASq) * sqrt(magBSq);
        const float epsilon = 1e-8f;
        similarities[gid] = (denom > epsilon) ? (dotProduct / denom) : 0.0f;
    }
    """
}
