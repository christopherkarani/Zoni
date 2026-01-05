// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RetrievalTests.swift - Tests for Retrieval Strategies (Phase 4A)

import Testing
import Foundation
@testable import Zoni

// MARK: - Test Helpers

private func makeChunk(
    id: String,
    content: String,
    documentId: String = "doc-1",
    index: Int = 0,
    custom: [String: MetadataValue] = [:]
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
            custom: custom
        )
    )
}

private func makeEmbedding(_ values: [Float]) -> Embedding {
    Embedding(vector: values, model: "test")
}

private func makeResult(id: String, content: String, score: Float) -> RetrievalResult {
    RetrievalResult(chunk: makeChunk(id: id, content: content), score: score)
}

// MARK: - VectorRetriever Tests

@Suite("VectorRetriever Tests")
struct VectorRetrieverTests {

    @Test("Basic retrieval returns results sorted by score")
    func testBasicRetrievalReturnsSortedResults() async throws {
        let store = InMemoryVectorStore()
        let mockEmbedding = MockEmbedding(dimensions: 3)

        // Set up mock embeddings for specific content
        await mockEmbedding.setMockEmbedding([1, 0, 0], for: "Swift programming")
        await mockEmbedding.setMockEmbedding([0, 1, 0], for: "Python scripting")
        await mockEmbedding.setMockEmbedding([0.9, 0.1, 0], for: "Swift code")

        let chunks = [
            makeChunk(id: "1", content: "Swift programming"),
            makeChunk(id: "2", content: "Python scripting"),
        ]

        let embeddings = try await mockEmbedding.embed(chunks.map(\.content))
        try await store.add(chunks, embeddings: embeddings)

        let retriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding
        )

        let results = try await retriever.retrieve(query: "Swift code", limit: 2, filter: nil)

        #expect(results.count == 2)
        #expect(results.first?.chunk.id == "1")  // Swift is more similar
    }

    @Test("Similarity threshold filters low-scoring results")
    func testSimilarityThresholdFiltersResults() async throws {
        let store = InMemoryVectorStore()
        let mockEmbedding = MockEmbedding(dimensions: 3)

        await mockEmbedding.setMockEmbedding([1, 0, 0], for: "High relevance")
        await mockEmbedding.setMockEmbedding([0, 0, 1], for: "Low relevance")
        await mockEmbedding.setMockEmbedding([0.9, 0.1, 0], for: "test query")

        let chunks = [
            makeChunk(id: "1", content: "High relevance"),
            makeChunk(id: "2", content: "Low relevance"),
        ]

        let embeddings = try await mockEmbedding.embed(chunks.map(\.content))
        try await store.add(chunks, embeddings: embeddings)

        let retriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding,
            similarityThreshold: 0.5
        )

        let results = try await retriever.retrieve(query: "test query", limit: 10, filter: nil)

        // Only high relevance should pass threshold
        #expect(results.count == 1)
        #expect(results.first?.chunk.id == "1")
    }

    @Test("Empty store returns empty results")
    func testEmptyStoreReturnsEmpty() async throws {
        let store = InMemoryVectorStore()
        let mockEmbedding = MockEmbedding(dimensions: 3)

        let retriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding
        )

        let results = try await retriever.retrieve(query: "test", limit: 5, filter: nil)

        #expect(results.isEmpty)
    }

    @Test("Metadata filter is applied correctly")
    func testMetadataFilterApplied() async throws {
        let store = InMemoryVectorStore()
        let mockEmbedding = MockEmbedding(dimensions: 3)

        await mockEmbedding.setMockEmbedding([1, 0, 0], for: "Doc A content")
        await mockEmbedding.setMockEmbedding([0.9, 0.1, 0], for: "Doc B content")
        await mockEmbedding.setMockEmbedding([1, 0, 0], for: "query")

        let chunks = [
            makeChunk(id: "1", content: "Doc A content", custom: ["category": "tech"]),
            makeChunk(id: "2", content: "Doc B content", custom: ["category": "finance"]),
        ]

        let embeddings = try await mockEmbedding.embed(chunks.map(\.content))
        try await store.add(chunks, embeddings: embeddings)

        let retriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding
        )

        let results = try await retriever.retrieve(
            query: "query",
            limit: 10,
            filter: .equals("category", "finance")
        )

        #expect(results.count == 1)
        #expect(results.first?.chunk.id == "2")
    }

    @Test("Limit is respected")
    func testLimitRespected() async throws {
        let store = InMemoryVectorStore()
        let mockEmbedding = MockEmbedding(dimensions: 3)

        // Add 10 chunks
        var chunks: [Chunk] = []
        for i in 0..<10 {
            chunks.append(makeChunk(id: "\(i)", content: "Content \(i)"))
        }

        let embeddings = try await mockEmbedding.embed(chunks.map(\.content))
        try await store.add(chunks, embeddings: embeddings)

        let retriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding
        )

        let results = try await retriever.retrieve(query: "test", limit: 3, filter: nil)

        #expect(results.count == 3)
    }
}

