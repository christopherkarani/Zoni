// ZoniAgents - SwiftAgents Integration for Zoni RAG Framework
//
// EmbeddingProviderBridgeTests.swift - Tests for ZoniEmbeddingAdapter

import Testing
import Foundation
@testable import Zoni
@testable import ZoniAgents

// MARK: - ZoniEmbeddingAdapter Tests

@Suite("ZoniEmbeddingAdapter Tests")
struct ZoniEmbeddingAdapterTests {

    // MARK: - Property Mapping Tests

    @Test("Adapter preserves dimensions from wrapped provider")
    func preservesDimensions() async throws {
        let mock = MockEmbedding(dimensions: 768)
        let adapter = ZoniEmbeddingAdapter(mock)

        #expect(adapter.dimensions == 768)
    }

    @Test("Adapter uses provider name as modelIdentifier")
    func modelIdentifierFromName() async {
        let mock = MockEmbedding()
        let adapter = ZoniEmbeddingAdapter(mock)

        #expect(adapter.modelIdentifier == "mock")
    }

    @Test("Adapter with different provider dimensions")
    func differentDimensions() async {
        let small = MockEmbedding(dimensions: 384)
        let large = MockEmbedding(dimensions: 3072)

        let smallAdapter = ZoniEmbeddingAdapter(small)
        let largeAdapter = ZoniEmbeddingAdapter(large)

        #expect(smallAdapter.dimensions == 384)
        #expect(largeAdapter.dimensions == 3072)
    }

    // MARK: - Single Embedding Tests

    @Test("Adapter converts single embedding to vector")
    func convertsSingleEmbedding() async throws {
        let mock = MockEmbedding(dimensions: 3)
        let adapter = ZoniEmbeddingAdapter(mock)

        let vector = try await adapter.embed("test text")

        #expect(vector.count == 3)
        #expect(vector.allSatisfy { $0.isFinite })
    }

    @Test("Adapter produces deterministic results for same input")
    func deterministicResults() async throws {
        let mock = MockEmbedding(dimensions: 128)
        let adapter = ZoniEmbeddingAdapter(mock)

        let vector1 = try await adapter.embed("hello world")
        let vector2 = try await adapter.embed("hello world")

        #expect(vector1 == vector2)
    }

    @Test("Adapter produces different results for different inputs")
    func differentInputsDifferentResults() async throws {
        let mock = MockEmbedding(dimensions: 128)
        let adapter = ZoniEmbeddingAdapter(mock)

        let vector1 = try await adapter.embed("hello")
        let vector2 = try await adapter.embed("goodbye")

        #expect(vector1 != vector2)
    }

    // MARK: - Batch Embedding Tests

    @Test("Adapter batch embeds multiple texts")
    func batchEmbedsMultipleTexts() async throws {
        let mock = MockEmbedding(dimensions: 64)
        let adapter = ZoniEmbeddingAdapter(mock)

        let texts = ["first", "second", "third"]
        let vectors = try await adapter.embed(texts)

        #expect(vectors.count == 3)
        #expect(vectors.allSatisfy { $0.count == 64 })
    }

    @Test("Adapter batch preserves order")
    func batchPreservesOrder() async throws {
        let mock = MockEmbedding(dimensions: 32)
        let adapter = ZoniEmbeddingAdapter(mock)

        let texts = ["alpha", "beta", "gamma"]
        let batchVectors = try await adapter.embed(texts)

        // Get individual vectors
        let alphaVector = try await adapter.embed("alpha")
        let betaVector = try await adapter.embed("beta")
        let gammaVector = try await adapter.embed("gamma")

        #expect(batchVectors[0] == alphaVector)
        #expect(batchVectors[1] == betaVector)
        #expect(batchVectors[2] == gammaVector)
    }

    @Test("Adapter handles empty batch")
    func handlesEmptyBatch() async throws {
        let mock = MockEmbedding(dimensions: 64)
        let adapter = ZoniEmbeddingAdapter(mock)

        let vectors = try await adapter.embed([String]())

        #expect(vectors.isEmpty)
    }

    @Test("Adapter handles single item batch")
    func handlesSingleItemBatch() async throws {
        let mock = MockEmbedding(dimensions: 64)
        let adapter = ZoniEmbeddingAdapter(mock)

        let vectors = try await adapter.embed(["only one"])

        #expect(vectors.count == 1)
        #expect(vectors[0].count == 64)
    }

    // MARK: - Protocol Conformance Tests

    @Test("Adapter conforms to AgentsEmbeddingProvider")
    func conformsToProtocol() async throws {
        let mock = MockEmbedding()
        let adapter = ZoniEmbeddingAdapter(mock)

        // Verify protocol conformance by using as protocol type
        let provider: any AgentsEmbeddingProvider = adapter

        #expect(provider.dimensions == mock.dimensions)
        #expect(provider.modelIdentifier == mock.name)
    }

    @Test("Adapter is Sendable")
    func isSendable() async {
        let mock = MockEmbedding()
        let adapter = ZoniEmbeddingAdapter(mock)

        // Test sendability by passing across actor boundary
        await Task {
            let _ = adapter.dimensions
        }.value
    }
}

// MARK: - AgentsEmbeddingProvider Default Implementation Tests

@Suite("AgentsEmbeddingProvider Default Implementation Tests")
struct AgentsEmbeddingProviderDefaultTests {

    @Test("Default batch implementation calls single embed for each text")
    func defaultBatchCallsSingleEmbed() async throws {
        let counter = EmbedCallCounter(dimensions: 16)

        let texts = ["one", "two", "three", "four", "five"]
        _ = try await counter.embed(texts)

        #expect(await counter.callCount == 5)
    }
}

// MARK: - Test Helpers

/// A mock that counts embed calls to verify default implementation behavior.
actor EmbedCallCounter: AgentsEmbeddingProvider {
    let dimensions: Int
    let modelIdentifier = "counter"
    private(set) var callCount = 0

    init(dimensions: Int) {
        self.dimensions = dimensions
    }

    func embed(_ text: String) async throws -> [Float] {
        callCount += 1
        return Array(repeating: 0.0, count: dimensions)
    }

    // Uses default batch implementation from protocol extension
}
