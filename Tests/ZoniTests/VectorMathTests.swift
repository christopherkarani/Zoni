// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// VectorMathTests.swift - Tests for SIMD vector math operations on Embedding type

import Testing
@testable import Zoni

// MARK: - VectorMath Tests

@Suite("VectorMath Tests")
struct VectorMathTests {

    // MARK: - Cosine Similarity Tests

    @Test("Cosine similarity of identical vectors returns 1.0")
    func testCosineSimilarityIdenticalVectors() {
        let embedding1 = Embedding(vector: [1.0, 2.0, 3.0])
        let embedding2 = Embedding(vector: [1.0, 2.0, 3.0])

        let result = embedding1.cosineSimilarity(to: embedding2)

        #expect(abs(result - 1.0) < 0.0001)
    }

    @Test("Cosine similarity of orthogonal vectors returns 0.0")
    func testCosineSimilarityOrthogonalVectors() {
        // [1, 0] and [0, 1] are orthogonal (perpendicular)
        let embedding1 = Embedding(vector: [1.0, 0.0])
        let embedding2 = Embedding(vector: [0.0, 1.0])

        let result = embedding1.cosineSimilarity(to: embedding2)

        #expect(abs(result - 0.0) < 0.0001)
    }

    @Test("Cosine similarity of opposite vectors returns -1.0")
    func testCosineSimilarityOppositeVectors() {
        let embedding1 = Embedding(vector: [1.0, 2.0, 3.0])
        let embedding2 = Embedding(vector: [-1.0, -2.0, -3.0])

        let result = embedding1.cosineSimilarity(to: embedding2)

        #expect(abs(result - (-1.0)) < 0.0001)
    }

    @Test("Cosine similarity with dimension mismatch returns 0.0")
    func testCosineSimilarityDimensionMismatch() {
        let embedding1 = Embedding(vector: [1.0, 2.0, 3.0])
        let embedding2 = Embedding(vector: [1.0, 2.0])

        let result = embedding1.cosineSimilarity(to: embedding2)

        #expect(abs(result - 0.0) < 0.0001)
    }

    @Test("Cosine similarity of empty vectors returns 0.0")
    func testCosineSimilarityEmptyVectors() {
        let embedding1 = Embedding(vector: [])
        let embedding2 = Embedding(vector: [])

        let result = embedding1.cosineSimilarity(to: embedding2)

        #expect(abs(result - 0.0) < 0.0001)
    }

    @Test("Cosine similarity with zero magnitude vector returns 0.0")
    func testCosineSimilarityZeroMagnitude() {
        let embedding1 = Embedding(vector: [0.0, 0.0, 0.0])
        let embedding2 = Embedding(vector: [1.0, 2.0, 3.0])

        let result = embedding1.cosineSimilarity(to: embedding2)

        #expect(abs(result - 0.0) < 0.0001)
    }

    // MARK: - Dot Product Tests

    @Test("Dot product basic calculation: [1,2,3] . [4,5,6] = 32")
    func testDotProductBasic() {
        // 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32
        let embedding1 = Embedding(vector: [1.0, 2.0, 3.0])
        let embedding2 = Embedding(vector: [4.0, 5.0, 6.0])

        let result = embedding1.dotProduct(with: embedding2)

        #expect(abs(result - 32.0) < 0.0001)
    }

    @Test("Dot product of orthogonal vectors returns 0")
    func testDotProductOrthogonal() {
        let embedding1 = Embedding(vector: [1.0, 0.0, 0.0])
        let embedding2 = Embedding(vector: [0.0, 1.0, 0.0])

        let result = embedding1.dotProduct(with: embedding2)

        #expect(abs(result - 0.0) < 0.0001)
    }

    @Test("Dot product with dimension mismatch returns 0.0")
    func testDotProductDimensionMismatch() {
        let embedding1 = Embedding(vector: [1.0, 2.0, 3.0])
        let embedding2 = Embedding(vector: [4.0, 5.0])

        let result = embedding1.dotProduct(with: embedding2)

        #expect(abs(result - 0.0) < 0.0001)
    }

    // MARK: - Euclidean Distance Tests

    @Test("Euclidean distance of identical vectors returns 0.0")
    func testEuclideanDistanceIdentical() {
        let embedding1 = Embedding(vector: [1.0, 2.0, 3.0])
        let embedding2 = Embedding(vector: [1.0, 2.0, 3.0])

        let result = embedding1.euclideanDistance(to: embedding2)

        #expect(abs(result - 0.0) < 0.0001)
    }

    @Test("Euclidean distance basic: [0,0] to [3,4] = 5.0")
    func testEuclideanDistanceBasic() {
        // sqrt((3-0)^2 + (4-0)^2) = sqrt(9 + 16) = sqrt(25) = 5
        let embedding1 = Embedding(vector: [0.0, 0.0])
        let embedding2 = Embedding(vector: [3.0, 4.0])

        let result = embedding1.euclideanDistance(to: embedding2)

        #expect(abs(result - 5.0) < 0.0001)
    }

    @Test("Euclidean distance with dimension mismatch returns 0.0")
    func testEuclideanDistanceDimensionMismatch() {
        let embedding1 = Embedding(vector: [1.0, 2.0, 3.0])
        let embedding2 = Embedding(vector: [1.0, 2.0])

        let result = embedding1.euclideanDistance(to: embedding2)

        #expect(result == 0.0)
    }

    // MARK: - Magnitude Tests

    @Test("Magnitude of unit vector [1,0,0] returns 1.0")
    func testMagnitudeUnitVector() {
        let embedding = Embedding(vector: [1.0, 0.0, 0.0])

        let result = embedding.magnitude()

        #expect(abs(result - 1.0) < 0.0001)
    }

