// ZoniAgents - SwiftAgents Integration for Zoni RAG Framework
//
// FactoryTests.swift - Tests for ZoniAgents factory methods

import Testing
import Foundation
@testable import Zoni
@testable import ZoniAgents

// MARK: - ZoniAgents Factory Tests

@Suite("ZoniAgents Factory Tests")
struct ZoniAgentsFactoryTests {

    // MARK: - Embedding Provider Factory Tests

    @Test("embeddingProvider wraps any EmbeddingProvider")
    func embeddingProviderWrapsProvider() async throws {
        let mock = MockEmbedding(dimensions: 512)
        let adapter = ZoniAgents.embeddingProvider(mock)

        #expect(adapter.dimensions == 512)
        #expect(adapter.modelIdentifier == "mock")
    }

    // MARK: - Memory Backend Factory Tests

    @Test("memoryBackend creates adapter with default namespace")
    func memoryBackendDefaultNamespace() async throws {
        let store = InMemoryVectorStore()
        let backend = ZoniAgents.memoryBackend(vectorStore: store)

        // Should work without errors
        try await backend.add(id: "1", content: "Test", embedding: [1, 0, 0], metadata: [:])
        let count = try await backend.count()

        #expect(count == 1)
    }

    @Test("memoryBackend creates adapter with custom namespace")
    func memoryBackendCustomNamespace() async throws {
        let store = InMemoryVectorStore()
        let backend = ZoniAgents.memoryBackend(vectorStore: store, namespace: "custom")

        try await backend.add(id: "1", content: "Test", embedding: [1, 0, 0], metadata: [:])
        let count = try await backend.count()

        #expect(count == 1)
    }

    // MARK: - Retriever Adapter Factory Tests

    @Test("retrieverAdapter wraps any Retriever")
    func retrieverAdapterWrapsRetriever() async throws {
        let mockRetriever = FactoryMockRetriever(results: [])
        let adapter = ZoniAgents.retrieverAdapter(mockRetriever)

        let results = try await adapter.retrieve(query: "test")

        #expect(results.isEmpty)
    }
}

// MARK: - RAGToolBundle Tests

@Suite("RAGToolBundle Tests")
struct RAGToolBundleTests {

    @Test("searchOnly returns search tool only")
    func searchOnlyReturnsSearchTool() async throws {
        let mockRetriever = FactoryMockRetriever(results: [])
        let tools = RAGToolBundle.searchOnly(retriever: mockRetriever)

        #expect(tools.count == 1)
        #expect(tools[0].name == "search_knowledge")
    }
}

// MARK: - Test Helpers

/// Mock retriever for factory tests.
actor FactoryMockRetriever: Retriever {
    nonisolated let name = "factory-mock"

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
