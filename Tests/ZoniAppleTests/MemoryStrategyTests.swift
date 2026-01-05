// ZoniApple - Apple platform extensions for Zoni
//
// MemoryStrategyTests.swift - Comprehensive tests for Memory Strategy implementations
//
// This test file follows TDD principles and covers:
// - EagerMemoryStrategy tests
// - StreamingMemoryStrategy tests
// - CachedMemoryStrategy tests
// - HybridMemoryStrategy tests
// - MemoryStrategyRecommendation tests
// - Sendable conformance tests
// - Integration tests with SQLiteVectorStore

import Testing
import Foundation
@testable import ZoniApple
@testable import Zoni

// MARK: - Test Helpers

/// Creates a test chunk with the specified parameters.
private func makeChunk(
    id: String,
    content: String,
    documentId: String = "doc-1",
    index: Int = 0
) -> Chunk {
    Chunk(
        id: id,
        content: content,
        metadata: ChunkMetadata(
            documentId: documentId,
            index: index,
            startOffset: 0,
            endOffset: content.count,
            source: nil,
            custom: [:]
        )
    )
}

/// Creates a test embedding with the specified values.
private func makeEmbedding(_ values: [Float]) -> Embedding {
    Embedding(vector: values, model: "test")
}

// MARK: - EagerMemoryStrategy Tests

@Suite("EagerMemoryStrategy Tests")
struct EagerMemoryStrategyTests {

    @Test("name is 'eager'")
    func nameIsEager() {
        let strategy = EagerMemoryStrategy()
        #expect(strategy.name == "eager")
    }

    @Test("init creates strategy")
    func initCreatesStrategy() {
        let strategy = EagerMemoryStrategy()
        #expect(strategy.name == "eager")
    }

    @Test("strategy conforms to MemoryStrategy protocol")
    func conformsToMemoryStrategyProtocol() {
        let strategy = EagerMemoryStrategy()
        let asProtocol: any MemoryStrategy = strategy
        #expect(asProtocol.name == "eager")
    }

    @Test("strategy is a struct with value semantics")
    func isValueType() {
        let strategy1 = EagerMemoryStrategy()
        var strategy2 = strategy1
        // Both should be independent instances (value types)
        #expect(strategy1.name == strategy2.name)
        #expect(strategy2.name == "eager")
    }
}

// MARK: - StreamingMemoryStrategy Tests

@Suite("StreamingMemoryStrategy Tests")
struct StreamingMemoryStrategyTests {

    @Test("name is 'streaming'")
    func nameIsStreaming() {
        let strategy = StreamingMemoryStrategy()
        #expect(strategy.name == "streaming")
    }

    @Test("default batchSize is 1000")
    func defaultBatchSizeIs1000() {
        let strategy = StreamingMemoryStrategy()
        #expect(strategy.batchSize == 1000)
    }

    @Test("custom batchSize is stored")
    func customBatchSizeIsStored() {
        let strategy = StreamingMemoryStrategy(batchSize: 2000)
        #expect(strategy.batchSize == 2000)
    }

    @Test("custom batchSize of 500 is stored")
    func customBatchSize500IsStored() {
        let strategy = StreamingMemoryStrategy(batchSize: 500)
        #expect(strategy.batchSize == 500)
    }

    @Test("custom batchSize of 1 is stored")
    func minimalBatchSizeIsStored() {
        let strategy = StreamingMemoryStrategy(batchSize: 1)
        #expect(strategy.batchSize == 1)
    }

    @Test("strategy conforms to MemoryStrategy protocol")
    func conformsToMemoryStrategyProtocol() {
        let strategy = StreamingMemoryStrategy(batchSize: 100)
        let asProtocol: any MemoryStrategy = strategy
        #expect(asProtocol.name == "streaming")
    }

    @Test("batchSize is immutable after initialization")
    func batchSizeIsImmutable() {
        let strategy = StreamingMemoryStrategy(batchSize: 750)
        // batchSize is let, so we can only verify it doesn't change
        #expect(strategy.batchSize == 750)
    }
}