// MARK: - KeywordRetriever Tests

@Suite("KeywordRetriever Tests")
struct KeywordRetrieverTests {

    @Test("BM25 scoring ranks relevant chunks higher")
    func testBM25Scoring() async throws {
        let retriever = KeywordRetriever()

        await retriever.index([
            makeChunk(id: "1", content: "Swift is a programming language for iOS development"),
            makeChunk(id: "2", content: "Python is great for machine learning"),
            makeChunk(id: "3", content: "Swift can also be used for server-side development"),
        ])

        let results = try await retriever.retrieve(query: "Swift programming", limit: 2, filter: nil)

        #expect(results.count == 2)
        // Both Swift chunks should rank higher than Python
        #expect(results.allSatisfy { $0.chunk.content.contains("Swift") })
    }

    @Test("Query with no matches returns empty")
    func testNoMatchesReturnsEmpty() async throws {
        let retriever = KeywordRetriever()

        await retriever.index([
            makeChunk(id: "1", content: "Swift programming language"),
        ])

        let results = try await retriever.retrieve(query: "Python machine learning", limit: 5, filter: nil)

        #expect(results.isEmpty)
    }

    @Test("Index stores chunks correctly")
    func testIndexStoresChunks() async throws {
        let retriever = KeywordRetriever()

        let chunks = [
            makeChunk(id: "1", content: "Hello world"),
            makeChunk(id: "2", content: "Goodbye world"),
        ]

        await retriever.index(chunks)

        let count = await retriever.indexedCount()
        #expect(count == 2)
    }

    @Test("Remove from index works correctly")
    func testRemoveFromIndex() async throws {
        let retriever = KeywordRetriever()

        await retriever.index([
            makeChunk(id: "1", content: "Hello world"),
            makeChunk(id: "2", content: "Goodbye world"),
        ])

        await retriever.removeFromIndex(ids: ["1"])

        let count = await retriever.indexedCount()
        #expect(count == 1)

        let results = try await retriever.retrieve(query: "Hello", limit: 5, filter: nil)
        #expect(results.isEmpty)
    }

    @Test("Clear index removes all data")
    func testClearIndex() async throws {
        let retriever = KeywordRetriever()

        await retriever.index([
            makeChunk(id: "1", content: "Hello world"),
            makeChunk(id: "2", content: "Goodbye world"),
        ])

        await retriever.clearIndex()

        let count = await retriever.indexedCount()
        #expect(count == 0)
    }

    @Test("Metadata filter is applied during search")
    func testMetadataFilterApplied() async throws {
        let retriever = KeywordRetriever()

        await retriever.index([
            makeChunk(id: "1", content: "Swift programming language", custom: ["type": "tech"]),
            makeChunk(id: "2", content: "Swift bird species", custom: ["type": "nature"]),
        ])

        let results = try await retriever.retrieve(
            query: "Swift",
            limit: 10,
            filter: .equals("type", "nature")
        )

        #expect(results.count == 1)
        #expect(results.first?.chunk.id == "2")
    }

