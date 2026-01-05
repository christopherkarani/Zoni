// ZoniAgents - SwiftAgents Integration for Zoni RAG Framework
//
// RetrieverAdapterTests.swift - Tests for ZoniRetrieverAdapter

import Testing
import Foundation
@testable import Zoni
@testable import ZoniAgents

// MARK: - ZoniRetrieverAdapter Tests

@Suite("ZoniRetrieverAdapter Tests")
struct ZoniRetrieverAdapterTests {

    // MARK: - Basic Retrieval Tests

    @Test("Adapter retrieves results from wrapped retriever")
    func retrievesResults() async throws {
        let mockRetriever = AgentsMockRetriever(results: [
            makeRetrievalResult(content: "First result", score: 0.9),
            makeRetrievalResult(content: "Second result", score: 0.8),
        ])
        let adapter = ZoniRetrieverAdapter(mockRetriever)

        let results = try await adapter.retrieve(query: "test query")

        #expect(results.count == 2)
        #expect(results[0].content == "First result")
        #expect(results[1].content == "Second result")
    }

    @Test("Adapter respects limit parameter")
    func respectsLimit() async throws {
        let mockRetriever = AgentsMockRetriever(results: [
            makeRetrievalResult(content: "1", score: 0.9),
            makeRetrievalResult(content: "2", score: 0.8),
            makeRetrievalResult(content: "3", score: 0.7),
            makeRetrievalResult(content: "4", score: 0.6),
            makeRetrievalResult(content: "5", score: 0.5),
        ])
        let adapter = ZoniRetrieverAdapter(mockRetriever)

        let results = try await adapter.retrieve(query: "test", limit: 3)

        #expect(results.count == 3)
    }

    @Test("Adapter uses default limit of 5")
    func usesDefaultLimit() async throws {
        let mockRetriever = AgentsMockRetriever(results: [])
        let adapter = ZoniRetrieverAdapter(mockRetriever)

        _ = try await adapter.retrieve(query: "test")

        #expect(await mockRetriever.lastLimit == 5)
    }

    // MARK: - Score Filtering Tests

    @Test("Adapter filters by minimum score")
    func filtersByMinScore() async throws {
        let mockRetriever = AgentsMockRetriever(results: [
            makeRetrievalResult(content: "High", score: 0.9),
            makeRetrievalResult(content: "Medium", score: 0.6),
            makeRetrievalResult(content: "Low", score: 0.3),
        ])
        let adapter = ZoniRetrieverAdapter(mockRetriever)

        let results = try await adapter.retrieve(query: "test", minScore: 0.5)

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.score >= 0.5 })
    }

    @Test("Adapter returns all results when minScore is nil")
    func returnsAllWhenNoMinScore() async throws {
        let mockRetriever = AgentsMockRetriever(results: [
            makeRetrievalResult(content: "High", score: 0.9),
            makeRetrievalResult(content: "Low", score: 0.1),
        ])
        let adapter = ZoniRetrieverAdapter(mockRetriever)

        let results = try await adapter.retrieve(query: "test", minScore: nil)

        #expect(results.count == 2)
    }

    @Test("Adapter handles minScore filtering all results")
    func handlesMinScoreFilteringAll() async throws {
        let mockRetriever = AgentsMockRetriever(results: [
            makeRetrievalResult(content: "Low1", score: 0.3),
            makeRetrievalResult(content: "Low2", score: 0.2),
        ])
        let adapter = ZoniRetrieverAdapter(mockRetriever)

        let results = try await adapter.retrieve(query: "test", minScore: 0.9)

        #expect(results.isEmpty)
    }

    // MARK: - Result Mapping Tests

    @Test("Adapter maps score correctly")
    func mapsScoreCorrectly() async throws {
        let mockRetriever = AgentsMockRetriever(results: [
            makeRetrievalResult(content: "Test", score: 0.876),
        ])
        let adapter = ZoniRetrieverAdapter(mockRetriever)

        let results = try await adapter.retrieve(query: "test")

        #expect(results[0].score == 0.876)
    }

    @Test("Adapter maps source from chunk metadata")
    func mapsSource() async throws {
        let chunk = makeChunk(content: "Test", source: "document.pdf")
        let mockRetriever = AgentsMockRetriever(results: [
            RetrievalResult(chunk: chunk, score: 0.9, metadata: [:])
        ])
        let adapter = ZoniRetrieverAdapter(mockRetriever)

        let results = try await adapter.retrieve(query: "test")

        #expect(results[0].source == "document.pdf")
    }

    @Test("Adapter handles nil source")
    func handlesNilSource() async throws {
        let chunk = makeChunk(content: "Test", source: nil)
        let mockRetriever = AgentsMockRetriever(results: [
            RetrievalResult(chunk: chunk, score: 0.9, metadata: [:])
        ])
        let adapter = ZoniRetrieverAdapter(mockRetriever)

        let results = try await adapter.retrieve(query: "test")

        #expect(results[0].source == nil)
    }

    // MARK: - Empty Results Tests

    @Test("Adapter handles empty results")
    func handlesEmptyResults() async throws {
        let mockRetriever = AgentsMockRetriever(results: [])
        let adapter = ZoniRetrieverAdapter(mockRetriever)

        let results = try await adapter.retrieve(query: "no matches")

        #expect(results.isEmpty)
    }

    // MARK: - Sendability Tests

    @Test("Adapter is Sendable")
    func isSendable() async {
        let mockRetriever = AgentsMockRetriever(results: [])
        let adapter = ZoniRetrieverAdapter(mockRetriever)

        // Test sendability by using in concurrent context
        await Task {
            _ = try? await adapter.retrieve(query: "test")
        }.value
    }
}