// MARK: - CachedMemoryStrategy Tests

@Suite("CachedMemoryStrategy Tests")
struct CachedMemoryStrategyTests {

    @Test("name is 'cached'")
    func nameIsCached() {
        let strategy = CachedMemoryStrategy()
        #expect(strategy.name == "cached")
    }

    @Test("default cacheSize is 10_000")
    func defaultCacheSizeIs10000() {
        let strategy = CachedMemoryStrategy()
        #expect(strategy.cacheSize == 10_000)
    }

    @Test("custom cacheSize is stored")
    func customCacheSizeIsStored() {
        let strategy = CachedMemoryStrategy(cacheSize: 5000)
        #expect(strategy.cacheSize == 5000)
    }

    @Test("custom cacheSize of 50000 is stored")
    func largeCacheSizeIsStored() {
        let strategy = CachedMemoryStrategy(cacheSize: 50_000)
        #expect(strategy.cacheSize == 50_000)
    }

    @Test("custom cacheSize of 1 is stored")
    func minimalCacheSizeIsStored() {
        let strategy = CachedMemoryStrategy(cacheSize: 1)
        #expect(strategy.cacheSize == 1)
    }

    @Test("strategy conforms to MemoryStrategy protocol")
    func conformsToMemoryStrategyProtocol() {
        let strategy = CachedMemoryStrategy(cacheSize: 2500)
        let asProtocol: any MemoryStrategy = strategy
        #expect(asProtocol.name == "cached")
    }

    @Test("cacheSize is immutable after initialization")
    func cacheSizeIsImmutable() {
        let strategy = CachedMemoryStrategy(cacheSize: 7500)
        // cacheSize is let, so we can only verify it doesn't change
        #expect(strategy.cacheSize == 7500)
    }
}

// MARK: - HybridMemoryStrategy Tests

@Suite("HybridMemoryStrategy Tests")
struct HybridMemoryStrategyTests {

    @Test("name is 'hybrid'")
    func nameIsHybrid() {
        let strategy = HybridMemoryStrategy()
        #expect(strategy.name == "hybrid")
    }

    @Test("default cacheSize is 10_000")
    func defaultCacheSizeIs10000() {
        let strategy = HybridMemoryStrategy()
        #expect(strategy.cacheSize == 10_000)
    }

    @Test("default batchSize is 1000")
    func defaultBatchSizeIs1000() {
        let strategy = HybridMemoryStrategy()
        #expect(strategy.batchSize == 1000)
    }

    @Test("custom cacheSize is stored")
    func customCacheSizeIsStored() {
        let strategy = HybridMemoryStrategy(cacheSize: 5000)
        #expect(strategy.cacheSize == 5000)
    }

    @Test("custom batchSize is stored")
    func customBatchSizeIsStored() {
        let strategy = HybridMemoryStrategy(batchSize: 500)
        #expect(strategy.batchSize == 500)
    }

    @Test("custom values are stored together")
    func customValuesAreStoredTogether() {
        let strategy = HybridMemoryStrategy(cacheSize: 8000, batchSize: 250)
        #expect(strategy.cacheSize == 8000)
        #expect(strategy.batchSize == 250)
    }

    @Test("strategy conforms to MemoryStrategy protocol")
    func conformsToMemoryStrategyProtocol() {
        let strategy = HybridMemoryStrategy(cacheSize: 3000, batchSize: 200)
        let asProtocol: any MemoryStrategy = strategy
        #expect(asProtocol.name == "hybrid")
    }

    @Test("both properties are immutable after initialization")
    func propertiesAreImmutable() {
        let strategy = HybridMemoryStrategy(cacheSize: 6000, batchSize: 400)
        // Both are let, so we verify they retain their values
        #expect(strategy.cacheSize == 6000)
        #expect(strategy.batchSize == 400)
    }
}

// MARK: - MemoryStrategyRecommendation Tests