    @Test("Tokenization handles edge cases")
    func testTokenizationEdgeCases() async throws {
        let retriever = KeywordRetriever()

        await retriever.index([
            makeChunk(id: "1", content: "Hello, World! This is a test."),
            makeChunk(id: "2", content: "HELLO world THIS IS ANOTHER TEST"),
        ])

        // Should match both due to case-insensitive tokenization
        let results = try await retriever.retrieve(query: "hello test", limit: 5, filter: nil)

        #expect(results.count == 2)
    }

    @Test("Stopwords are filtered")
    func testStopwordsFiltered() async throws {
        let retriever = KeywordRetriever()

        await retriever.index([
            makeChunk(id: "1", content: "The quick brown fox"),
            makeChunk(id: "2", content: "A lazy dog"),
        ])

        // Searching for "the a" should return nothing since these are stopwords
        let results = try await retriever.retrieve(query: "the", limit: 5, filter: nil)

        #expect(results.isEmpty)
    }
}

// MARK: - HybridRetriever Tests

@Suite("HybridRetriever Tests")
struct HybridRetrieverTests {

    @Test("Combines results from both retrievers")
    func testCombinesResults() async throws {
        let store = InMemoryVectorStore()
        let mockEmbedding = MockEmbedding(dimensions: 3)

        let chunks = [
            makeChunk(id: "1", content: "Swift programming language"),
            makeChunk(id: "2", content: "iOS development guide"),
            makeChunk(id: "3", content: "Python for beginners"),
        ]

        let embeddings = try await mockEmbedding.embed(chunks.map(\.content))
        try await store.add(chunks, embeddings: embeddings)

        let vectorRetriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding
        )

        let keywordRetriever = KeywordRetriever()
        await keywordRetriever.index(chunks)

        let hybridRetriever = HybridRetriever(
            vectorRetriever: vectorRetriever,
            keywordRetriever: keywordRetriever
        )

        let results = try await hybridRetriever.retrieve(query: "Swift programming", limit: 3, filter: nil)

        #expect(!results.isEmpty)
        // Swift should be top result due to keyword match
    }

    @Test("RRF fusion produces stable rankings")
    func testRRFFusion() async throws {
        let store = InMemoryVectorStore()
        let mockEmbedding = MockEmbedding(dimensions: 3)

        await mockEmbedding.setMockEmbedding([1, 0, 0], for: "Swift code")
        await mockEmbedding.setMockEmbedding([0.9, 0.1, 0], for: "Swift programming")
        await mockEmbedding.setMockEmbedding([0.5, 0.5, 0], for: "Python code")
        await mockEmbedding.setMockEmbedding([0.95, 0.05, 0], for: "Swift query")

        let chunks = [
            makeChunk(id: "1", content: "Swift code"),
            makeChunk(id: "2", content: "Swift programming"),
            makeChunk(id: "3", content: "Python code"),
        ]

        let embeddings = try await mockEmbedding.embed(chunks.map(\.content))
        try await store.add(chunks, embeddings: embeddings)

        let vectorRetriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding
        )

        let keywordRetriever = KeywordRetriever()
        await keywordRetriever.index(chunks)

        let hybridRetriever = HybridRetriever(
            vectorRetriever: vectorRetriever,
            keywordRetriever: keywordRetriever
        )
        await hybridRetriever.setFusionMethod(.reciprocalRankFusion(k: 60))

        // Run multiple times to ensure stability
        let results1 = try await hybridRetriever.retrieve(query: "Swift query", limit: 3, filter: nil)
        let results2 = try await hybridRetriever.retrieve(query: "Swift query", limit: 3, filter: nil)

        #expect(results1.map(\.id) == results2.map(\.id))
    }

    @Test("Weighted sum respects vectorWeight")
    func testWeightedSum() async throws {
        let store = InMemoryVectorStore()
        let mockEmbedding = MockEmbedding(dimensions: 3)

        let chunks = [
            makeChunk(id: "1", content: "Swift programming"),
        ]

        let embeddings = try await mockEmbedding.embed(chunks.map(\.content))
        try await store.add(chunks, embeddings: embeddings)

        let vectorRetriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding
        )

        let keywordRetriever = KeywordRetriever()
        await keywordRetriever.index(chunks)

        let hybridRetriever = HybridRetriever(
            vectorRetriever: vectorRetriever,
            keywordRetriever: keywordRetriever,
            vectorWeight: 0.8  // 80% vector, 20% keyword
        )
        await hybridRetriever.setFusionMethod(.weightedSum)

        let results = try await hybridRetriever.retrieve(query: "Swift", limit: 3, filter: nil)

        #expect(!results.isEmpty)
    }

    @Test("Results are deduplicated by chunk ID")
    func testDeduplication() async throws {
        let store = InMemoryVectorStore()
        let mockEmbedding = MockEmbedding(dimensions: 3)

        let chunks = [
            makeChunk(id: "1", content: "Swift programming"),
        ]

        let embeddings = try await mockEmbedding.embed(chunks.map(\.content))
        try await store.add(chunks, embeddings: embeddings)

        let vectorRetriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding
        )

        let keywordRetriever = KeywordRetriever()
        await keywordRetriever.index(chunks)

        let hybridRetriever = HybridRetriever(
            vectorRetriever: vectorRetriever,
            keywordRetriever: keywordRetriever
        )

        let results = try await hybridRetriever.retrieve(query: "Swift", limit: 10, filter: nil)

        // Same chunk should only appear once
        let uniqueIds = Set(results.map(\.id))
        #expect(results.count == uniqueIds.count)
    }
}

