// ZoniAgents - SwiftAgents Integration for Zoni RAG Framework
//
// ErrorAndConcurrencyTests.swift - Tests for error handling and concurrent access

import Testing
import Foundation
@testable import Zoni
@testable import ZoniAgents

// MARK: - Error Path Tests

@Suite("ZoniVectorStoreAdapter Error Tests")
struct VectorStoreErrorTests {

    // MARK: - Validation Error Tests

    @Test("Adapter throws on empty ID")
    func throwsOnEmptyId() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        await #expect(throws: ZoniError.self) {
            try await adapter.add(
                id: "",
                content: "Test",
                embedding: [1, 0, 0],
                metadata: [:]
            )
        }
    }

    @Test("Adapter throws on ID with invalid characters")
    func throwsOnInvalidIdChars() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        await #expect(throws: ZoniError.self) {
            try await adapter.add(
                id: "test\0id",
                content: "Test",
                embedding: [1, 0, 0],
                metadata: [:]
            )
        }
    }

    @Test("Adapter throws on ID exceeding max length")
    func throwsOnLongId() async throws {
        let store = InMemoryVectorStore()
        let config = VectorStoreAdapterConfig(maxEntries: 100, maxIdLength: 10)
        let adapter = ZoniVectorStoreAdapter(vectorStore: store, config: config)

        let longId = String(repeating: "x", count: 11)
        await #expect(throws: ZoniError.self) {
            try await adapter.add(
                id: longId,
                content: "Test",
                embedding: [1, 0, 0],
                metadata: [:]
            )
        }
    }

    @Test("Adapter throws on empty embedding")
    func throwsOnEmptyEmbedding() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        await #expect(throws: ZoniError.self) {
            try await adapter.add(
                id: "test",
                content: "Test",
                embedding: [],
                metadata: [:]
            )
        }
    }

    @Test("Adapter throws on NaN in embedding")
    func throwsOnNaNEmbedding() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        await #expect(throws: ZoniError.self) {
            try await adapter.add(
                id: "test",
                content: "Test",
                embedding: [Float.nan, 0, 0],
                metadata: [:]
            )
        }
    }

    @Test("Adapter throws on infinity in embedding")
    func throwsOnInfinityEmbedding() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        await #expect(throws: ZoniError.self) {
            try await adapter.add(
                id: "test",
                content: "Test",
                embedding: [Float.infinity, 0, 0],
                metadata: [:]
            )
        }
    }

    @Test("Adapter throws on search with zero limit")
    func throwsOnZeroLimit() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        await #expect(throws: ZoniError.self) {
            try await adapter.search(queryEmbedding: [1, 0, 0], limit: 0)
        }
    }

    @Test("Adapter throws on search with negative limit")
    func throwsOnNegativeLimit() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        await #expect(throws: ZoniError.self) {
            try await adapter.search(queryEmbedding: [1, 0, 0], limit: -5)
        }
    }

    @Test("Adapter throws on search with empty embedding")
    func throwsOnEmptySearchEmbedding() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        await #expect(throws: ZoniError.self) {
            try await adapter.search(queryEmbedding: [], limit: 10)
        }
    }

    @Test("Adapter throws when max entries exceeded")
    func throwsWhenMaxEntriesExceeded() async throws {
        let store = InMemoryVectorStore()
        let config = VectorStoreAdapterConfig(maxEntries: 2, maxIdLength: 256)
        let adapter = ZoniVectorStoreAdapter(vectorStore: store, config: config)

        // Add up to limit
        try await adapter.add(id: "1", content: "One", embedding: [1, 0, 0], metadata: [:])
        try await adapter.add(id: "2", content: "Two", embedding: [0, 1, 0], metadata: [:])

        // Third should fail
        await #expect(throws: ZoniError.self) {
            try await adapter.add(id: "3", content: "Three", embedding: [0, 0, 1], metadata: [:])
        }
    }
}

@Suite("ZoniRetrieverAdapter Error Tests")
struct RetrieverErrorTests {

