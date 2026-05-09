import Foundation

/// A protocol for performing similarity calculations on vectors.
///
/// This allows for different implementations of vector math, such as
/// CPU-based (Accelerate/SIMD) or GPU-based (Metal).
public protocol SimilarityCalculator: Sendable {
    /// Computes cosine similarity between adjacent pairs of vectors (v[i] vs v[i+1]).
    ///
    /// - Parameters:
    ///   - vectors: A flat array containing all vectors sequentially.
    ///   - dimensions: The dimensionality of each vector.
    /// - Returns: An array of `N-1` similarity scores, where `N` is the number of vectors.
    func adjacentCosineSimilarity(vectors: [Float], dimensions: Int) async throws -> [Float]
}