// MARK: - MMRRetriever Tests

@Suite("MMRRetriever Tests")
struct MMRRetrieverTests {

    @Test("Lambda 1.0 returns same order as base retriever")
    func testLambdaOnePureRelevance() async throws {
        let store = InMemoryVectorStore()
        let mockEmbedding = MockEmbedding(dimensions: 3)

        await mockEmbedding.setMockEmbedding([1, 0, 0], for: "A")
        await mockEmbedding.setMockEmbedding([0.9, 0.1, 0], for: "B")
        await mockEmbedding.setMockEmbedding([0.5, 0.5, 0], for: "C")
        await mockEmbedding.setMockEmbedding([1, 0, 0], for: "query")

        let chunks = [
            makeChunk(id: "1", content: "A"),
            makeChunk(id: "2", content: "B"),
            makeChunk(id: "3", content: "C"),
        ]

        let embeddings = try await mockEmbedding.embed(chunks.map(\.content))
        try await store.add(chunks, embeddings: embeddings)

        let baseRetriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding
        )

        let mmrRetriever = MMRRetriever(
            baseRetriever: baseRetriever,
            embeddingProvider: mockEmbedding,
            lambda: 1.0  // Pure relevance
        )

        let baseResults = try await baseRetriever.retrieve(query: "query", limit: 3, filter: nil)
        let mmrResults = try await mmrRetriever.retrieve(query: "query", limit: 3, filter: nil)