// MARK: - AgentRetrievalResult Tests

@Suite("AgentRetrievalResult Tests")
struct AgentRetrievalResultTests {

    @Test("AgentRetrievalResult stores all properties")
    func storesAllProperties() {
        let result = AgentRetrievalResult(
            id: "test-id",
            content: "Test content",
            score: 0.85,
            source: "test.pdf",
            documentId: "doc-1",
            chunkIndex: 5,
            metadata: ["key": "value"]
        )

        #expect(result.id == "test-id")
        #expect(result.content == "Test content")
        #expect(result.score == 0.85)
        #expect(result.source == "test.pdf")
        #expect(result.documentId == "doc-1")
        #expect(result.chunkIndex == 5)
        #expect(result.metadata["key"] == "value")
    }

    @Test("AgentRetrievalResult is Sendable")
    func isSendable() async {
        let result = AgentRetrievalResult(
            id: "test-id",
            content: "Test",
            score: 0.9,
            source: nil,
            metadata: [:]
        )

        _ = await Task {
            result.content
        }.value
    }

    @Test("AgentRetrievalResult is Hashable")
    func isHashable() {
        let result1 = AgentRetrievalResult(
            id: "test-id",
            content: "Test",
            score: 0.9,
            source: nil,
            metadata: [:]
        )
        let result2 = AgentRetrievalResult(
            id: "test-id",
            content: "Test",
            score: 0.9,
            source: nil,
            metadata: [:]
        )

        var set = Set<AgentRetrievalResult>()
        set.insert(result1)
        set.insert(result2)

        #expect(set.count == 1)
    }

    @Test("AgentRetrievalResult uses default values for optional fields")
    func usesDefaultValues() {
        let result = AgentRetrievalResult(
            id: "test-id",
            content: "Test",
            score: 0.5,
            source: nil,
            metadata: [:]
        )

        #expect(result.documentId == nil)
        #expect(result.chunkIndex == 0)
    }
}

// MARK: - Test Helpers

/// Mock retriever for testing adapter behavior.
actor AgentsMockRetriever: Retriever {
    nonisolated let name = "agents-mock"

    private let results: [RetrievalResult]
    private(set) var lastQuery: String?
    private(set) var lastLimit: Int?

    init(results: [RetrievalResult]) {
        self.results = results
    }

    func retrieve(
        query: String,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        lastQuery = query
        lastLimit = limit
        return Array(results.prefix(limit))
    }
}

private func makeChunk(
    id: String = UUID().uuidString,
    content: String,
    source: String? = nil
) -> Chunk {
    Chunk(
        id: id,
        content: content,
        metadata: ChunkMetadata(
            documentId: "doc-1",
            index: 0,
            startOffset: 0,
            endOffset: content.count,
            source: source,
            custom: [:]
        )
    )
}

private func makeRetrievalResult(
    content: String,
    score: Float,
    source: String? = nil
) -> RetrievalResult {
    RetrievalResult(
        chunk: makeChunk(content: content, source: source),
        score: score,
        metadata: [:]
    )
}
