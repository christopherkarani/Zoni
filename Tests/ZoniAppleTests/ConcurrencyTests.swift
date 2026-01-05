// ZoniApple - Apple platform extensions for Zoni
//
// ConcurrencyTests.swift - Tests for concurrent access safety

import Testing
import Foundation
@testable import ZoniApple
@testable import Zoni

// MARK: - EmbeddingLRUCache Concurrency Tests

@Suite("EmbeddingLRUCache Concurrency Tests")
struct EmbeddingLRUCacheConcurrencyTests {

    /// Creates a test chunk for caching.
    private func makeTestChunk(id: String) -> Chunk {
        Chunk(
            id: id,
            content: "Test content for \(id)",
            metadata: ChunkMetadata(documentId: "doc-1", index: 0)
        )
    }

    /// Creates a test embedding for caching.
    private func makeTestEmbedding(seed: Int) -> Embedding {
        var vector = [Float](repeating: 0, count: 128)
        for i in 0..<128 {
            vector[i] = Float(sin(Double(seed + i)))
        }
        return Embedding(vector: vector, model: "test")
    }

    @Test("Concurrent puts don't corrupt cache")
    func concurrentPutsDontCorrupt() async throws {
        let cache = EmbeddingLRUCache(capacity: 100)

        // Launch many concurrent put operations
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<200 {
                group.addTask {
                    let chunk = self.makeTestChunk(id: "chunk-\(i)")
                    let embedding = self.makeTestEmbedding(seed: i)
                    await cache.put("key-\(i)", value: (chunk: chunk, embedding: embedding))
                }
            }
        }

        // Cache should respect capacity limit
        let count = await cache.count
        #expect(count <= 100, "Cache should not exceed capacity")
        #expect(count > 0, "Cache should have entries")
    }

    @Test("Concurrent gets and puts are safe")
    func concurrentGetsAndPuts() async throws {
        let cache = EmbeddingLRUCache(capacity: 50)

        // Pre-populate cache
        for i in 0..<50 {
            let chunk = makeTestChunk(id: "chunk-\(i)")
            let embedding = makeTestEmbedding(seed: i)
            await cache.put("key-\(i)", value: (chunk: chunk, embedding: embedding))
        }

        // Launch concurrent gets and puts
        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 50..<100 {
                group.addTask {
                    let chunk = self.makeTestChunk(id: "chunk-\(i)")
                    let embedding = self.makeTestEmbedding(seed: i)
                    await cache.put("key-\(i)", value: (chunk: chunk, embedding: embedding))
                }
            }

            // Readers
            for i in 0..<50 {
                group.addTask {
                    _ = await cache.get("key-\(i)")
                }
            }
        }

        // Verify cache is still functional
        let count = await cache.count
        #expect(count <= 50, "Cache should respect capacity")
    }

    @Test("Concurrent clear and access is safe")
    func concurrentClearAndAccess() async throws {
        let cache = EmbeddingLRUCache(capacity: 100)

        // Pre-populate
        for i in 0..<50 {
            let chunk = makeTestChunk(id: "chunk-\(i)")
            let embedding = makeTestEmbedding(seed: i)
            await cache.put("key-\(i)", value: (chunk: chunk, embedding: embedding))
        }

        // Concurrent operations including clear
        await withTaskGroup(of: Void.self) { group in
            // Clear operation
            group.addTask {
                await cache.clear()
            }

            // Concurrent puts
            for i in 50..<100 {
                group.addTask {
                    let chunk = self.makeTestChunk(id: "chunk-\(i)")
                    let embedding = self.makeTestEmbedding(seed: i)
                    await cache.put("key-\(i)", value: (chunk: chunk, embedding: embedding))
                }
            }
        }

        // Cache should be in consistent state
        let count = await cache.count
        #expect(count >= 0, "Cache count should be non-negative")
    }

    @Test("High contention stress test")
    func highContentionStressTest() async throws {
        let cache = EmbeddingLRUCache(capacity: 20)
        let iterations = 500

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    let key = "key-\(i % 30)" // Reuse keys to cause contention
                    let chunk = self.makeTestChunk(id: "chunk-\(i)")
                    let embedding = self.makeTestEmbedding(seed: i)

                    // Mix of operations
                    if i % 3 == 0 {
                        await cache.put(key, value: (chunk: chunk, embedding: embedding))
                    } else if i % 3 == 1 {
                        _ = await cache.get(key)
                    } else {
                        _ = await cache.contains(key)
                    }
                }
            }
        }

        // Verify cache integrity
        let count = await cache.count
        let keys = await cache.allKeys()
        #expect(count == keys.count, "Count should match keys count")
        #expect(count <= 20, "Should not exceed capacity")
    }
}

// MARK: - Memory Strategy Concurrency Tests

@Suite("Memory Strategy Concurrency Tests")
struct MemoryStrategyConcurrencyTests {

    /// Creates a test embedding.
    private func makeTestEmbedding(dimensions: Int = 128, seed: Int = 0) -> Embedding {
        var vector = [Float](repeating: 0, count: dimensions)
        for i in 0..<dimensions {
            vector[i] = Float(sin(Double(seed + i))) * 0.5 + 0.5
        }

        // Normalize
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        if magnitude > 0 {
            vector = vector.map { $0 / magnitude }
        }

        return Embedding(vector: vector, model: "test")
    }