        // With lambda=1.0, should have same order as base retriever
        #expect(mmrResults.map(\.id) == baseResults.map(\.id))
    }

    @Test("Lambda 0.5 produces diverse results")
    func testLambdaHalfDiversity() async throws {
        let store = InMemoryVectorStore()
        let mockEmbedding = MockEmbedding(dimensions: 3)

        // Set up similar and diverse embeddings
        await mockEmbedding.setMockEmbedding([1, 0, 0], for: "Similar A")
        await mockEmbedding.setMockEmbedding([0.99, 0.01, 0], for: "Similar B")  // Very similar to A
        await mockEmbedding.setMockEmbedding([0, 1, 0], for: "Different C")       // Orthogonal
        await mockEmbedding.setMockEmbedding([1, 0, 0], for: "query")

        let chunks = [
            makeChunk(id: "1", content: "Similar A"),
            makeChunk(id: "2", content: "Similar B"),
            makeChunk(id: "3", content: "Different C"),
        ]

        let embeddings = try await mockEmbedding.embed(chunks.map(\.content))
        try await store.add(chunks, embeddings: embeddings)

        let baseRetriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding
        )

        let mmrRetriever = MMRRetriever(
            baseRetriever: baseRetriever,
            embeddingProvider: mockEmbedding,
            lambda: 0.5  // Balance relevance and diversity
        )

        let mmrResults = try await mmrRetriever.retrieve(query: "query", limit: 3, filter: nil)

        #expect(mmrResults.count == 3)
        // "Different C" should appear earlier than with pure relevance due to diversity bonus
    }

    @Test("Lambda 0.0 maximizes diversity")
    func testLambdaZeroPureDiversity() async throws {
        let store = InMemoryVectorStore()
        let mockEmbedding = MockEmbedding(dimensions: 3)

        await mockEmbedding.setMockEmbedding([1, 0, 0], for: "A")
        await mockEmbedding.setMockEmbedding([1, 0, 0], for: "B")  // Same as A
        await mockEmbedding.setMockEmbedding([0, 1, 0], for: "C")  // Different
        await mockEmbedding.setMockEmbedding([1, 0, 0], for: "query")

        let chunks = [
            makeChunk(id: "1", content: "A"),
            makeChunk(id: "2", content: "B"),
            makeChunk(id: "3", content: "C"),
        ]

        let embeddings = try await mockEmbedding.embed(chunks.map(\.content))
        try await store.add(chunks, embeddings: embeddings)

        let baseRetriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding
        )

        let mmrRetriever = MMRRetriever(
            baseRetriever: baseRetriever,
            embeddingProvider: mockEmbedding,
            lambda: 0.0  // Pure diversity
        )

        let mmrResults = try await mmrRetriever.retrieve(query: "query", limit: 2, filter: nil)

        // Should select diverse items rather than all similar ones
        #expect(mmrResults.count == 2)
    }

    @Test("Handles empty candidates gracefully")
    func testEmptyCandidates() async throws {
        let store = InMemoryVectorStore()  // Empty store
        let mockEmbedding = MockEmbedding(dimensions: 3)

        let baseRetriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding
        )

        let mmrRetriever = MMRRetriever(
            baseRetriever: baseRetriever,
            embeddingProvider: mockEmbedding
        )

        let results = try await mmrRetriever.retrieve(query: "test", limit: 5, filter: nil)

        #expect(results.isEmpty)
    }
}

// MARK: - MockReranker Tests

@Suite("MockReranker Tests")
struct MockRerankerTests {

    @Test("Returns results with mock scores")
    func testReturnsWithMockScores() async throws {
        let reranker = MockReranker()
        await reranker.setMockScore(0.9, for: "1")
        await reranker.setMockScore(0.5, for: "2")

        let results = [
            makeResult(id: "1", content: "A", score: 0.3),
            makeResult(id: "2", content: "B", score: 0.8),
        ]

        let reranked = try await reranker.rerank(query: "test", results: results)

        #expect(reranked.count == 2)
        // Should be reordered by mock scores
        #expect(reranked.first?.id == "1")
        #expect(reranked.first?.score == 0.9)
    }

    @Test("Records rerank calls")
    func testRecordsCalls() async throws {
        let reranker = MockReranker()

        let results = [makeResult(id: "1", content: "A", score: 0.5)]

        _ = try await reranker.rerank(query: "test query", results: results)
        _ = try await reranker.rerank(query: "another query", results: results)

        let calls = await reranker.getRecordedCalls()
        #expect(calls.count == 2)
        #expect(calls[0].query == "test query")
        #expect(calls[1].query == "another query")
    }

    @Test("Failure simulation works")
    func testFailureSimulation() async throws {
        let reranker = MockReranker()
        await reranker.setFailure(true, message: "API error")

        let results = [makeResult(id: "1", content: "A", score: 0.5)]

        await #expect(throws: ZoniError.self) {
            _ = try await reranker.rerank(query: "test", results: results)
        }
    }

    @Test("Reset clears state")
    func testReset() async throws {
        let reranker = MockReranker()
        await reranker.setMockScore(0.9, for: "1")
        await reranker.setFailure(true)

        let results = [makeResult(id: "1", content: "A", score: 0.5)]
        _ = try? await reranker.rerank(query: "test", results: results)

        await reranker.reset()

        // Should work after reset
        let reranked = try await reranker.rerank(query: "test", results: results)
        #expect(!reranked.isEmpty)
    }
}

