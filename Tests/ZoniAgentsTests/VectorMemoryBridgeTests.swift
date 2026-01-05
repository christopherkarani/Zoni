// ZoniAgents - SwiftAgents Integration for Zoni RAG Framework
//
// VectorMemoryBridgeTests.swift - Tests for ZoniVectorStoreAdapter

import Testing
import Foundation
@testable import Zoni
@testable import ZoniAgents

// MARK: - ZoniVectorStoreAdapter Tests

@Suite("ZoniVectorStoreAdapter Tests")
struct ZoniVectorStoreAdapterTests {

    // MARK: - Basic Operations Tests

    @Test("Adapter adds and retrieves entries")
    func addAndRetrieve() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        try await adapter.add(
            id: "msg1",
            content: "Hello world",
            embedding: [0.1, 0.2, 0.3],
            metadata: ["role": "user"]
        )

        let results = try await adapter.search(
            queryEmbedding: [0.1, 0.2, 0.3],
            limit: 10
        )

        #expect(results.count == 1)
        #expect(results[0].content == "Hello world")
        #expect(results[0].id == "msg1")
    }

    @Test("Adapter returns correct count")
    func countReturnsCorrectValue() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        #expect(try await adapter.count() == 0)

        try await adapter.add(
            id: "1",
            content: "First",
            embedding: [1, 0, 0],
            metadata: [:]
        )
        #expect(try await adapter.count() == 1)

        try await adapter.add(
            id: "2",
            content: "Second",
            embedding: [0, 1, 0],
            metadata: [:]
        )
        #expect(try await adapter.count() == 2)
    }

    @Test("Adapter clears all entries")
    func clearRemovesAllEntries() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        // Add some entries
        try await adapter.add(id: "1", content: "One", embedding: [1, 0, 0], metadata: [:])
        try await adapter.add(id: "2", content: "Two", embedding: [0, 1, 0], metadata: [:])
        try await adapter.add(id: "3", content: "Three", embedding: [0, 0, 1], metadata: [:])

        #expect(try await adapter.count() == 3)

        try await adapter.clear()

        #expect(try await adapter.count() == 0)
    }

    @Test("Adapter deletes entries by ID")
    func deleteRemovesSpecificEntries() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        try await adapter.add(id: "keep", content: "Keep this", embedding: [1, 0, 0], metadata: [:])
        try await adapter.add(id: "delete", content: "Delete this", embedding: [0, 1, 0], metadata: [:])

        #expect(try await adapter.count() == 2)

        try await adapter.delete(ids: ["delete"])

        #expect(try await adapter.count() == 1)

        let results = try await adapter.search(queryEmbedding: [1, 0, 0], limit: 10)
        #expect(results.count == 1)
        #expect(results[0].id == "keep")
    }

    // MARK: - Search Tests

    @Test("Adapter search returns results sorted by score")
    func searchReturnsSortedResults() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        // Add entries with different similarity to query [1, 0, 0]
        try await adapter.add(id: "far", content: "Far", embedding: [0, 0, 1], metadata: [:])
        try await adapter.add(id: "close", content: "Close", embedding: [0.9, 0.1, 0], metadata: [:])
        try await adapter.add(id: "medium", content: "Medium", embedding: [0.5, 0.5, 0], metadata: [:])

        let results = try await adapter.search(queryEmbedding: [1, 0, 0], limit: 3)

        #expect(results.count == 3)
        // Should be sorted by similarity (highest first)
        #expect(results[0].id == "close")
        #expect(results[1].id == "medium")
        #expect(results[2].id == "far")
    }

    @Test("Adapter search respects limit")
    func searchRespectsLimit() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        for i in 0..<10 {
            try await adapter.add(
                id: "entry-\(i)",
                content: "Entry \(i)",
                embedding: [Float(i) / 10, 0, 0],
                metadata: [:]
            )
        }

        let results = try await adapter.search(queryEmbedding: [1, 0, 0], limit: 3)

        #expect(results.count == 3)
    }

    @Test("Adapter search handles empty store")
    func searchHandlesEmptyStore() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        let results = try await adapter.search(queryEmbedding: [1, 0, 0], limit: 10)

        #expect(results.isEmpty)
    }

    // MARK: - Metadata Tests

    @Test("Adapter preserves metadata")
    func preservesMetadata() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        try await adapter.add(
            id: "msg1",
            content: "Test content",
            embedding: [1, 0, 0],
            metadata: [
                "role": "assistant",
                "timestamp": "2024-01-01",
                "source": "conversation"
            ]
        )

        let results = try await adapter.search(queryEmbedding: [1, 0, 0], limit: 1)

        #expect(results.count == 1)
        #expect(results[0].metadata["role"] == "assistant")
        #expect(results[0].metadata["timestamp"] == "2024-01-01")
        #expect(results[0].metadata["source"] == "conversation")
    }

    @Test("Adapter handles empty metadata")
    func handlesEmptyMetadata() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        try await adapter.add(
            id: "msg1",
            content: "No metadata",
            embedding: [1, 0, 0],
            metadata: [:]
        )

        let results = try await adapter.search(queryEmbedding: [1, 0, 0], limit: 1)

        #expect(results.count == 1)
        #expect(results[0].metadata.isEmpty)
    }

    // MARK: - Namespace Isolation Tests

    @Test("Adapter isolates entries by namespace")
    func namespaceIsolation() async throws {
        let store = InMemoryVectorStore()
        let adapter1 = ZoniVectorStoreAdapter(vectorStore: store, namespace: "agent1")
        let adapter2 = ZoniVectorStoreAdapter(vectorStore: store, namespace: "agent2")

        try await adapter1.add(id: "a", content: "Agent 1 data", embedding: [1, 0, 0], metadata: [:])
        try await adapter2.add(id: "b", content: "Agent 2 data", embedding: [0, 1, 0], metadata: [:])

        // Each adapter should only see its own data
        let results1 = try await adapter1.search(queryEmbedding: [1, 0, 0], limit: 10)
        let results2 = try await adapter2.search(queryEmbedding: [0, 1, 0], limit: 10)

        #expect(results1.count == 1)
        #expect(results1[0].content == "Agent 1 data")

        #expect(results2.count == 1)
        #expect(results2[0].content == "Agent 2 data")
    }

    @Test("Adapter clear only affects its namespace")
    func clearOnlyAffectsNamespace() async throws {
        let store = InMemoryVectorStore()
        let adapter1 = ZoniVectorStoreAdapter(vectorStore: store, namespace: "agent1")
        let adapter2 = ZoniVectorStoreAdapter(vectorStore: store, namespace: "agent2")

        try await adapter1.add(id: "a", content: "Keep", embedding: [1, 0, 0], metadata: [:])
        try await adapter2.add(id: "b", content: "Delete", embedding: [0, 1, 0], metadata: [:])

        try await adapter2.clear()

        // Agent1's data should still exist
        let results1 = try await adapter1.search(queryEmbedding: [1, 0, 0], limit: 10)
        #expect(results1.count == 1)

        // Agent2's data should be gone
        let results2 = try await adapter2.search(queryEmbedding: [0, 1, 0], limit: 10)
        #expect(results2.isEmpty)
    }

    @Test("Adapter delete cannot delete other namespace entries")
    func deleteCannotCrossNamespace() async throws {
        let store = InMemoryVectorStore()
        let adapter1 = ZoniVectorStoreAdapter(vectorStore: store, namespace: "agent1")
        let adapter2 = ZoniVectorStoreAdapter(vectorStore: store, namespace: "agent2")

        try await adapter1.add(id: "protected", content: "Agent 1 data", embedding: [1, 0, 0], metadata: [:])
        try await adapter2.add(id: "delete-me", content: "Agent 2 data", embedding: [0, 1, 0], metadata: [:])

        // Agent2 tries to delete Agent1's entry - should be silently ignored
        try await adapter2.delete(ids: ["protected"])

        // Agent1's data should still exist (protected by namespace boundary)
        let results1 = try await adapter1.search(queryEmbedding: [1, 0, 0], limit: 10)
        #expect(results1.count == 1)
        #expect(results1[0].id == "protected")

        // Agent2's count should be unaffected
        #expect(try await adapter2.count() == 1)
    }

    @Test("Adapter count returns namespace-specific count")
    func countReturnsNamespaceCount() async throws {
        let store = InMemoryVectorStore()
        let adapter1 = ZoniVectorStoreAdapter(vectorStore: store, namespace: "agent1")
        let adapter2 = ZoniVectorStoreAdapter(vectorStore: store, namespace: "agent2")

        // Add entries to each namespace
        try await adapter1.add(id: "a1", content: "Agent 1 first", embedding: [1, 0, 0], metadata: [:])
        try await adapter1.add(id: "a2", content: "Agent 1 second", embedding: [0.9, 0.1, 0], metadata: [:])
        try await adapter2.add(id: "b1", content: "Agent 2 only", embedding: [0, 1, 0], metadata: [:])

        // Each adapter should return its own count
        #expect(try await adapter1.count() == 2)
        #expect(try await adapter2.count() == 1)
    }

    @Test("Default namespace is 'agent_memory'")
    func defaultNamespace() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        // Just verify it doesn't crash with default namespace
        try await adapter.add(id: "test", content: "Test", embedding: [1, 0, 0], metadata: [:])
        let results = try await adapter.search(queryEmbedding: [1, 0, 0], limit: 1)

        #expect(results.count == 1)
    }

    // MARK: - Protocol Conformance Tests

    @Test("Adapter conforms to AgentsVectorMemoryBackend")
    func conformsToProtocol() async throws {
        let store = InMemoryVectorStore()
        let adapter = ZoniVectorStoreAdapter(vectorStore: store)

        // Verify protocol conformance by using as protocol type
        let backend: any AgentsVectorMemoryBackend = adapter

        try await backend.add(id: "test", content: "Test", embedding: [1, 0, 0], metadata: [:])
        let count = try await backend.count()

        #expect(count == 1)
    }
}