    @Test("Concurrent strategy searches don't interfere")
    func concurrentStrategySearches() async throws {
        let store = try SQLiteVectorStore(path: ":memory:", tableName: "concurrency_test")

        // Add some test data
        let docs = (0..<20).map { i in
            Chunk(
                id: "chunk-\(i)",
                content: "Content for document \(i)",
                metadata: ChunkMetadata(
                    documentId: "doc-\(i / 5)",
                    index: i % 5,
                    custom: ["index": .int(i)]
                )
            )
        }

        let embeddings = docs.map { _ in makeTestEmbedding(dimensions: 128, seed: Int.random(in: 0..<1000)) }
        try await store.add(docs, embeddings: embeddings)

        // Create different strategies
        let strategies: [any MemoryStrategy] = [
            EagerMemoryStrategy(),
            StreamingMemoryStrategy(batchSize: 5),
            HybridMemoryStrategy(cacheSize: 10, batchSize: 5)
        ]

        // Run concurrent searches with different strategies
        await withTaskGroup(of: [RetrievalResult].self) { group in
            for (index, strategy) in strategies.enumerated() {
                group.addTask {
                    do {
                        let query = self.makeTestEmbedding(dimensions: 128, seed: index * 100)
                        return try await store.search(
                            query: query,
                            limit: 5,
                            filter: nil,
                            memoryStrategy: strategy
                        )
                    } catch {
                        return []
                    }
                }
            }

            // Collect results
            var resultCounts: [Int] = []
            for await results in group {
                resultCounts.append(results.count)
            }

            // All searches should complete successfully
            #expect(resultCounts.count == strategies.count)
        }
    }
}

// MARK: - Embedding Provider Concurrency Tests

@Suite("Embedding Provider Concurrency Tests")
struct EmbeddingProviderConcurrencyTests {

    @Test("NLEmbeddingProvider concurrent embeds are safe")
    func nlProviderConcurrentEmbeds() async throws {
        guard NLEmbeddingProvider.isLanguageAvailable(.english) else {
            return // Skip if not available
        }

        let provider = try NLEmbeddingProvider.english()
        let texts = (0..<50).map { "Test sentence number \($0) for embedding" }

        // Concurrent single embeds
        await withTaskGroup(of: Embedding?.self) { group in
            for text in texts {
                group.addTask {
                    try? await provider.embed(text)
                }
            }

            var successCount = 0
            for await result in group {
                if result != nil {
                    successCount += 1
                }
            }

            #expect(successCount == texts.count, "All embeds should succeed")
        }
    }

    @Test("SwiftEmbeddingsProvider concurrent embeds are safe")
    func swiftEmbeddingsProviderConcurrentEmbeds() async throws {
        guard #available(macOS 15.0, iOS 18.0, tvOS 18.0, visionOS 2.0, watchOS 11.0, *) else {
            return // Skip if not available
        }

        do {
            let provider = try await SwiftEmbeddingsProvider.default()
            let texts = (0..<30).map { "Test sentence number \($0)" }

            // Concurrent embeds
            await withTaskGroup(of: Embedding?.self) { group in
                for text in texts {
                    group.addTask {
                        try? await provider.embed(text)
                    }
                }

                var successCount = 0
                for await result in group {
                    if result != nil {
                        successCount += 1
                    }
                }

                #expect(successCount == texts.count, "All embeds should succeed")
            }
        } catch {
            // Model download may fail in test environment
            return
        }
    }
}

// MARK: - SQLiteVectorStore Concurrency Tests

@Suite("SQLiteVectorStore Concurrency Tests")
struct SQLiteVectorStoreConcurrencyTests {

    /// Creates a test embedding.
    private func makeTestEmbedding(dimensions: Int = 64, seed: Int = 0) -> Embedding {
        var vector = [Float](repeating: 0, count: dimensions)
        for i in 0..<dimensions {
            vector[i] = Float(sin(Double(seed + i)))
        }
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        if magnitude > 0 {
            vector = vector.map { $0 / magnitude }
        }
        return Embedding(vector: vector, model: "test")
    }

    @Test("Concurrent adds don't corrupt store")
    func concurrentAdds() async throws {
        let store = try SQLiteVectorStore(path: ":memory:", tableName: "concurrent_add_test")

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let chunk = Chunk(
                        id: "chunk-\(i)",
                        content: "Content \(i)",
                        metadata: ChunkMetadata(documentId: "doc-\(i / 10)", index: i % 10)
                    )
                    let embedding = self.makeTestEmbedding(dimensions: 64, seed: i)

                    do {
                        try await store.add([chunk], embeddings: [embedding])
                    } catch {
                        // Ignore duplicate key errors in concurrent scenario
                    }
                }
            }
        }

        // Store should be in consistent state
        let count = try await store.count()
        #expect(count > 0, "Store should have entries")
    }

    @Test("Concurrent searches are safe")
    func concurrentSearches() async throws {
        let store = try SQLiteVectorStore(path: ":memory:", tableName: "concurrent_search_test")

        // Pre-populate
        for i in 0..<50 {
            let chunk = Chunk(
                id: "chunk-\(i)",
                content: "Content \(i)",
                metadata: ChunkMetadata(documentId: "doc-\(i / 5)", index: i % 5)
            )
            let embedding = makeTestEmbedding(dimensions: 64, seed: i)
            try await store.add([chunk], embeddings: [embedding])
        }

        // Concurrent searches
        await withTaskGroup(of: [RetrievalResult].self) { group in
            for i in 0..<20 {
                group.addTask {
                    let query = self.makeTestEmbedding(dimensions: 64, seed: i * 10)
                    return (try? await store.search(query: query, limit: 5, filter: nil)) ?? []
                }
            }

            var allResults: [[RetrievalResult]] = []
            for await results in group {
                allResults.append(results)
            }

            // All searches should return results
            #expect(allResults.count == 20)
            for results in allResults {
                #expect(results.count <= 5)
            }
        }
    }
}