@Suite("MemoryStrategyRecommendation Tests")
struct MemoryStrategyRecommendationTests {

    @Test("eagerThreshold is 10_000")
    func eagerThresholdIs10000() {
        #expect(MemoryStrategyRecommendation.eagerThreshold == 10_000)
    }

    @Test("streamingThreshold is 100_000")
    func streamingThresholdIs100000() {
        #expect(MemoryStrategyRecommendation.streamingThreshold == 100_000)
    }

    @Test("recommendedStrategy for 5000 vectors returns EagerMemoryStrategy")
    func recommendedStrategyFor5000ReturnsEager() {
        let strategy = MemoryStrategyRecommendation.recommendedStrategy(forVectorCount: 5000)
        #expect(strategy.name == "eager")
        #expect(strategy is EagerMemoryStrategy)
    }

    @Test("recommendedStrategy for 0 vectors returns EagerMemoryStrategy")
    func recommendedStrategyFor0ReturnsEager() {
        let strategy = MemoryStrategyRecommendation.recommendedStrategy(forVectorCount: 0)
        #expect(strategy.name == "eager")
        #expect(strategy is EagerMemoryStrategy)
    }

    @Test("recommendedStrategy for 9999 vectors returns EagerMemoryStrategy")
    func recommendedStrategyFor9999ReturnsEager() {
        let strategy = MemoryStrategyRecommendation.recommendedStrategy(forVectorCount: 9_999)
        #expect(strategy.name == "eager")
        #expect(strategy is EagerMemoryStrategy)
    }

    @Test("recommendedStrategy for 10_000 vectors returns HybridMemoryStrategy")
    func recommendedStrategyFor10000ReturnsHybrid() {
        let strategy = MemoryStrategyRecommendation.recommendedStrategy(forVectorCount: 10_000)
        #expect(strategy.name == "hybrid")
        #expect(strategy is HybridMemoryStrategy)
    }

    @Test("recommendedStrategy for 50_000 vectors returns HybridMemoryStrategy")
    func recommendedStrategyFor50000ReturnsHybrid() {
        let strategy = MemoryStrategyRecommendation.recommendedStrategy(forVectorCount: 50_000)
        #expect(strategy.name == "hybrid")
        #expect(strategy is HybridMemoryStrategy)
    }

    @Test("recommendedStrategy for 99_999 vectors returns HybridMemoryStrategy")
    func recommendedStrategyFor99999ReturnsHybrid() {
        let strategy = MemoryStrategyRecommendation.recommendedStrategy(forVectorCount: 99_999)
        #expect(strategy.name == "hybrid")
        #expect(strategy is HybridMemoryStrategy)
    }

    @Test("recommendedStrategy for 100_000 vectors returns StreamingMemoryStrategy")
    func recommendedStrategyFor100000ReturnsStreaming() {
        let strategy = MemoryStrategyRecommendation.recommendedStrategy(forVectorCount: 100_000)
        #expect(strategy.name == "streaming")
        #expect(strategy is StreamingMemoryStrategy)
    }

    @Test("recommendedStrategy for 200_000 vectors returns StreamingMemoryStrategy")
    func recommendedStrategyFor200000ReturnsStreaming() {
        let strategy = MemoryStrategyRecommendation.recommendedStrategy(forVectorCount: 200_000)
        #expect(strategy.name == "streaming")
        #expect(strategy is StreamingMemoryStrategy)
    }

    @Test("recommendedStrategy for 1_000_000 vectors returns StreamingMemoryStrategy")
    func recommendedStrategyFor1MillionReturnsStreaming() {
        let strategy = MemoryStrategyRecommendation.recommendedStrategy(forVectorCount: 1_000_000)
        #expect(strategy.name == "streaming")
        #expect(strategy is StreamingMemoryStrategy)
    }

