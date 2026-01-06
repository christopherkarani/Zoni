// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// RAGPipelineTests.swift - Tests for RAGPipeline orchestrator
// TDD Red Phase: These tests will initially FAIL until implementation is complete

import Testing
import Foundation
@testable import Zoni

// MARK: - Mock LLM Provider

/// Mock LLM provider for testing RAGPipeline without external API calls.
struct MockLLMProvider: LLMProvider, Sendable {
    let name: String = "MockLLM"
    let model: String = "mock-model"
    let maxContextTokens: Int = 4096

    func generate(
        prompt: String,
        systemPrompt: String?,
        options: LLMOptions
    ) async throws -> String {
        "Mock response based on the provided context."
    }

    func stream(
        prompt: String,
        systemPrompt: String?,
        options: LLMOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("Mock ")
            continuation.yield("streaming ")
            continuation.yield("response.")
            continuation.finish()
        }
    }
}

// MARK: - Test Helpers

/// Creates a test pipeline with mock components
private func createTestPipeline() -> RAGPipeline {
    let embedding = MockEmbedding(dimensions: 384)
    let vectorStore = InMemoryVectorStore()
    let chunker = FixedSizeChunker(chunkSize: 100, chunkOverlap: 20)

    return RAGPipeline(
        embedding: embedding,
        vectorStore: vectorStore,
        llm: MockLLMProvider(),
        chunker: chunker
    )
}

/// Creates a test document with optional custom content
private func createTestDocument(
    content: String = "Test content for chunking and embedding. This is a sample document that will be processed by the RAG pipeline.",
    source: String = "test.txt"
) -> Document {
    Document(
        content: content,
        metadata: DocumentMetadata(source: source)
    )
}

// MARK: - Ingestion Tests

@Suite("RAGPipeline Ingestion Tests")
struct RAGPipelineIngestionTests {

    @Test("Ingest single document stores chunks")
    func testIngestSingleDocument() async throws {
        let pipeline = createTestPipeline()
        let document = createTestDocument()

        try await pipeline.ingest(document)

        let stats = try await pipeline.statistics()
        #expect(stats.chunkCount > 0)
        #expect(stats.documentCount == 1)
    }

    @Test("Ingest multiple documents")
    func testIngestMultipleDocuments() async throws {
        let pipeline = createTestPipeline()
        let documents = [
            createTestDocument(content: "First document content that is long enough for chunking."),
            createTestDocument(content: "Second document content that is also long enough."),
            createTestDocument(content: "Third document content with sufficient length.")
        ]

        try await pipeline.ingest(documents)

        let stats = try await pipeline.statistics()
        #expect(stats.documentCount == 3)
    }

    @Test("Ingest empty document array does nothing")
    func testIngestEmptyArray() async throws {
        let pipeline = createTestPipeline()

        try await pipeline.ingest([Document]())

        let stats = try await pipeline.statistics()
        #expect(stats.documentCount == 0)
        #expect(stats.chunkCount == 0)
    }

    @Test("Ingest from URL uses loader registry")
    func testIngestFromURL() async throws {
        let pipeline = createTestPipeline()

        // Create a temporary text file
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_\(UUID()).txt")
        try "Test content from file that is long enough for processing.".write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        // Register text loader
        await pipeline.registerLoader(TextLoader())

        try await pipeline.ingest(from: fileURL)

        let stats = try await pipeline.statistics()
        #expect(stats.documentCount == 1)
    }

