// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// SIMD-optimized vector math operations using Apple's Accelerate framework.

import Accelerate

// MARK: - VectorMath

/// SIMD-optimized vector math operations for high-performance similarity computations.
///
/// `VectorMath` provides hardware-accelerated vector operations using Apple's Accelerate
/// framework. These operations are essential for efficient similarity search in vector stores.
///
/// All methods are stateless and thread-safe, making them suitable for concurrent use
/// across multiple threads or actors.
///
/// Example usage:
/// ```swift
/// let vectorA: [Float] = [0.1, 0.2, 0.3, 0.4]
/// let vectorB: [Float] = [0.15, 0.25, 0.35, 0.45]
///
/// // Compute similarity metrics
/// let similarity = VectorMath.cosineSimilarity(vectorA, vectorB)
/// let distance = VectorMath.euclideanDistance(vectorA, vectorB)
/// let dot = VectorMath.dotProduct(vectorA, vectorB)
///
/// // Normalize a vector to unit length
/// let unitVector = VectorMath.normalize(vectorA)
/// ```
///
/// ## Performance
/// These operations use `vDSP` functions from Accelerate for SIMD optimization,
/// providing significant speedups for high-dimensional vectors (e.g., 1536 dimensions
/// for OpenAI embeddings or 768 dimensions for sentence transformers).
///
/// ## Thread Safety
/// All methods are pure functions with no shared mutable state, making them
/// inherently thread-safe and suitable for use in concurrent contexts.
public enum VectorMath {

    // MARK: - Private Helpers

    /// Checks if all values in the vector are finite (not NaN or Infinity).
    ///
    /// - Parameter vector: The vector to validate.
    /// - Returns: `true` if all elements are finite, `false` if any element is NaN or Infinity.
    private static func allFinite(_ vector: [Float]) -> Bool {
        vector.allSatisfy { $0.isFinite }
    }

    // MARK: - Similarity Metrics

    /// Computes the cosine similarity between two vectors using SIMD operations.
    ///
    /// Cosine similarity measures the angle between two vectors, returning a value
    /// in the range [-1, 1] where:
    /// - 1 means the vectors point in the same direction (identical orientation)
    /// - 0 means the vectors are orthogonal (unrelated)
    /// - -1 means the vectors point in opposite directions
    ///
    /// Formula: `dot(a, b) / (||a|| * ||b||)`
    ///
    /// This implementation uses `vDSP_dotpr` and `vDSP_svesq` for SIMD acceleration.
    ///
    /// - Parameters:
    ///   - a: The first vector.
    ///   - b: The second vector.
    /// - Returns: The cosine similarity value in the range [-1, 1].
    ///   Returns 0.0 if:
    ///   - Vectors have different dimensions
    ///   - Either vector is empty
    ///   - Either vector has zero magnitude
    ///   - Either vector contains NaN or Infinity values
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        // Validate input dimensions
        guard a.count == b.count else {
            return 0.0
        }

        guard !a.isEmpty else {
            return 0.0
        }

        // Validate that all values are finite (not NaN or Infinity)
        guard allFinite(a), allFinite(b) else {
            return 0.0
        }

        let dot = dotProduct(a, b)
        let magnitudeA = magnitude(a)
        let magnitudeB = magnitude(b)

        // Handle zero magnitude to avoid division by zero
        let magnitudeProduct = magnitudeA * magnitudeB
        guard magnitudeProduct > 0 else {
            return 0.0
        }