// MARK: - MemorySearchResult Tests

@Suite("MemorySearchResult Tests")
struct MemorySearchResultTests {

    @Test("MemorySearchResult is equatable")
    func isEquatable() {
        let result1 = MemorySearchResult(id: "1", content: "Test", score: 0.9, metadata: [:])
        let result2 = MemorySearchResult(id: "1", content: "Test", score: 0.9, metadata: [:])
        let result3 = MemorySearchResult(id: "2", content: "Test", score: 0.9, metadata: [:])

        #expect(result1 == result2)
        #expect(result1 != result3)
    }

    @Test("MemorySearchResult is comparable by score")
    func isComparableByScore() {
        let low = MemorySearchResult(id: "1", content: "Low", score: 0.3, metadata: [:])
        let high = MemorySearchResult(id: "2", content: "High", score: 0.9, metadata: [:])

        #expect(low < high)
        #expect(high > low)
    }

    @Test("MemorySearchResult is hashable")
    func isHashable() {
        let result1 = MemorySearchResult(id: "1", content: "Test", score: 0.9, metadata: [:])
        let result2 = MemorySearchResult(id: "1", content: "Test", score: 0.9, metadata: [:])

        var set = Set<MemorySearchResult>()
        set.insert(result1)
        set.insert(result2)

        #expect(set.count == 1)
    }

    @Test("MemorySearchResult description truncates long content")
    func descriptionTruncatesContent() {
        let longContent = String(repeating: "a", count: 100)
        let result = MemorySearchResult(id: "1", content: longContent, score: 0.5, metadata: [:])

        let desc = result.description

        #expect(desc.contains("..."))
        #expect(!desc.contains(longContent))
    }

    @Test("MemorySearchResult description shows short content fully")
    func descriptionShowsShortContent() {
        let shortContent = "Short"
        let result = MemorySearchResult(id: "1", content: shortContent, score: 0.5, metadata: [:])

        let desc = result.description

        #expect(desc.contains(shortContent))
        #expect(!desc.contains("..."))
    }
}