    @Test("Adapter throws on zero limit")
    func throwsOnZeroLimit() async throws {
        let mockRetriever = ErrorTestMockRetriever(results: [])
        let adapter = ZoniRetrieverAdapter(mockRetriever)

        await #expect(throws: ZoniError.self) {
            try await adapter.retrieve(query: "test", limit: 0)
        }
    }

    @Test("Adapter throws on negative limit")
    func throwsOnNegativeLimit() async throws {
        let mockRetriever = ErrorTestMockRetriever(results: [])
        let adapter = ZoniRetrieverAdapter(mockRetriever)

        await #expect(throws: ZoniError.self) {
            try await adapter.retrieve(query: "test", limit: -1)
        }
    }

    @Test("Adapter throws on NaN minScore")
    func throwsOnNaNMinScore() async throws {
        let mockRetriever = ErrorTestMockRetriever(results: [])
        let adapter = ZoniRetrieverAdapter(mockRetriever)

        await #expect(throws: ZoniError.self) {
            try await adapter.retrieve(query: "test", limit: 5, minScore: Float.nan)
        }
    }

    @Test("Adapter throws on infinity minScore")
    func throwsOnInfinityMinScore() async throws {
        let mockRetriever = ErrorTestMockRetriever(results: [])
        let adapter = ZoniRetrieverAdapter(mockRetriever)

        await #expect(throws: ZoniError.self) {
            try await adapter.retrieve(query: "test", limit: 5, minScore: Float.infinity)
        }
    }
}

// MARK: - Concurrency Tests

@Suite("Concurrency Tests")
struct ConcurrencyTests {

    @Test("Concurrent adds to vector store adapter")
    func concurrentAdds() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        // Launch 50 concurrent add operations
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    try await adapter.add(
                        id: "entry-\(i)",
                        content: "Content \(i)",
                        embedding: [Float(i) / 50.0, 0.5, 0.5],
                        metadata: ["index": "\(i)"]
                    )
                }
            }
            try await group.waitForAll()
        }

        let count = try await adapter.count()
        #expect(count == 50)
    }

    @Test("Concurrent searches on vector store adapter")
    func concurrentSearches() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        // Add some entries first
        for i in 0..<10 {
            try await adapter.add(
                id: "entry-\(i)",
                content: "Content \(i)",
                embedding: [Float(i) / 10.0, 0.5, 0.5],
                metadata: [:]
            )
        }

        // Launch 20 concurrent search operations
        let results = try await withThrowingTaskGroup(of: [MemorySearchResult].self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await adapter.search(queryEmbedding: [0.5, 0.5, 0.5], limit: 5)
                }
            }

            var allResults: [[MemorySearchResult]] = []
            for try await result in group {
                allResults.append(result)
            }
            return allResults
        }

        // All searches should succeed and return results
        #expect(results.count == 20)
        #expect(results.allSatisfy { !$0.isEmpty })
    }

    @Test("Concurrent adds and searches")
    func concurrentAddsAndSearches() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        // Seed with some initial data
        for i in 0..<5 {
            try await adapter.add(
                id: "seed-\(i)",
                content: "Seed \(i)",
                embedding: [Float(i) / 5.0, 0.5, 0.5],
                metadata: [:]
            )
        }

        // Launch mixed concurrent operations
        try await withThrowingTaskGroup(of: Void.self) { group in
            // 25 adds
            for i in 0..<25 {
                group.addTask {
                    try await adapter.add(
                        id: "concurrent-\(i)",
                        content: "Concurrent \(i)",
                        embedding: [Float(i) / 25.0, 0.3, 0.3],
                        metadata: [:]
                    )
                }
            }

            // 25 searches
            for _ in 0..<25 {
                group.addTask {
                    _ = try await adapter.search(queryEmbedding: [0.5, 0.5, 0.5], limit: 5)
                }
            }

            try await group.waitForAll()
        }

        // Should have all entries
        let count = try await adapter.count()
        #expect(count == 30) // 5 seed + 25 concurrent
    }

    @Test("Embedding adapter handles concurrent embeds")
    func concurrentEmbeds() async throws {
        let mockProvider = ConcurrencyTestMockEmbedding(dimensions: 128)
        let adapter = ZoniEmbeddingAdapter(mockProvider)

        // Launch 50 concurrent embed operations
        let results = try await withThrowingTaskGroup(of: [Float].self) { group in
            for i in 0..<50 {
                group.addTask {
                    try await adapter.embed("Text \(i)")
                }
            }

            var vectors: [[Float]] = []
            for try await vector in group {
                vectors.append(vector)
            }
            return vectors
        }

        #expect(results.count == 50)
        #expect(results.allSatisfy { $0.count == 128 })
    }

    @Test("Namespace isolation under concurrent access")
    func namespaceIsolationConcurrent() async throws {
        let store = InMemoryVectorStore()
        let adapter1 = ZoniVectorStoreAdapter(vectorStore: store, namespace: "agent1")
        let adapter2 = ZoniVectorStoreAdapter(vectorStore: store, namespace: "agent2")

        // Concurrent adds to both namespaces
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<25 {
                group.addTask {
                    try await adapter1.add(
                        id: "entry-\(i)",
                        content: "Agent1 \(i)",
                        embedding: [Float(i) / 25.0, 0, 0],
                        metadata: [:]
                    )
                }
                group.addTask {
                    try await adapter2.add(
                        id: "entry-\(i)",
                        content: "Agent2 \(i)",
                        embedding: [0, Float(i) / 25.0, 0],
                        metadata: [:]
                    )
                }
            }
            try await group.waitForAll()
        }

        // Each should see only its own entries
        let count1 = try await adapter1.count()
        let count2 = try await adapter2.count()

        #expect(count1 == 25)
        #expect(count2 == 25)

        // Searches should be isolated
        let results1 = try await adapter1.search(queryEmbedding: [1, 0, 0], limit: 100)
        let results2 = try await adapter2.search(queryEmbedding: [0, 1, 0], limit: 100)

        #expect(results1.allSatisfy { $0.content.hasPrefix("Agent1") })
        #expect(results2.allSatisfy { $0.content.hasPrefix("Agent2") })
    }
}