// MARK: - RerankerRetriever Tests

@Suite("RerankerRetriever Tests")
struct RerankerRetrieverTests {

    @Test("Reranking changes result order")
    func testRerankerChangesOrder() async throws {
        let store = InMemoryVectorStore()
        let mockEmbedding = MockEmbedding(dimensions: 3)

        let chunks = [
            makeChunk(id: "1", content: "First"),
            makeChunk(id: "2", content: "Second"),
        ]

        let embeddings = try await mockEmbedding.embed(chunks.map(\.content))
        try await store.add(chunks, embeddings: embeddings)

        let baseRetriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding
        )

        let mockReranker = MockReranker()
        await mockReranker.setMockScore(0.9, for: "2")  // Make second chunk rank first
        await mockReranker.setMockScore(0.1, for: "1")

        let rerankerRetriever = RerankerRetriever(
            baseRetriever: baseRetriever,
            reranker: mockReranker
        )

        let results = try await rerankerRetriever.retrieve(query: "test", limit: 2, filter: nil)

        #expect(results.first?.id == "2")  // Second should now be first
    }

    @Test("Uses initialLimit for candidate fetching")
    func testInitialLimit() async throws {
        let store = InMemoryVectorStore()
        let mockEmbedding = MockEmbedding(dimensions: 3)

        // Add 10 chunks
        var chunks: [Chunk] = []
        for i in 0..<10 {
            chunks.append(makeChunk(id: "\(i)", content: "Content \(i)"))
        }

        let embeddings = try await mockEmbedding.embed(chunks.map(\.content))
        try await store.add(chunks, embeddings: embeddings)

        let baseRetriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding
        )

        let mockReranker = MockReranker()

        let rerankerRetriever = RerankerRetriever(
            baseRetriever: baseRetriever,
            reranker: mockReranker,
            initialLimit: 5  // Fetch 5 candidates
        )

        let results = try await rerankerRetriever.retrieve(query: "test", limit: 2, filter: nil)

        #expect(results.count == 2)

        // Check that reranker received 5 candidates (initialLimit)
        let calls = await mockReranker.getRecordedCalls()
        #expect(calls.first?.resultCount == 5)
    }

    @Test("Name includes base retriever name")
    func testNameIncludesBase() async throws {
        let store = InMemoryVectorStore()
        let mockEmbedding = MockEmbedding(dimensions: 3)

        let baseRetriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding
        )

        let rerankerRetriever = RerankerRetriever(
            baseRetriever: baseRetriever,
            reranker: MockReranker()
        )

        #expect(rerankerRetriever.name.contains("vector"))
    }
}

// MARK: - MultiQueryRetriever Tests

@Suite("MultiQueryRetriever Tests")
struct MultiQueryRetrieverTests {

    @Test("Generates multiple query variations")
    func testGeneratesVariations() async throws {
        let store = InMemoryVectorStore()
        let mockEmbedding = MockEmbedding(dimensions: 3)
        let mockLLM = RetrievalMockLLMProvider()

        // Configure LLM to return variations
        await mockLLM.setResponse("""
            What is Swift used for?
            How does Swift work?
            """)

        let chunks = [
            makeChunk(id: "1", content: "Swift programming"),
        ]

        let embeddings = try await mockEmbedding.embed(chunks.map(\.content))
        try await store.add(chunks, embeddings: embeddings)

        let baseRetriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding
        )

        let multiQueryRetriever = MultiQueryRetriever(
            baseRetriever: baseRetriever,
            llmProvider: mockLLM,
            numQueries: 3
        )

        let results = try await multiQueryRetriever.retrieve(query: "What is Swift?", limit: 5, filter: nil)

        // LLM should have been called to generate queries
        let llmCalls = await mockLLM.getCallCount()
        #expect(llmCalls >= 1)