        return dot / magnitudeProduct
    }

    /// Computes the dot product of two vectors using SIMD operations.
    ///
    /// The dot product (also called scalar product or inner product) is the sum
    /// of the element-wise products of two vectors.
    ///
    /// Formula: `sum(a[i] * b[i]) for i in 0..<n`
    ///
    /// This implementation uses `vDSP_dotpr` for SIMD acceleration.
    ///
    /// - Parameters:
    ///   - a: The first vector.
    ///   - b: The second vector.
    /// - Returns: The dot product of the two vectors.
    ///   Returns 0.0 if vectors have different dimensions, are empty,
    ///   or contain NaN or Infinity values.
    public static func dotProduct(_ a: [Float], _ b: [Float]) -> Float {
        // Validate input dimensions
        guard a.count == b.count else {
            return 0.0
        }

        guard !a.isEmpty else {
            return 0.0
        }

        // Validate that all values are finite (not NaN or Infinity)
        guard allFinite(a), allFinite(b) else {
            return 0.0
        }

        var result: Float = 0.0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }

    /// Computes the Euclidean distance between two vectors using SIMD operations.
    ///
    /// Euclidean distance is the straight-line distance between two points
    /// in the vector space, also known as L2 distance.
    ///
    /// Formula: `sqrt(sum((a[i] - b[i])^2)) for i in 0..<n`
    ///
    /// This implementation computes the difference vector and then uses
    /// `vDSP_svesq` for the sum of squared elements.
    ///
    /// - Parameters:
    ///   - a: The first vector.
    ///   - b: The second vector.
    /// - Returns: The Euclidean distance between the two vectors.
    ///   Returns 0.0 if vectors have different dimensions, are empty,
    ///   or contain NaN or Infinity values.
    public static func euclideanDistance(_ a: [Float], _ b: [Float]) -> Float {
        // Validate input dimensions
        guard a.count == b.count else {
            return 0.0
        }

        guard !a.isEmpty else {
            return 0.0
        }

        // Validate that all values are finite (not NaN or Infinity)
        guard allFinite(a), allFinite(b) else {
            return 0.0
        }

        // Compute difference vector: diff = a - b
        var diff = [Float](repeating: 0.0, count: a.count)
        vDSP_vsub(b, 1, a, 1, &diff, 1, vDSP_Length(a.count))

        // Compute sum of squared differences
        var sumSquares: Float = 0.0
        vDSP_svesq(diff, 1, &sumSquares, vDSP_Length(diff.count))

        return sumSquares.squareRoot()
    }

    // MARK: - Vector Operations

    /// Computes the magnitude (L2 norm) of a vector using SIMD operations.
    ///
    /// The magnitude is the Euclidean length of the vector, calculated as the
    /// square root of the sum of squared elements.
    ///
    /// Formula: `sqrt(sum(v[i]^2)) for i in 0..<n`
    ///
    /// This implementation uses `vDSP_svesq` for SIMD acceleration.
    ///
    /// - Parameter v: The input vector.
    /// - Returns: The magnitude (length) of the vector.
    ///   Returns 0.0 for empty vectors.
    public static func magnitude(_ v: [Float]) -> Float {
        guard !v.isEmpty else {
            return 0.0
        }

        var sumSquares: Float = 0.0
        vDSP_svesq(v, 1, &sumSquares, vDSP_Length(v.count))
        return sumSquares.squareRoot()
    }

    /// Normalizes a vector to unit length using SIMD operations.
    ///
    /// A normalized vector (unit vector) has a magnitude of 1.0 while preserving
    /// its direction. Normalizing vectors is useful for cosine similarity comparisons
    /// and can simplify distance calculations.
    ///
    /// Formula: `v[i] / ||v|| for i in 0..<n`
    ///
    /// This implementation uses `vDSP_vsdiv` for SIMD-accelerated division.
    ///
    /// - Parameter v: The input vector.
    /// - Returns: A new vector with the same direction but magnitude of 1.0.
    ///   Returns an empty array for empty input vectors.
    ///   Returns the original vector if it has zero magnitude (cannot normalize)
    ///   or if it contains NaN or Infinity values.
    public static func normalize(_ v: [Float]) -> [Float] {
        guard !v.isEmpty else {
            return []
        }

        // Validate that all values are finite (not NaN or Infinity)
        guard allFinite(v) else {
            return v
        }

        var mag = magnitude(v)

        // Cannot normalize a zero-magnitude vector
        guard mag > 0 else {
            return v
        }

        var result = [Float](repeating: 0.0, count: v.count)
        vDSP_vsdiv(v, 1, &mag, &result, 1, vDSP_Length(v.count))
        return result
    }
}