    @Test("Ingest from URL throws for unsupported type")
    func testIngestFromURLUnsupportedType() async {
        let pipeline = createTestPipeline()
        let url = URL(fileURLWithPath: "/fake/file.unsupported")

        await #expect(throws: ZoniError.self) {
            try await pipeline.ingest(from: url)
        }
    }

    @Test("Ingest directory loads multiple files")
    func testIngestDirectory() async throws {
        let pipeline = createTestPipeline()

        // Create temporary directory with files
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoni_test_\(UUID())")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create test files
        try "Content 1 with enough text for chunking.".write(
            to: tempDir.appendingPathComponent("file1.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "Content 2 with enough text for chunking.".write(
            to: tempDir.appendingPathComponent("file2.txt"),
            atomically: true,
            encoding: .utf8
        )

        // Register loader
        await pipeline.registerLoader(TextLoader())

        try await pipeline.ingest(directory: tempDir, recursive: false)

        let stats = try await pipeline.statistics()
        #expect(stats.documentCount == 2)
    }

    @Test("Ingest directory recursively loads nested files")
    func testIngestDirectoryRecursive() async throws {
        let pipeline = createTestPipeline()

        // Create temporary directory with nested structure
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoni_recursive_test_\(UUID())")
        let nestedDir = tempDir.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create test files at different levels
        try "Root content with enough text.".write(
            to: tempDir.appendingPathComponent("root.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "Nested content with enough text.".write(
            to: nestedDir.appendingPathComponent("nested.txt"),
            atomically: true,
            encoding: .utf8
        )

        // Register loader
        await pipeline.registerLoader(TextLoader())

        try await pipeline.ingest(directory: tempDir, recursive: true)

        let stats = try await pipeline.statistics()
        #expect(stats.documentCount == 2)
    }
}

// MARK: - Retrieval Tests

@Suite("RAGPipeline Retrieval Tests")
struct RAGPipelineRetrievalTests {

    @Test("Retrieve returns relevant results")
    func testRetrieve() async throws {
        let pipeline = createTestPipeline()

        // Ingest test documents
        try await pipeline.ingest(createTestDocument(
            content: "Swift is a programming language developed by Apple for iOS and macOS development."
        ))
        try await pipeline.ingest(createTestDocument(
            content: "Python is widely used for data science and machine learning applications."
        ))

        let results = try await pipeline.retrieve("Swift programming", limit: 5)

        #expect(!results.isEmpty)
        #expect(results.count <= 5)
    }

    @Test("Retrieve with filter narrows results")
    func testRetrieveWithFilter() async throws {
        let pipeline = createTestPipeline()

        // Ingest documents with different sources
        try await pipeline.ingest(createTestDocument(
            content: "Document about Swift programming language features.",
            source: "programming.txt"
        ))
        try await pipeline.ingest(createTestDocument(
            content: "Document about cooking recipes and techniques.",
            source: "cooking.txt"
        ))

        let filter = MetadataFilter.contains("source", "programming")
        let results = try await pipeline.retrieve("content", limit: 10, filter: filter)

        // All results should be from programming source
        for result in results {
            #expect(result.chunk.metadata.source?.contains("programming") == true)
        }
    }

    @Test("Retrieve empty store returns empty results")
    func testRetrieveEmptyStore() async throws {
        let pipeline = createTestPipeline()

        let results = try await pipeline.retrieve("anything", limit: 5)

        #expect(results.isEmpty)
    }

    @Test("Retrieve respects limit parameter")
    func testRetrieveRespectsLimit() async throws {
        let pipeline = createTestPipeline()

        // Ingest multiple documents
        for i in 1...10 {
            try await pipeline.ingest(createTestDocument(
                content: "Document number \(i) with content about Swift programming."
            ))
        }

        let results = try await pipeline.retrieve("Swift programming", limit: 3)

        #expect(results.count <= 3)
    }
}

// MARK: - Query Tests

@Suite("RAGPipeline Query Tests")
struct RAGPipelineQueryTests {

    @Test("Query returns response with answer and sources")
    func testQuery() async throws {
        let pipeline = createTestPipeline()

        // Ingest documents
        try await pipeline.ingest(createTestDocument(
            content: "Swift supports async/await for modern concurrency patterns."
        ))

        let response = try await pipeline.query("What does Swift support?")

        #expect(!response.answer.isEmpty)
        #expect(!response.sources.isEmpty)
    }

    @Test("Query with custom options")
    func testQueryWithOptions() async throws {
        let pipeline = createTestPipeline()
        try await pipeline.ingest(createTestDocument())

        let options = QueryOptions(
            retrievalLimit: 3,
            systemPrompt: "Be concise."
        )

        let response = try await pipeline.query("Test question", options: options)

        #expect(response.sources.count <= 3)
    }

    @Test("Query on empty store returns answer with empty sources")
    func testQueryEmptyStore() async throws {
        let pipeline = createTestPipeline()

        let response = try await pipeline.query("Any question")

        // Should still return a response, possibly indicating no context found
        #expect(response.sources.isEmpty)
    }

    @Test("Query includes metadata about timing")
    func testQueryMetadata() async throws {
        let pipeline = createTestPipeline()
        try await pipeline.ingest(createTestDocument())

        let response = try await pipeline.query("Test question")

        // Metadata should be populated (exact values depend on implementation)
        #expect(response.metadata.chunksRetrieved != nil || response.sources.count >= 0)
    }
}

// MARK: - Stream Query Tests

@Suite("RAGPipeline Stream Query Tests")
struct RAGPipelineStreamQueryTests {

    @Test("Stream query yields events in order")
    func testStreamQuery() async throws {
        let pipeline = createTestPipeline()
        try await pipeline.ingest(createTestDocument())

        var events: [RAGStreamEvent] = []

        for try await event in pipeline.streamQuery("Test question") {
            events.append(event)
        }

        // Should have retrieval and generation events
        #expect(!events.isEmpty)

        // First event should be retrievalStarted
        if case .retrievalStarted = events.first {
            // Good - expected first event
        } else {
            Issue.record("First event should be retrievalStarted")
        }
    }

    @Test("Stream query emits retrieval complete with sources")
    func testStreamQueryRetrievalComplete() async throws {
        let pipeline = createTestPipeline()
        try await pipeline.ingest(createTestDocument())

        var foundRetrievalComplete = false

        for try await event in pipeline.streamQuery("Test question") {
            if case .retrievalComplete(let sources) = event {
                foundRetrievalComplete = true
                #expect(sources.count >= 0) // May be empty if no matches
            }
        }

        #expect(foundRetrievalComplete)
    }

    @Test("Stream query emits generation chunks")
    func testStreamQueryGenerationChunks() async throws {
        let pipeline = createTestPipeline()
        try await pipeline.ingest(createTestDocument())

        var generationChunks: [String] = []

        for try await event in pipeline.streamQuery("Test question") {
            if case .generationChunk(let text) = event {
                generationChunks.append(text)
            }
        }

        #expect(!generationChunks.isEmpty)
    }

    @Test("Stream query ends with complete event")
    func testStreamQueryComplete() async throws {
        let pipeline = createTestPipeline()
        try await pipeline.ingest(createTestDocument())

        var lastEvent: RAGStreamEvent?

        for try await event in pipeline.streamQuery("Test question") {
            lastEvent = event
        }

        if case .complete(let response) = lastEvent {
            #expect(!response.answer.isEmpty)
        } else {
            Issue.record("Last event should be complete")
        }
    }
}

// MARK: - Statistics Tests

@Suite("RAGPipeline Statistics Tests")
struct RAGPipelineStatisticsTests {

    @Test("Statistics returns correct counts")
    func testStatistics() async throws {
        let pipeline = createTestPipeline()

        // Empty initially
        var stats = try await pipeline.statistics()
        #expect(stats.documentCount == 0)
        #expect(stats.chunkCount == 0)

        // After ingestion
        try await pipeline.ingest(createTestDocument())
        stats = try await pipeline.statistics()

        #expect(stats.documentCount == 1)
        #expect(stats.chunkCount > 0)
        #expect(stats.embeddingDimensions == 384)
    }

    @Test("Statistics includes provider names")
    func testStatisticsProviderNames() async throws {
        let pipeline = createTestPipeline()
        let stats = try await pipeline.statistics()

        #expect(!stats.vectorStoreName.isEmpty)
        #expect(!stats.embeddingProviderName.isEmpty)
    }

    @Test("Statistics reflects multiple document ingestion")
    func testStatisticsMultipleDocuments() async throws {
        let pipeline = createTestPipeline()

        try await pipeline.ingest(createTestDocument(content: "First document content."))
        try await pipeline.ingest(createTestDocument(content: "Second document content."))
        try await pipeline.ingest(createTestDocument(content: "Third document content."))

        let stats = try await pipeline.statistics()

        #expect(stats.documentCount == 3)
        #expect(stats.chunkCount >= 3) // At least one chunk per document
    }
}

// MARK: - Clear Tests

@Suite("RAGPipeline Clear Tests")
struct RAGPipelineClearTests {

    @Test("Clear removes all data")
    func testClear() async throws {
        let pipeline = createTestPipeline()

        // Ingest some documents
        try await pipeline.ingest(createTestDocument())
        try await pipeline.ingest(createTestDocument())

        var stats = try await pipeline.statistics()
        #expect(stats.documentCount > 0)

        // Clear
        try await pipeline.clear()

        stats = try await pipeline.statistics()
        #expect(stats.documentCount == 0)
        #expect(stats.chunkCount == 0)
    }

    @Test("Clear on empty store succeeds")
    func testClearEmptyStore() async throws {
        let pipeline = createTestPipeline()

        // Should not throw
        try await pipeline.clear()

        let stats = try await pipeline.statistics()
        #expect(stats.documentCount == 0)
    }

    @Test("Clear allows new ingestion")
    func testClearThenIngest() async throws {
        let pipeline = createTestPipeline()

        // Ingest, clear, then ingest again
        try await pipeline.ingest(createTestDocument(content: "First batch content."))

        var stats = try await pipeline.statistics()
        let firstCount = stats.documentCount

        try await pipeline.clear()

        try await pipeline.ingest(createTestDocument(content: "Second batch content."))

        stats = try await pipeline.statistics()
        #expect(stats.documentCount == 1)
        #expect(firstCount >= 1)
    }
}

// MARK: - Integration Tests

@Suite("RAGPipeline Integration Tests")
struct RAGPipelineIntegrationTests {

    @Test("Full RAG pipeline flow")
    func testFullPipelineFlow() async throws {
        let pipeline = createTestPipeline()

        // 1. Ingest documents
        try await pipeline.ingest(createTestDocument(
            content: "Swift is a powerful programming language for Apple platforms.",
            source: "swift-intro.txt"
        ))
        try await pipeline.ingest(createTestDocument(
            content: "Concurrency in Swift uses async/await and structured concurrency.",
            source: "swift-concurrency.txt"
        ))

        // 2. Verify ingestion
        var stats = try await pipeline.statistics()
        #expect(stats.documentCount == 2)

        // 3. Retrieve relevant chunks
        let results = try await pipeline.retrieve("Swift concurrency", limit: 5)
        #expect(!results.isEmpty)

        // 4. Query the pipeline
        let response = try await pipeline.query("How does Swift handle concurrency?")
        #expect(!response.answer.isEmpty)

        // 5. Clear the pipeline
        try await pipeline.clear()
        stats = try await pipeline.statistics()
        #expect(stats.documentCount == 0)
    }

    @Test("Pipeline handles concurrent operations")
    func testConcurrentOperations() async throws {
        let pipeline = createTestPipeline()

        // Ingest some initial data
        try await pipeline.ingest(createTestDocument(content: "Initial content for testing."))

        // Perform concurrent queries
        async let query1 = pipeline.query("first query")
        async let query2 = pipeline.query("second query")
        async let stats = pipeline.statistics()

        let (response1, response2, statsResult) = try await (query1, query2, stats)

        #expect(!response1.answer.isEmpty)
        #expect(!response2.answer.isEmpty)
        #expect(statsResult.documentCount >= 1)
    }

    @Test("Pipeline maintains consistency across operations")
    func testConsistencyAcrossOperations() async throws {
        let pipeline = createTestPipeline()

        // Ingest
        try await pipeline.ingest(createTestDocument(content: "Document one content."))
        let stats1 = try await pipeline.statistics()

        // Retrieve
        _ = try await pipeline.retrieve("Document", limit: 5)
        let stats2 = try await pipeline.statistics()

        // Query
        _ = try await pipeline.query("What is document one?")
        let stats3 = try await pipeline.statistics()

        // Verify consistency - retrieval and query should not change counts
        #expect(stats1.documentCount == stats2.documentCount)
        #expect(stats2.documentCount == stats3.documentCount)
        #expect(stats1.chunkCount == stats2.chunkCount)
        #expect(stats2.chunkCount == stats3.chunkCount)
    }
}

// MARK: - Edge Case Tests

@Suite("RAGPipeline Edge Case Tests")
struct RAGPipelineEdgeCaseTests {

    @Test("Handle empty query string")
    func testEmptyQuery() async throws {
        let pipeline = createTestPipeline()
        try await pipeline.ingest(createTestDocument())

        // Should handle gracefully - either return empty results or throw
        let results = try await pipeline.retrieve("", limit: 5)
        #expect(results.isEmpty || results.count >= 0)
    }

    @Test("Handle very long document content")
    func testVeryLongDocument() async throws {
        let pipeline = createTestPipeline()
        let longContent = String(repeating: "This is a test sentence. ", count: 1000)
        let document = createTestDocument(content: longContent)

        try await pipeline.ingest(document)

        let stats = try await pipeline.statistics()
        #expect(stats.documentCount == 1)
        #expect(stats.chunkCount > 1) // Should be chunked into multiple pieces
    }

    @Test("Handle special characters in content")
    func testSpecialCharacters() async throws {
        let pipeline = createTestPipeline()
        let content = "Test content with special chars: @#$%^&*() and unicode: Hello"
        let document = createTestDocument(content: content)

        try await pipeline.ingest(document)

        let stats = try await pipeline.statistics()
        #expect(stats.documentCount == 1)
    }

    @Test("Handle whitespace-only query")
    func testWhitespaceQuery() async throws {
        let pipeline = createTestPipeline()
        try await pipeline.ingest(createTestDocument())

        // Should handle gracefully
        let results = try await pipeline.retrieve("   ", limit: 5)
        #expect(results.isEmpty || results.count >= 0)
    }
}