        #expect(!results.isEmpty)
    }

    @Test("Always includes original query")
    func testIncludesOriginal() async throws {
        let store = InMemoryVectorStore()
        let mockEmbedding = MockEmbedding(dimensions: 3)
        let mockLLM = RetrievalMockLLMProvider()

        // Return empty variations
        await mockLLM.setResponse("")

        let chunks = [
            makeChunk(id: "1", content: "Swift programming"),
        ]

        let embeddings = try await mockEmbedding.embed(chunks.map(\.content))
        try await store.add(chunks, embeddings: embeddings)

        let baseRetriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding
        )

        let multiQueryRetriever = MultiQueryRetriever(
            baseRetriever: baseRetriever,
            llmProvider: mockLLM
        )

        // Even with empty LLM response, should still use original query
        let results = try await multiQueryRetriever.retrieve(query: "Swift", limit: 5, filter: nil)

        #expect(!results.isEmpty)
    }

    @Test("Merges results correctly")
    func testMergesResults() async throws {
        let store = InMemoryVectorStore()
        let mockEmbedding = MockEmbedding(dimensions: 3)
        let mockLLM = RetrievalMockLLMProvider()

        await mockLLM.setResponse("Alternative query")

        let chunks = [
            makeChunk(id: "1", content: "Swift programming"),
            makeChunk(id: "2", content: "iOS development"),
        ]

        let embeddings = try await mockEmbedding.embed(chunks.map(\.content))
        try await store.add(chunks, embeddings: embeddings)

        let baseRetriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding
        )

        let multiQueryRetriever = MultiQueryRetriever(
            baseRetriever: baseRetriever,
            llmProvider: mockLLM
        )

        let results = try await multiQueryRetriever.retrieve(query: "Swift", limit: 5, filter: nil)

        // Results should be deduplicated
        let uniqueIds = Set(results.map(\.id))
        #expect(results.count == uniqueIds.count)
    }

    @Test("Custom prompt is used when provided")
    func testCustomPrompt() async throws {
        let store = InMemoryVectorStore()
        let mockEmbedding = MockEmbedding(dimensions: 3)
        let mockLLM = RetrievalMockLLMProvider()

        await mockLLM.setResponse("Variation 1")

        let chunks = [makeChunk(id: "1", content: "Test")]
        let embeddings = try await mockEmbedding.embed(chunks.map(\.content))
        try await store.add(chunks, embeddings: embeddings)

        let baseRetriever = VectorRetriever(
            vectorStore: store,
            embeddingProvider: mockEmbedding
        )

        let multiQueryRetriever = MultiQueryRetriever(
            baseRetriever: baseRetriever,
            llmProvider: mockLLM
        )

        await multiQueryRetriever.setQueryGenerationPrompt("Custom prompt: {query}")

        _ = try await multiQueryRetriever.retrieve(query: "test", limit: 5, filter: nil)

        let prompts = await mockLLM.getRecordedPrompts()
        #expect(prompts.first?.contains("Custom prompt") == true)
    }
}

// MARK: - Retrieval Mock LLM Provider

/// Mock LLM provider specifically for retrieval tests.
actor RetrievalMockLLMProvider: LLMProvider {
    nonisolated let name = "mock"
    nonisolated let model = "mock-model"
    nonisolated let maxContextTokens = 4096

    private var mockResponse: String = ""
    private var shouldFail: Bool = false
    private var recordedPrompts: [String] = []
    private var callCount: Int = 0

    func setResponse(_ response: String) {
        self.mockResponse = response
    }

    func setFailure(_ shouldFail: Bool) {
        self.shouldFail = shouldFail
    }

    func getRecordedPrompts() -> [String] {
        recordedPrompts
    }

    func getCallCount() -> Int {
        callCount
    }

    func generate(prompt: String, systemPrompt: String?, options: LLMOptions) async throws -> String {
        callCount += 1
        recordedPrompts.append(prompt)

        if shouldFail {
            throw ZoniError.generationFailed(reason: "Mock failure")
        }

        return mockResponse
    }

    nonisolated func stream(prompt: String, systemPrompt: String?, options: LLMOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("")
            continuation.finish()
        }
    }
}

// MARK: - RetrievalUtils Tests

