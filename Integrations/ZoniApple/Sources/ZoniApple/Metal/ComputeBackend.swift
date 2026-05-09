// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// ComputeBackend.swift - Adaptive compute backend selection
//
// This module provides intelligent selection between CPU (vDSP SIMD) and
// GPU (Metal) compute backends based on workload characteristics.

import Foundation
import Zoni

// MARK: - ComputeBackend

/// Compute backend options for vector operations.
///
/// The framework supports both CPU-based SIMD operations (via Accelerate/vDSP)
/// and GPU-based parallel computation (via Metal). The optimal choice depends
/// on the workload size and characteristics.
public enum ComputeBackend: String, Sendable, Codable {
    /// CPU-based computation using Apple's Accelerate framework (vDSP).
    ///
    /// Best for:
    /// - Small datasets (< 5,000 vectors)
    /// - Filtered searches (filter evaluation on CPU anyway)
    /// - Platforms without Metal support
    case cpu

    /// GPU-based computation using Metal compute shaders.
    ///
    /// Best for:
    /// - Large datasets (> 10,000 vectors)
    /// - Unfiltered full-scan searches
    /// - Apple Silicon devices with powerful GPUs
    case gpu

    /// Automatic selection based on workload characteristics.
    ///
    /// The framework will analyze the workload and choose the optimal backend.
    /// This is the recommended default for most use cases.
    case auto
}

// MARK: - GPUAcceleratedVectorStore

/// Protocol for vector stores that support GPU-accelerated search.
///
/// Vector stores can conform to this protocol to provide optional GPU
/// acceleration for similarity search operations. The framework will
/// automatically fall back to CPU-based search when GPU is unavailable
/// or not beneficial for the workload.
public protocol GPUAcceleratedVectorStore: VectorStore {

    /// Whether this store currently supports GPU acceleration.
    ///
    /// This may change at runtime if GPU resources become unavailable.
    var supportsGPUSearch: Bool { get async }

    /// The number of vectors currently stored.
    ///
    /// Used for adaptive backend selection.
    var vectorCount: Int { get async }

    /// Performs similarity search using the specified compute backend.
    ///
    /// - Parameters:
    ///   - query: The query embedding to search for.
    ///   - limit: Maximum number of results to return.
    ///   - filter: Optional metadata filter.
    ///   - backend: Compute backend to use (cpu, gpu, or auto).
    /// - Returns: Ranked retrieval results.
    func search(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?,
        backend: ComputeBackend
    ) async throws -> [RetrievalResult]
}

// MARK: - Default Implementation

extension GPUAcceleratedVectorStore {

    /// Default implementation using auto backend selection.
    public func search(
        query: Embedding,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        try await search(query: query, limit: limit, filter: filter, backend: .auto)
    }
}

// MARK: - BackendSelector

/// Intelligent compute backend selector.
///
/// Analyzes workload characteristics and system state to determine
/// the optimal compute backend for vector operations.
public struct BackendSelector: Sendable {

    /// Threshold below which CPU is preferred (GPU overhead dominates).
    public static let cpuPreferredThreshold = 5_000

    /// Threshold above which GPU is preferred.
    public static let gpuPreferredThreshold = 10_000

    /// Memory threshold for GPU (bytes). If workload exceeds this, batch or use CPU.
    public static let gpuMemoryThreshold = 500 * 1024 * 1024  // 500 MB

    /// Selects the optimal backend for the given workload.
    ///
    /// - Parameters:
    ///   - requestedBackend: The backend requested by the user.
    ///   - vectorCount: Number of vectors in the store.
    ///   - dimensions: Vector dimensions.
    ///   - hasFilter: Whether a metadata filter is applied.
    ///   - isGPUAvailable: Whether GPU is currently available.
    /// - Returns: The selected compute backend.
    public static func select(
        requestedBackend: ComputeBackend,
        vectorCount: Int,
        dimensions: Int,
        hasFilter: Bool,
        isGPUAvailable: Bool
    ) -> ComputeBackend {
        // Explicit CPU request or GPU unavailable
        guard requestedBackend != .cpu else { return .cpu }
        guard isGPUAvailable else { return .cpu }

        // Explicit GPU request (user knows best)
        guard requestedBackend != .gpu else { return .gpu }

        // Auto selection logic
        return autoSelect(
            vectorCount: vectorCount,
            dimensions: dimensions,
            hasFilter: hasFilter
        )
    }

    /// Automatic backend selection based on workload analysis.
    private static func autoSelect(
        vectorCount: Int,
        dimensions: Int,
        hasFilter: Bool
    ) -> ComputeBackend {
        // Validate inputs - invalid values default to CPU
        guard vectorCount > 0, dimensions > 0 else {
            return .cpu
        }

        // Filters require CPU evaluation, reducing GPU benefit
        if hasFilter {
            // Only use GPU if filtered set is still large
            return vectorCount >= gpuPreferredThreshold * 2 ? .gpu : .cpu
        }

        // Small datasets: CPU wins due to GPU dispatch overhead
        if vectorCount < cpuPreferredThreshold {
            return .cpu
        }

        // Medium datasets: breakeven zone, slight CPU preference
        if vectorCount < gpuPreferredThreshold {
            // Use GPU only for high-dimensional vectors (more compute-bound)
            return dimensions >= 1024 ? .gpu : .cpu
        }

        // Large datasets: GPU wins
        // Check memory requirements using Int64 to prevent overflow
        let requiredMemory = Int64(vectorCount) * Int64(dimensions) * Int64(MemoryLayout<Float>.size)
        if requiredMemory > Int64(gpuMemoryThreshold) {
            // Very large: may need batching or streaming
            // Still prefer GPU but caller should handle batching
            return .gpu
        }

        return .gpu
    }
}

// MARK: - ComputeBackendMetrics

/// Metrics for compute backend performance monitoring.
public struct ComputeBackendMetrics: Sendable {
    /// Total CPU search operations performed.
    public var cpuSearchCount: Int = 0

    /// Total GPU search operations performed.
    public var gpuSearchCount: Int = 0

    /// Total CPU search time in seconds.
    public var cpuSearchTime: Double = 0.0

    /// Total GPU search time in seconds.
    public var gpuSearchTime: Double = 0.0

    /// Average CPU search time per operation.
    public var averageCPUSearchTime: Double {
        cpuSearchCount > 0 ? cpuSearchTime / Double(cpuSearchCount) : 0
    }

    /// Average GPU search time per operation.
    public var averageGPUSearchTime: Double {
        gpuSearchCount > 0 ? gpuSearchTime / Double(gpuSearchCount) : 0
    }

    /// Records a CPU search operation.
    public mutating func recordCPUSearch(duration: Double) {
        cpuSearchCount += 1
        cpuSearchTime += duration
    }

    /// Records a GPU search operation.
    public mutating func recordGPUSearch(duration: Double) {
        gpuSearchCount += 1
        gpuSearchTime += duration
    }
}