    @Test("estimatedMemoryUsage calculation is correct for 10000 vectors with 1536 dimensions")
    func estimatedMemoryUsageFor10000x1536() {
        let usage = MemoryStrategyRecommendation.estimatedMemoryUsage(
            vectorCount: 10_000,
            dimensions: 1536
        )
        // 10,000 * 1536 * 4 bytes = 61,440,000 bytes
        let expected = 10_000 * 1536 * MemoryLayout<Float>.size
        #expect(usage == expected)
        #expect(usage == 61_440_000)
    }

    @Test("estimatedMemoryUsage calculation is correct for 1000 vectors with 768 dimensions")
    func estimatedMemoryUsageFor1000x768() {
        let usage = MemoryStrategyRecommendation.estimatedMemoryUsage(
            vectorCount: 1000,
            dimensions: 768
        )
        // 1,000 * 768 * 4 bytes = 3,072,000 bytes
        let expected = 1000 * 768 * MemoryLayout<Float>.size
        #expect(usage == expected)
        #expect(usage == 3_072_000)
    }

    @Test("estimatedMemoryUsage for 0 vectors is 0")
    func estimatedMemoryUsageForZeroVectors() {
        let usage = MemoryStrategyRecommendation.estimatedMemoryUsage(
            vectorCount: 0,
            dimensions: 1536
        )
        #expect(usage == 0)
    }

    @Test("estimatedMemoryUsage for 0 dimensions is 0")
    func estimatedMemoryUsageForZeroDimensions() {
        let usage = MemoryStrategyRecommendation.estimatedMemoryUsage(
            vectorCount: 10_000,
            dimensions: 0
        )
        #expect(usage == 0)
    }

    @Test("estimatedMemoryUsage uses Float size of 4 bytes")
    func estimatedMemoryUsageUsesFloatSize() {
        // Verify that Float is 4 bytes on this platform
        #expect(MemoryLayout<Float>.size == 4)

        let usage = MemoryStrategyRecommendation.estimatedMemoryUsage(
            vectorCount: 1,
            dimensions: 1
        )
        #expect(usage == 4)
    }
}

// MARK: - Sendable Conformance Tests

@Suite("Sendable Conformance Tests")
struct SendableConformanceTests {

    @Test("EagerMemoryStrategy conforms to Sendable")
    func eagerIsSendable() {
        let strategy = EagerMemoryStrategy()
        // Compile-time check: passing to a concurrent context
        let _: any Sendable = strategy
        #expect(strategy.name == "eager")
    }

    @Test("StreamingMemoryStrategy conforms to Sendable")
    func streamingIsSendable() {
        let strategy = StreamingMemoryStrategy(batchSize: 500)
        // Compile-time check: passing to a concurrent context
        let _: any Sendable = strategy
        #expect(strategy.name == "streaming")
    }

    @Test("CachedMemoryStrategy conforms to Sendable")
    func cachedIsSendable() {
        let strategy = CachedMemoryStrategy(cacheSize: 5000)
        // Compile-time check: passing to a concurrent context
        let _: any Sendable = strategy
        #expect(strategy.name == "cached")
    }

    @Test("HybridMemoryStrategy conforms to Sendable")
    func hybridIsSendable() {
        let strategy = HybridMemoryStrategy(cacheSize: 5000, batchSize: 500)
        // Compile-time check: passing to a concurrent context
        let _: any Sendable = strategy
        #expect(strategy.name == "hybrid")
    }

    @Test("MemoryStrategy protocol extends Sendable")
    func memoryStrategyProtocolExtendsSendable() {
        // Any MemoryStrategy should be Sendable
        let strategies: [any MemoryStrategy] = [
            EagerMemoryStrategy(),
            StreamingMemoryStrategy(),
            CachedMemoryStrategy(),
            HybridMemoryStrategy()
        ]

        for strategy in strategies {
            // Compile-time check: MemoryStrategy extends Sendable
            let _: any Sendable = strategy
            #expect(!strategy.name.isEmpty)
        }
    }