@Suite("RetrievalUtils Tests")
struct RetrievalUtilsTests {

    @Test("Tokenize splits and lowercases text")
    func testTokenize() {
        let tokens = RetrievalUtils.tokenize("Hello, World! This is a TEST.")

        #expect(tokens.contains("hello"))
        #expect(tokens.contains("world"))
        #expect(tokens.contains("test"))
        // Short words and stopwords should be filtered
        #expect(!tokens.contains("is"))
        #expect(!tokens.contains("a"))
    }

    @Test("Tokenize with custom min length")
    func testTokenizeMinLength() {
        // Use filterStopwords: false to test minLength in isolation
        let tokens = RetrievalUtils.tokenize("Go to the store", minLength: 2, filterStopwords: false)

        #expect(tokens.contains("go"))
        #expect(tokens.contains("to"))
        #expect(tokens.contains("the"))
    }

    @Test("Normalize score handles edge cases")
    func testNormalizeScore() {
        #expect(RetrievalUtils.normalizeScore(0.5, min: 0, max: 1) == 0.5)
        #expect(RetrievalUtils.normalizeScore(0, min: 0, max: 1) == 0)
        #expect(RetrievalUtils.normalizeScore(1, min: 0, max: 1) == 1)
        #expect(RetrievalUtils.normalizeScore(5, min: 0, max: 10) == 0.5)

        // Edge case: min == max
        #expect(RetrievalUtils.normalizeScore(5, min: 5, max: 5) == 0)
    }

    @Test("Tokenize handles empty string")
    func testTokenizeEmptyString() {
        let tokens = RetrievalUtils.tokenize("")
        #expect(tokens.isEmpty)
    }

    @Test("Tokenize handles whitespace-only string")
    func testTokenizeWhitespaceOnly() {
        let tokens = RetrievalUtils.tokenize("   \n\t\r   ")
        #expect(tokens.isEmpty)
    }

    @Test("Tokenize handles Unicode accented characters")
    func testTokenizeUnicode() {
        let tokens = RetrievalUtils.tokenize("Café résumé naïve", filterStopwords: false)
        #expect(tokens.contains("café"))
        #expect(tokens.contains("résumé"))
        #expect(tokens.contains("naïve"))
    }

    @Test("Tokenize handles emojis gracefully")
    func testTokenizeEmojis() {
        let tokens = RetrievalUtils.tokenize("Hello 🌍 world! Test 👍")
        #expect(tokens.contains("hello"))
        #expect(tokens.contains("world"))
        #expect(tokens.contains("test"))
        // Emojis should be filtered out (not alphanumeric)
        #expect(!tokens.contains("🌍"))
        #expect(!tokens.contains("👍"))
    }

    @Test("Tokenize handles numbers and alphanumeric")
    func testTokenizeNumbersAndAlphanumeric() {
        let tokens = RetrievalUtils.tokenize("Swift5 iOS17 2024 abc123", filterStopwords: false)
        #expect(tokens.contains("swift5"))
        #expect(tokens.contains("ios17"))
        #expect(tokens.contains("2024"))
        #expect(tokens.contains("abc123"))
    }

    @Test("Term frequency counts correctly")
    func testTermFrequency() {
        let tokens = ["hello", "world", "hello", "test", "hello"]
        #expect(RetrievalUtils.termFrequency("hello", in: tokens) == 3)
        #expect(RetrievalUtils.termFrequency("world", in: tokens) == 1)
        #expect(RetrievalUtils.termFrequency("missing", in: tokens) == 0)
    }

    @Test("Term frequency handles empty tokens")
    func testTermFrequencyEmpty() {
        #expect(RetrievalUtils.termFrequency("test", in: []) == 0)
    }

    @Test("Stopwords list includes common words")
    func testStopwordsContainsCommonWords() {
        #expect(RetrievalUtils.stopWords.contains("the"))
        #expect(RetrievalUtils.stopWords.contains("and"))
        #expect(RetrievalUtils.stopWords.contains("or"))
        #expect(RetrievalUtils.stopWords.contains("is"))
        #expect(RetrievalUtils.stopWords.contains("are"))
    }
}