// MARK: - Edge Case Tests

@Suite("Edge Case Tests")
struct EdgeCaseTests {

    @Test("Adapter handles empty content")
    func handlesEmptyContent() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        try await adapter.add(
            id: "empty",
            content: "",
            embedding: [1, 0, 0],
            metadata: [:]
        )

        let results = try await adapter.search(queryEmbedding: [1, 0, 0], limit: 1)
        #expect(results.count == 1)
        #expect(results[0].content == "")
    }

    @Test("Adapter handles very long content")
    func handlesLongContent() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        let longContent = String(repeating: "a", count: 100_000)
        try await adapter.add(
            id: "long",
            content: longContent,
            embedding: [1, 0, 0],
            metadata: [:]
        )

        let results = try await adapter.search(queryEmbedding: [1, 0, 0], limit: 1)
        #expect(results.count == 1)
        #expect(results[0].content.count == 100_000)
    }

    @Test("Adapter handles special characters in metadata")
    func handlesSpecialMetadata() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        try await adapter.add(
            id: "special",
            content: "Test",
            embedding: [1, 0, 0],
            metadata: [
                "unicode": "Hello 世界 🌍",
                "quotes": "\"quoted\"",
                "empty": ""
            ]
        )

        let results = try await adapter.search(queryEmbedding: [1, 0, 0], limit: 1)
        #expect(results[0].metadata["unicode"] == "Hello 世界 🌍")
        #expect(results[0].metadata["quotes"] == "\"quoted\"")
        #expect(results[0].metadata["empty"] == "")
    }

    @Test("Adapter handles high-dimensional embeddings")
    func handlesHighDimensional() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        let embedding = (0..<3072).map { Float($0) / 3072.0 }
        try await adapter.add(
            id: "high-dim",
            content: "Test",
            embedding: embedding,
            metadata: [:]
        )

        let results = try await adapter.search(queryEmbedding: embedding, limit: 1)
        #expect(results.count == 1)
    }

    @Test("Adapter delete with non-existent IDs is safe")
    func deleteNonExistent() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        try await adapter.add(id: "exists", content: "Test", embedding: [1, 0, 0], metadata: [:])

        // Should not throw
        try await adapter.delete(ids: ["does-not-exist", "also-missing"])

        // Original should still exist
        let count = try await adapter.count()
        #expect(count == 1)
    }

    @Test("Adapter clear on empty store is safe")
    func clearEmpty() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        // Should not throw
        try await adapter.clear()

        let count = try await adapter.count()
        #expect(count == 0)
    }
}

// MARK: - Test Helpers

/// Mock retriever for error tests.
actor ErrorTestMockRetriever: Retriever {
    nonisolated let name = "error-test-mock"

    private let results: [RetrievalResult]

    init(results: [RetrievalResult]) {
        self.results = results
    }

    func retrieve(
        query: String,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        Array(results.prefix(limit))
    }
}

/// Mock embedding provider for concurrency tests.
actor ConcurrencyTestMockEmbedding: EmbeddingProvider {
    nonisolated let name = "concurrency-test-mock"
    nonisolated let dimensions: Int
    nonisolated let maxTokensPerRequest: Int = 8192
    nonisolated let optimalBatchSize: Int = 100

    init(dimensions: Int) {
        self.dimensions = dimensions
    }

    func embed(_ text: String) async throws -> Embedding {
        // Small delay to simulate network latency
        try await Task.sleep(for: .milliseconds(1))
        let vector = (0..<dimensions).map { Float($0) / Float(dimensions) }
        return Embedding(vector: vector, model: name)
    }

    func embed(_ texts: [String]) async throws -> [Embedding] {
        var results: [Embedding] = []
        for text in texts {
            let result = try await embed(text)
            results.append(result)
        }
        return results
    }
}

extension Sequence {
    func asyncMap<T>(_ transform: @escaping (Element) async throws -> T) async rethrows -> [T] {
        var results: [T] = []
        for element in self {
            try await results.append(transform(element))
        }
        return results
    }
}