    @Test("Strategies can be passed across actor boundaries")
    func strategiesCanCrossActorBoundaries() async {
        actor TestActor {
            func useStrategy(_ strategy: any MemoryStrategy) -> String {
                return strategy.name
            }
        }

        let testActor = TestActor()

        let eagerName = await testActor.useStrategy(EagerMemoryStrategy())
        #expect(eagerName == "eager")

        let streamingName = await testActor.useStrategy(StreamingMemoryStrategy())
        #expect(streamingName == "streaming")

        let cachedName = await testActor.useStrategy(CachedMemoryStrategy())
        #expect(cachedName == "cached")

        let hybridName = await testActor.useStrategy(HybridMemoryStrategy())
        #expect(hybridName == "hybrid")
    }

    @Test("Strategies can be used in Task groups")
    func strategiesCanBeUsedInTaskGroups() async {
        let strategies: [any MemoryStrategy] = [
            EagerMemoryStrategy(),
            StreamingMemoryStrategy(batchSize: 100),
            CachedMemoryStrategy(cacheSize: 1000),
            HybridMemoryStrategy(cacheSize: 1000, batchSize: 100)
        ]

        let names = await withTaskGroup(of: String.self) { group in
            for strategy in strategies {
                group.addTask {
                    return strategy.name
                }
            }

            var results: [String] = []
            for await name in group {
                results.append(name)
            }
            return results.sorted()
        }

        #expect(names.contains("eager"))
        #expect(names.contains("streaming"))
        #expect(names.contains("cached"))
        #expect(names.contains("hybrid"))
    }
}

// MARK: - Integration Tests with SQLiteVectorStore

@Suite("SQLiteVectorStore Memory Strategy Integration Tests")
struct SQLiteVectorStoreIntegrationTests {

    /// Creates an in-memory SQLite vector store for testing.
    private func createTestStore() async throws -> SQLiteVectorStore {
        try SQLiteVectorStore(path: ":memory:")
    }

    /// Populates the store with test data.
    private func populateStore(_ store: SQLiteVectorStore, count: Int) async throws {
        let chunks = (0..<count).map { i in
            makeChunk(id: "chunk-\(i)", content: "Test content \(i)", documentId: "doc-\(i / 10)")
        }

        // Create embeddings with 3 dimensions for testing
        let embeddings = (0..<count).map { i in
            let x = Float(i) / Float(count)
            let y = Float(count - i) / Float(count)
            let z = Float.random(in: 0...0.1)
            return makeEmbedding([x, y, z])
        }

        try await store.add(chunks, embeddings: embeddings)
    }

    @Test("search with EagerMemoryStrategy returns results")
    func searchWithEagerMemoryStrategy() async throws {
        let store = try await createTestStore()
        try await populateStore(store, count: 10)

        let strategy = EagerMemoryStrategy()
        let query = makeEmbedding([0.5, 0.5, 0.05])

        let results = try await store.search(
            query: query,
            limit: 5,
            filter: nil,
            memoryStrategy: strategy
        )

        #expect(results.count <= 5)
        #expect(results.count > 0)

        // Verify results are sorted by score (descending)
        for i in 1..<results.count {
            #expect(results[i - 1].score >= results[i].score)
        }
    }

    @Test("search with StreamingMemoryStrategy returns results")
    func searchWithStreamingMemoryStrategy() async throws {
        let store = try await createTestStore()
        try await populateStore(store, count: 20)

        let strategy = StreamingMemoryStrategy(batchSize: 5)
        let query = makeEmbedding([0.3, 0.7, 0.05])

        let results = try await store.search(
            query: query,
            limit: 5,
            filter: nil,
            memoryStrategy: strategy
        )

        #expect(results.count <= 5)
        #expect(results.count > 0)

        // Verify results are sorted by score (descending)
        for i in 1..<results.count {
            #expect(results[i - 1].score >= results[i].score)
        }
    }