    @Test("Magnitude of [3,4] returns 5.0")
    func testMagnitudeBasic() {
        // sqrt(3^2 + 4^2) = sqrt(9 + 16) = sqrt(25) = 5
        let embedding = Embedding(vector: [3.0, 4.0])

        let result = embedding.magnitude()

        #expect(abs(result - 5.0) < 0.0001)
    }

    @Test("Magnitude of empty vector returns 0.0")
    func testMagnitudeEmpty() {
        let embedding = Embedding(vector: [])

        let result = embedding.magnitude()

        #expect(abs(result - 0.0) < 0.0001)
    }

    // MARK: - Normalize Tests

    @Test("Normalized vector has magnitude 1.0")
    func testNormalizeBasic() {
        let embedding = Embedding(vector: [3.0, 4.0])

        let normalized = embedding.normalized()
        let magnitude = normalized.magnitude()

        #expect(abs(magnitude - 1.0) < 0.0001)

        // Verify direction is preserved (components scaled proportionally)
        // Original ratio: 3/4 = 0.75
        // Normalized: [0.6, 0.8], ratio: 0.6/0.8 = 0.75
        #expect(abs(normalized.vector[0] - 0.6) < 0.0001)
        #expect(abs(normalized.vector[1] - 0.8) < 0.0001)
    }

    @Test("Normalizing zero vector returns original")
    func testNormalizeZeroVector() {
        let embedding = Embedding(vector: [0.0, 0.0, 0.0])

        let normalized = embedding.normalized()

        // Should return original vector unchanged
        #expect(normalized.vector == embedding.vector)
    }

    // MARK: - Additional Edge Case Tests

    @Test("Cosine similarity with normalized vectors equals dot product")
    func testCosineSimilarityNormalizedEqualsDotProduct() {
        let embedding1 = Embedding(vector: [3.0, 4.0])
        let embedding2 = Embedding(vector: [1.0, 2.0])

        let normalized1 = embedding1.normalized()
        let normalized2 = embedding2.normalized()

        let cosineSim = embedding1.cosineSimilarity(to: embedding2)
        let dotProd = normalized1.dotProduct(with: normalized2)

        #expect(abs(cosineSim - dotProd) < 0.0001)
    }

    @Test("Euclidean distance of empty vectors returns 0.0")
    func testEuclideanDistanceEmptyVectors() {
        let embedding1 = Embedding(vector: [])
        let embedding2 = Embedding(vector: [])

        let result = embedding1.euclideanDistance(to: embedding2)

        #expect(abs(result - 0.0) < 0.0001)
    }

    @Test("Dot product of empty vectors returns 0.0")
    func testDotProductEmptyVectors() {
        let embedding1 = Embedding(vector: [])
        let embedding2 = Embedding(vector: [])

        let result = embedding1.dotProduct(with: embedding2)

        #expect(abs(result - 0.0) < 0.0001)
    }

    @Test("Magnitude of zero vector returns 0.0")
    func testMagnitudeZeroVector() {
        let embedding = Embedding(vector: [0.0, 0.0, 0.0])

        let result = embedding.magnitude()

        #expect(abs(result - 0.0) < 0.0001)
    }

    @Test("Normalized vector preserves model metadata")
    func testNormalizePreservesModel() {
        let embedding = Embedding(vector: [3.0, 4.0], model: "test-model")

        let normalized = embedding.normalized()

        #expect(normalized.model == "test-model")
    }

    @Test("Euclidean distance is symmetric")
    func testEuclideanDistanceSymmetric() {
        let embedding1 = Embedding(vector: [1.0, 2.0, 3.0])
        let embedding2 = Embedding(vector: [4.0, 5.0, 6.0])

        let distance1 = embedding1.euclideanDistance(to: embedding2)
        let distance2 = embedding2.euclideanDistance(to: embedding1)

        #expect(abs(distance1 - distance2) < 0.0001)
    }

    @Test("Cosine similarity is symmetric")
    func testCosineSimilaritySymmetric() {
        let embedding1 = Embedding(vector: [1.0, 2.0, 3.0])
        let embedding2 = Embedding(vector: [4.0, 5.0, 6.0])

        let similarity1 = embedding1.cosineSimilarity(to: embedding2)
        let similarity2 = embedding2.cosineSimilarity(to: embedding1)

        #expect(abs(similarity1 - similarity2) < 0.0001)
    }

    @Test("Dot product is commutative")
    func testDotProductCommutative() {
        let embedding1 = Embedding(vector: [1.0, 2.0, 3.0])
        let embedding2 = Embedding(vector: [4.0, 5.0, 6.0])

        let dotProd1 = embedding1.dotProduct(with: embedding2)
        let dotProd2 = embedding2.dotProduct(with: embedding1)

        #expect(abs(dotProd1 - dotProd2) < 0.0001)
    }

    @Test("High-dimensional vectors work correctly")
    func testHighDimensionalVectors() {
        // Create 1536-dimensional vectors (typical for OpenAI embeddings)
        var vector1 = [Float](repeating: 0.1, count: 1536)
        var vector2 = [Float](repeating: 0.2, count: 1536)

        // Make first few elements distinct
        vector1[0] = 1.0
        vector2[0] = 0.5

        let embedding1 = Embedding(vector: vector1)
        let embedding2 = Embedding(vector: vector2)

        // Should compute without overflow or underflow
        let similarity = embedding1.cosineSimilarity(to: embedding2)
        let distance = embedding1.euclideanDistance(to: embedding2)
        let magnitude1 = embedding1.magnitude()

        #expect(similarity > 0.0 && similarity < 1.0)
        #expect(distance > 0.0)
        #expect(magnitude1 > 0.0)
    }
}
