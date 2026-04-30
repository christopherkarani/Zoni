#if canImport(Metal)
import Metal
import Zoni

/// A Metal-accelerated implementation of vector similarity calculations.
///
/// This calculator uses the `MetalVectorCompute` engine to perform
/// batch vector operations on the GPU.
public struct MetalSimilarityCalculator: SimilarityCalculator {
    
    // MARK: - Properties
    
    private let compute: MetalVectorCompute
    
    // MARK: - Initialization
    
    /// Creates a new Metal-backed similarity calculator.
    ///
    /// - Throws: `MetalComputeError` if Metal initialization fails.
    public init() throws {
        self.compute = try MetalVectorCompute()
    }
    
    // MARK: - SimilarityCalculator Protocol
    
    public func adjacentCosineSimilarity(vectors: [Float], dimensions: Int) async throws -> [Float] {
        return try await compute.adjacentCosineSimilarity(vectors: vectors, dimensions: dimensions)
    }
}
#endif