    @Test("search with CachedMemoryStrategy returns results")
    func searchWithCachedMemoryStrategy() async throws {
        let store = try await createTestStore()
        try await populateStore(store, count: 15)

        let strategy = CachedMemoryStrategy(cacheSize: 100)
        let query = makeEmbedding([0.7, 0.3, 0.05])

        let results = try await store.search(
            query: query,
            limit: 5,
            filter: nil,
            memoryStrategy: strategy
        )

        #expect(results.count <= 5)
        #expect(results.count > 0)
    }

    @Test("search with HybridMemoryStrategy returns results")
    func searchWithHybridMemoryStrategy() async throws {
        let store = try await createTestStore()
        try await populateStore(store, count: 25)

        let strategy = HybridMemoryStrategy(cacheSize: 50, batchSize: 10)
        let query = makeEmbedding([0.6, 0.4, 0.05])

        let results = try await store.search(
            query: query,
            limit: 5,
            filter: nil,
            memoryStrategy: strategy
        )

        #expect(results.count <= 5)
        #expect(results.count > 0)

        // Verify results are sorted by score (descending)
        for i in 1..<results.count {
            #expect(results[i - 1].score >= results[i].score)
        }
    }

    @Test("recommendedStrategy property returns a strategy")
    func recommendedStrategyPropertyReturnsStrategy() async throws {
        let store = try await createTestStore()
        try await populateStore(store, count: 5)

        let strategy = await store.recommendedStrategy
        #expect(!strategy.name.isEmpty)

        // With only 5 vectors, should recommend eager
        #expect(strategy.name == "eager")
    }

    @Test("recommendedStrategy returns hybrid for medium datasets")
    func recommendedStrategyReturnsHybridForMedium() async throws {
        // We can't easily add 10k vectors in a test, so we'll test the recommendation logic directly
        let strategy = MemoryStrategyRecommendation.recommendedStrategy(forVectorCount: 15_000)
        #expect(strategy.name == "hybrid")
    }

    @Test("different strategies produce consistent results")
    func differentStrategiesProduceConsistentResults() async throws {
        let store = try await createTestStore()
        try await populateStore(store, count: 30)

        let query = makeEmbedding([0.5, 0.5, 0.05])
        let limit = 5

        // Get results with different strategies
        let eagerResults = try await store.search(
            query: query,
            limit: limit,
            filter: nil,
            memoryStrategy: EagerMemoryStrategy()
        )

        let streamingResults = try await store.search(
            query: query,
            limit: limit,
            filter: nil,
            memoryStrategy: StreamingMemoryStrategy(batchSize: 5)
        )

        let hybridResults = try await store.search(
            query: query,
            limit: limit,
            filter: nil,
            memoryStrategy: HybridMemoryStrategy(cacheSize: 20, batchSize: 5)
        )

        // All strategies should return the same number of results
        #expect(eagerResults.count == streamingResults.count)
        #expect(streamingResults.count == hybridResults.count)

        // The top result should be the same across strategies
        if !eagerResults.isEmpty && !streamingResults.isEmpty && !hybridResults.isEmpty {
            // Check that scores are approximately equal (floating point comparison)
            let eagerTopScore = eagerResults[0].score
            let streamingTopScore = streamingResults[0].score
            let hybridTopScore = hybridResults[0].score

            #expect(abs(eagerTopScore - streamingTopScore) < 0.001)
            #expect(abs(streamingTopScore - hybridTopScore) < 0.001)
        }
    }

    @Test("search with filter works across strategies")
    func searchWithFilterWorksAcrossStrategies() async throws {
        let store = try await createTestStore()
        try await populateStore(store, count: 30)

        let query = makeEmbedding([0.5, 0.5, 0.05])
        let filter = MetadataFilter.equals("documentId", "doc-1")

        let strategies: [any MemoryStrategy] = [
            EagerMemoryStrategy(),
            StreamingMemoryStrategy(batchSize: 10),
            HybridMemoryStrategy(cacheSize: 20, batchSize: 10)
        ]

        for strategy in strategies {
            let results = try await store.search(
                query: query,
                limit: 5,
                filter: filter,
                memoryStrategy: strategy
            )

            // All results should match the filter
            for result in results {
                #expect(result.chunk.metadata.documentId == "doc-1")
            }
        }
    }

    @Test("empty store returns empty results with any strategy")
    func emptyStoreReturnsEmptyResults() async throws {
        let store = try await createTestStore()
        let query = makeEmbedding([0.5, 0.5, 0.05])

        let strategies: [any MemoryStrategy] = [
            EagerMemoryStrategy(),
            StreamingMemoryStrategy(batchSize: 10),
            CachedMemoryStrategy(cacheSize: 100),
            HybridMemoryStrategy(cacheSize: 50, batchSize: 10)
        ]

        for strategy in strategies {
            let results = try await store.search(
                query: query,
                limit: 5,
                filter: nil,
                memoryStrategy: strategy
            )

            #expect(results.isEmpty, "Strategy '\(strategy.name)' should return empty results for empty store")
        }
    }

    @Test("searchWithAutoStrategy uses recommended strategy")
    func searchWithAutoStrategyUsesRecommendedStrategy() async throws {
        let store = try await createTestStore()
        try await populateStore(store, count: 10)

        let query = makeEmbedding([0.5, 0.5, 0.05])

        let results = try await store.searchWithAutoStrategy(
            query: query,
            limit: 5,
            filter: nil
        )

        #expect(results.count <= 5)
        #expect(results.count > 0)
    }

    @Test("estimatedMemoryUsage property returns value")
    func estimatedMemoryUsagePropertyReturnsValue() async throws {
        let store = try await createTestStore()
        try await populateStore(store, count: 10)

        let usage = await store.estimatedMemoryUsage
        // Should be vectorCount * dimensions * sizeof(Float)
        // With default dimensions of 1536 and 10 vectors: 10 * 1536 * 4 = 61,440
        #expect(usage > 0)
    }
}

// MARK: - Strategy Property Tests

@Suite("Strategy Property Tests")
struct StrategyPropertyTests {

    @Test("All strategies have non-empty names")
    func allStrategiesHaveNonEmptyNames() {
        let strategies: [any MemoryStrategy] = [
            EagerMemoryStrategy(),
            StreamingMemoryStrategy(),
            CachedMemoryStrategy(),
            HybridMemoryStrategy()
        ]

        for strategy in strategies {
            #expect(!strategy.name.isEmpty)
        }
    }

    @Test("Strategy names are unique")
    func strategyNamesAreUnique() {
        let strategies: [any MemoryStrategy] = [
            EagerMemoryStrategy(),
            StreamingMemoryStrategy(),
            CachedMemoryStrategy(),
            HybridMemoryStrategy()
        ]

        let names = strategies.map { $0.name }
        let uniqueNames = Set(names)

        #expect(names.count == uniqueNames.count)
    }

    @Test("Strategy names are lowercase")
    func strategyNamesAreLowercase() {
        let strategies: [any MemoryStrategy] = [
            EagerMemoryStrategy(),
            StreamingMemoryStrategy(),
            CachedMemoryStrategy(),
            HybridMemoryStrategy()
        ]

        for strategy in strategies {
            #expect(strategy.name == strategy.name.lowercased())
        }
    }
}

// MARK: - Edge Case Tests

@Suite("Memory Strategy Edge Cases")
struct MemoryStrategyEdgeCaseTests {

    @Test("Streaming with batch size of 1 works")
    func streamingWithBatchSizeOf1Works() async throws {
        let store = try SQLiteVectorStore(path: ":memory:")

        let chunks = [
            makeChunk(id: "1", content: "Hello"),
            makeChunk(id: "2", content: "World"),
        ]
        let embeddings = [
            makeEmbedding([1.0, 0.0, 0.0]),
            makeEmbedding([0.0, 1.0, 0.0]),
        ]

        try await store.add(chunks, embeddings: embeddings)

        let strategy = StreamingMemoryStrategy(batchSize: 1)
        let query = makeEmbedding([0.5, 0.5, 0.0])

        let results = try await store.search(
            query: query,
            limit: 2,
            filter: nil,
            memoryStrategy: strategy
        )

        #expect(results.count == 2)
    }

    @Test("Cached with cache size of 1 works")
    func cachedWithCacheSizeOf1Works() async throws {
        let store = try SQLiteVectorStore(path: ":memory:")

        let chunks = [
            makeChunk(id: "1", content: "Hello"),
            makeChunk(id: "2", content: "World"),
        ]
        let embeddings = [
            makeEmbedding([1.0, 0.0, 0.0]),
            makeEmbedding([0.0, 1.0, 0.0]),
        ]

        try await store.add(chunks, embeddings: embeddings)

        let strategy = CachedMemoryStrategy(cacheSize: 1)
        let query = makeEmbedding([0.5, 0.5, 0.0])

        let results = try await store.search(
            query: query,
            limit: 2,
            filter: nil,
            memoryStrategy: strategy
        )

        #expect(results.count == 2)
    }

    @Test("Hybrid with minimal values works")
    func hybridWithMinimalValuesWorks() async throws {
        let store = try SQLiteVectorStore(path: ":memory:")

        let chunks = [
            makeChunk(id: "1", content: "Hello"),
            makeChunk(id: "2", content: "World"),
            makeChunk(id: "3", content: "Test"),
        ]
        let embeddings = [
            makeEmbedding([1.0, 0.0, 0.0]),
            makeEmbedding([0.0, 1.0, 0.0]),
            makeEmbedding([0.0, 0.0, 1.0]),
        ]

        try await store.add(chunks, embeddings: embeddings)

        let strategy = HybridMemoryStrategy(cacheSize: 1, batchSize: 1)
        let query = makeEmbedding([0.5, 0.5, 0.0])

        let results = try await store.search(
            query: query,
            limit: 3,
            filter: nil,
            memoryStrategy: strategy
        )

        #expect(results.count == 3)
    }

    @Test("Large batch size works with small dataset")
    func largeBatchSizeWithSmallDataset() async throws {
        let store = try SQLiteVectorStore(path: ":memory:")

        let chunks = [
            makeChunk(id: "1", content: "Hello"),
        ]
        let embeddings = [
            makeEmbedding([1.0, 0.0, 0.0]),
        ]

        try await store.add(chunks, embeddings: embeddings)

        // Batch size larger than dataset
        let strategy = StreamingMemoryStrategy(batchSize: 10_000)
        let query = makeEmbedding([1.0, 0.0, 0.0])

        let results = try await store.search(
            query: query,
            limit: 10,
            filter: nil,
            memoryStrategy: strategy
        )

        #expect(results.count == 1)
    }

    @Test("Limit larger than dataset works")
    func limitLargerThanDatasetWorks() async throws {
        let store = try SQLiteVectorStore(path: ":memory:")

        let chunks = [
            makeChunk(id: "1", content: "Hello"),
            makeChunk(id: "2", content: "World"),
        ]
        let embeddings = [
            makeEmbedding([1.0, 0.0, 0.0]),
            makeEmbedding([0.0, 1.0, 0.0]),
        ]

        try await store.add(chunks, embeddings: embeddings)

        let strategies: [any MemoryStrategy] = [
            EagerMemoryStrategy(),
            StreamingMemoryStrategy(batchSize: 10),
            CachedMemoryStrategy(cacheSize: 10),
            HybridMemoryStrategy(cacheSize: 10, batchSize: 10)
        ]

        let query = makeEmbedding([0.5, 0.5, 0.0])

        for strategy in strategies {
            let results = try await store.search(
                query: query,
                limit: 100,  // Much larger than dataset
                filter: nil,
                memoryStrategy: strategy
            )

            #expect(results.count == 2, "Strategy '\(strategy.name)' should return all 2 results")
        }
    }
}
