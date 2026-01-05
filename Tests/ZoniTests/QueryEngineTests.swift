// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// QueryEngineTests.swift - Tests for QueryEngine, ContextBuilder, and CompactSynthesizer

import Testing
import Foundation
@testable import Zoni

// MARK: - Test Helpers

private func makeChunk(
    id: String,
    content: String,
    documentId: String = "doc-1",
    index: Int = 0,
    source: String? = nil
) -> Chunk {
    Chunk(
        id: id,
        content: content,
        metadata: ChunkMetadata(
            documentId: documentId,
            index: index,
            startOffset: 0,
            endOffset: content.count,
            source: source,
            custom: [:]
        )
    )
}

private func makeResult(chunk: Chunk, score: Float) -> RetrievalResult {
    RetrievalResult(chunk: chunk, score: score)
}

// MARK: - Mock Implementations

/// A mock LLM provider for testing query engine operations.
actor QueryEngineMockLLMProvider: LLMProvider {
    nonisolated var name: String { "mock" }
    nonisolated var model: String { "mock-model" }
    nonisolated var maxContextTokens: Int { 4096 }

    var response: String = "Mock response"
    var streamChunks: [String] = ["Mock ", "response"]

    func generate(
        prompt: String,
        systemPrompt: String?,
        options: LLMOptions
    ) async throws -> String {
        response
    }

    nonisolated func stream(
        prompt: String,
        systemPrompt: String?,
        options: LLMOptions
    ) -> AsyncThrowingStream<String, Error> {
        // Capture the chunks for use in the stream
        AsyncThrowingStream { continuation in
            Task {
                let chunks = await self.streamChunks
                for chunk in chunks {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    func setResponse(_ newResponse: String) {
        response = newResponse
    }

    func setStreamChunks(_ chunks: [String]) {
        streamChunks = chunks
    }
}

/// A mock retriever for testing query engine operations.
struct QueryEngineMockRetriever: Retriever {
    var name: String { "mock" }
    var results: [RetrievalResult] = []

    func retrieve(
        query: String,
        limit: Int,
        filter: MetadataFilter?
    ) async throws -> [RetrievalResult] {
        Array(results.prefix(limit))
    }
}

/// A mock query transformer for testing query transformation.
struct MockTransformer: QueryTransformer {
    var transformedQuery: String

    func transform(_ query: String) async throws -> String {
        transformedQuery
    }
}

// MARK: - QueryEngine Tests

@Suite("QueryEngine Tests")
struct QueryEngineTests {

    @Test("Query returns response with sources")
    func testQueryReturnsResponseWithSources() async throws {
        let llmProvider = QueryEngineMockLLMProvider()
        await llmProvider.setResponse("This is the answer based on the context.")

        let chunk1 = makeChunk(id: "1", content: "First chunk content", source: "doc1.txt")
        let chunk2 = makeChunk(id: "2", content: "Second chunk content", source: "doc2.txt")
        let retriever = QueryEngineMockRetriever(results: [
            makeResult(chunk: chunk1, score: 0.95),
            makeResult(chunk: chunk2, score: 0.85)
        ])

        let engine = QueryEngine(retriever: retriever, llmProvider: llmProvider)
        let response = try await engine.query("What is the answer?")

        #expect(response.answer == "This is the answer based on the context.")
        #expect(response.sources.count == 2)
        #expect(response.sources[0].chunk.id == "1")
        #expect(response.sources[1].chunk.id == "2")
    }

    @Test("Query with empty results returns graceful message")
    func testQueryWithEmptyResultsReturnsGracefulMessage() async throws {
        let llmProvider = QueryEngineMockLLMProvider()
        let retriever = QueryEngineMockRetriever(results: [])

        let engine = QueryEngine(retriever: retriever, llmProvider: llmProvider)
        let response = try await engine.query("What is something unknown?")

        #expect(response.answer.contains("could not find any relevant information"))
        #expect(response.sources.isEmpty)
        #expect(response.metadata.chunksRetrieved == 0)
    }

    @Test("Query timing metadata is populated")
    func testQueryTimingMetadataPopulated() async throws {
        let llmProvider = QueryEngineMockLLMProvider()
        await llmProvider.setResponse("Answer")

        let chunk = makeChunk(id: "1", content: "Content")
        let retriever = QueryEngineMockRetriever(results: [makeResult(chunk: chunk, score: 0.9)])

        let engine = QueryEngine(retriever: retriever, llmProvider: llmProvider)
        let response = try await engine.query("Question?")

        #expect(response.metadata.retrievalTime != nil)
        #expect(response.metadata.generationTime != nil)
        #expect(response.metadata.totalTime != nil)
        #expect(response.metadata.model == "mock-model")
        #expect(response.metadata.chunksRetrieved == 1)
    }

    @Test("Query with transformer applies transformation")
    func testQueryWithTransformerAppliesTransformation() async throws {
        let llmProvider = QueryEngineMockLLMProvider()
        await llmProvider.setResponse("Transformed answer")

        let chunk = makeChunk(id: "1", content: "Relevant content")
        let retriever = QueryEngineMockRetriever(results: [makeResult(chunk: chunk, score: 0.9)])

        let engine = QueryEngine(retriever: retriever, llmProvider: llmProvider)
        let transformer = MockTransformer(transformedQuery: "transformed query text")
        await engine.setQueryTransformer(transformer)

        let response = try await engine.query("original query")

        // The transformer should have been called (we verify the engine works with transformer)
        #expect(response.answer == "Transformed answer")
    }

    @Test("Streaming events order is correct")
    func testStreamingEventsOrder() async throws {
        let llmProvider = QueryEngineMockLLMProvider()
        await llmProvider.setStreamChunks(["Hello ", "world", "!"])

        let chunk = makeChunk(id: "1", content: "Test content")
        let retriever = QueryEngineMockRetriever(results: [makeResult(chunk: chunk, score: 0.9)])

        let engine = QueryEngine(retriever: retriever, llmProvider: llmProvider)

        var events: [String] = []
        var generationChunks: [String] = []

        for try await event in engine.streamQuery("Test question") {
            switch event {
            case .retrievalStarted:
                events.append("retrievalStarted")
            case .retrievalComplete(let results):
                events.append("retrievalComplete(\(results.count))")
            case .generationStarted:
                events.append("generationStarted")
            case .generationChunk(let chunk):
                generationChunks.append(chunk)
            case .generationComplete(let answer):
                events.append("generationComplete")
                #expect(answer == "Hello world!")
            case .complete(let response):
                events.append("complete")
                #expect(response.sources.count == 1)
            case .error:
                events.append("error")
            }
        }

        // Verify event order
        #expect(events[0] == "retrievalStarted")
        #expect(events[1] == "retrievalComplete(1)")
        #expect(events[2] == "generationStarted")
        #expect(events[3] == "generationComplete")
        #expect(events[4] == "complete")

        // Verify generation chunks
        #expect(generationChunks == ["Hello ", "world", "!"])
    }
}

// MARK: - ContextBuilder Tests

@Suite("ContextBuilder Tests")
struct ContextBuilderTests {

    @Test("Build includes source numbers")
    func testBuildIncludesSourceNumbers() async throws {
        let builder = ContextBuilder(includeMetadata: true)

        let chunk1 = makeChunk(id: "1", content: "First content", source: "source1.txt")
        let chunk2 = makeChunk(id: "2", content: "Second content", source: "source2.txt")

        let results = [
            makeResult(chunk: chunk1, score: 0.9),
            makeResult(chunk: chunk2, score: 0.8)
        ]

        let context = builder.build(
            query: "test query",
            results: results,
            maxTokens: 1000
        )

        #expect(context.contains("[Source 1]"))
        #expect(context.contains("[Source 2]"))
        #expect(context.contains("First content"))
        #expect(context.contains("Second content"))
    }

    @Test("Build respects max tokens")
    func testBuildRespectsMaxTokens() async throws {
        let builder = ContextBuilder(includeMetadata: true)

        // Create chunks with substantial content
        let chunk1 = makeChunk(id: "1", content: String(repeating: "word ", count: 100), source: "source1.txt")
        let chunk2 = makeChunk(id: "2", content: String(repeating: "text ", count: 100), source: "source2.txt")
        let chunk3 = makeChunk(id: "3", content: String(repeating: "more ", count: 100), source: "source3.txt")

        let results = [
            makeResult(chunk: chunk1, score: 0.9),
            makeResult(chunk: chunk2, score: 0.8),
            makeResult(chunk: chunk3, score: 0.7)
        ]

        // Use a very small token limit to force truncation
        let context = builder.build(
            query: "test query",
            results: results,
            maxTokens: 50  // Very small limit
        )

        // Should not include all three sources due to token limit
        let sourceCount = context.components(separatedBy: "[Source").count - 1
        #expect(sourceCount < 3)
    }

    @Test("Build structured returns context chunks")
    func testBuildStructuredReturnsContextChunks() async throws {
        let builder = ContextBuilder()

        let chunk1 = makeChunk(id: "1", content: "Content one", source: "file1.txt")
        let chunk2 = makeChunk(id: "2", content: "Content two", source: "file2.txt")

        let results = [
            makeResult(chunk: chunk1, score: 0.95),
            makeResult(chunk: chunk2, score: 0.85)
        ]

        let contextChunks = builder.buildStructured(query: "query", results: results)

        #expect(contextChunks.count == 2)
        #expect(contextChunks[0].index == 1)
        #expect(contextChunks[0].content == "Content one")
        #expect(contextChunks[0].source == "file1.txt")
        #expect(contextChunks[0].score == 0.95)
        #expect(contextChunks[1].index == 2)
        #expect(contextChunks[1].content == "Content two")
        #expect(contextChunks[1].source == "file2.txt")
        #expect(contextChunks[1].score == 0.85)
    }
}

// MARK: - CompactSynthesizer Tests

@Suite("CompactSynthesizer Tests")
struct CompactSynthesizerTests {

    @Test("Synthesize generates response")
    func testSynthesizeGeneratesResponse() async throws {
        let llmProvider = QueryEngineMockLLMProvider()
        await llmProvider.setResponse("Generated answer based on context")

        let synthesizer = CompactSynthesizer(llmProvider: llmProvider)

        let chunk = makeChunk(id: "1", content: "Context information")
        let results = [makeResult(chunk: chunk, score: 0.9)]

        let response = try await synthesizer.synthesize(
            query: "What is the answer?",
            context: "Context information",
            results: results,
            options: .default
        )

        #expect(response == "Generated answer based on context")
    }

    @Test("Stream synthesize yields chunks")
    func testStreamSynthesizeYieldsChunks() async throws {
        let llmProvider = QueryEngineMockLLMProvider()
        await llmProvider.setStreamChunks(["Part ", "one", " part ", "two"])

        let synthesizer = CompactSynthesizer(llmProvider: llmProvider)

        let chunk = makeChunk(id: "1", content: "Context")
        let results = [makeResult(chunk: chunk, score: 0.9)]

        var chunks: [String] = []
        for try await chunk in synthesizer.streamSynthesize(
            query: "question",
            context: "context",
            results: results,
            options: .default
        ) {
            chunks.append(chunk)
        }

        #expect(chunks == ["Part ", "one", " part ", "two"])
        #expect(chunks.joined() == "Part one part two")
    }
}

// MARK: - QueryEngine Error Handling Tests

@Suite("QueryEngine Error Handling Tests")
struct QueryEngineErrorHandlingTests {

    @Test("Query throws for empty query")
    func testQueryThrowsForEmptyQuery() async throws {
        let llmProvider = QueryEngineMockLLMProvider()
        let retriever = QueryEngineMockRetriever(results: [])

        let engine = QueryEngine(retriever: retriever, llmProvider: llmProvider)

        do {
            _ = try await engine.query("")
            Issue.record("Expected error for empty query")
        } catch let error as ZoniError {
            #expect(error.localizedDescription.contains("empty"))
        }
    }

    @Test("Query throws for whitespace-only query")
    func testQueryThrowsForWhitespaceOnlyQuery() async throws {
        let llmProvider = QueryEngineMockLLMProvider()
        let retriever = QueryEngineMockRetriever(results: [])

        let engine = QueryEngine(retriever: retriever, llmProvider: llmProvider)

        do {
            _ = try await engine.query("   \n\t  ")
            Issue.record("Expected error for whitespace-only query")
        } catch let error as ZoniError {
            #expect(error.localizedDescription.contains("empty"))
        }
    }

    @Test("Query throws for invalid retrieval limit")
    func testQueryThrowsForInvalidRetrievalLimit() async throws {
        let llmProvider = QueryEngineMockLLMProvider()
        let retriever = QueryEngineMockRetriever(results: [])

        let engine = QueryEngine(retriever: retriever, llmProvider: llmProvider)
        let options = QueryOptions(retrievalLimit: 0)

        do {
            _ = try await engine.query("test", options: options)
            Issue.record("Expected error for zero retrieval limit")
        } catch let error as ZoniError {
            #expect(error.localizedDescription.contains("greater than zero"))
        }
    }

    @Test("Query throws for excessive retrieval limit")
    func testQueryThrowsForExcessiveRetrievalLimit() async throws {
        let llmProvider = QueryEngineMockLLMProvider()
        let retriever = QueryEngineMockRetriever(results: [])

        let engine = QueryEngine(retriever: retriever, llmProvider: llmProvider)
        let options = QueryOptions(retrievalLimit: 10000)

        do {
            _ = try await engine.query("test", options: options)
            Issue.record("Expected error for excessive retrieval limit")
        } catch let error as ZoniError {
            #expect(error.localizedDescription.contains("exceeds maximum"))
        }
    }

    @Test("Retrieve throws for empty query")
    func testRetrieveThrowsForEmptyQuery() async throws {
        let llmProvider = QueryEngineMockLLMProvider()
        let retriever = QueryEngineMockRetriever(results: [])

        let engine = QueryEngine(retriever: retriever, llmProvider: llmProvider)

        do {
            _ = try await engine.retrieve("")
            Issue.record("Expected error for empty query")
        } catch let error as ZoniError {
            #expect(error.localizedDescription.contains("empty"))
        }
    }

    @Test("Retrieve throws for invalid limit")
    func testRetrieveThrowsForInvalidLimit() async throws {
        let llmProvider = QueryEngineMockLLMProvider()
        let retriever = QueryEngineMockRetriever(results: [])

        let engine = QueryEngine(retriever: retriever, llmProvider: llmProvider)

        do {
            _ = try await engine.retrieve("test", limit: -1)
            Issue.record("Expected error for negative limit")
        } catch let error as ZoniError {
            #expect(error.localizedDescription.contains("greater than zero"))
        }
    }
}

// MARK: - ContextBuilder Edge Case Tests

@Suite("ContextBuilder Edge Case Tests")
struct ContextBuilderEdgeCaseTests {

    @Test("Build handles empty results")
    func testBuildHandlesEmptyResults() async throws {
        let builder = ContextBuilder()
        let context = builder.build(
            query: "test",
            results: [],
            maxTokens: 1000
        )

        #expect(context.isEmpty)
    }

    @Test("Build handles missing source metadata")
    func testBuildHandlesMissingSource() async throws {
        let builder = ContextBuilder(includeMetadata: true)

        let chunk = makeChunk(id: "1", content: "Content", source: nil)
        let results = [makeResult(chunk: chunk, score: 0.9)]

        let context = builder.build(
            query: "test",
            results: results,
            maxTokens: 1000
        )

        #expect(context.contains("[Source 1]"))
        #expect(context.contains("Content"))
    }

    @Test("Build includes scores when configured")
    func testBuildIncludesScores() async throws {
        let builder = ContextBuilder(includeMetadata: true, includeScores: true)

        let chunk = makeChunk(id: "1", content: "Content", source: "test.txt")
        let results = [makeResult(chunk: chunk, score: 0.8523)]

        let context = builder.build(
            query: "test",
            results: results,
            maxTokens: 1000
        )

        // Should include score in the output
        #expect(context.contains("0.85"))
    }

    @Test("Build handles single result")
    func testBuildHandlesSingleResult() async throws {
        let builder = ContextBuilder()

        let chunk = makeChunk(id: "1", content: "Single chunk content", source: "single.txt")
        let results = [makeResult(chunk: chunk, score: 0.95)]

        let context = builder.build(
            query: "test",
            results: results,
            maxTokens: 1000
        )

        #expect(context.contains("[Source 1]"))
        #expect(context.contains("Single chunk content"))
        // Should not have separator since only one chunk
        #expect(!context.contains("---") || context.components(separatedBy: "---").count <= 2)
    }
}

// MARK: - RAGPrompts Tests

@Suite("RAGPrompts Tests")
struct RAGPromptsTests {

    @Test("Compact template contains required placeholders")
    func testCompactTemplateStructure() throws {
        let template = RAGPrompts.compactTemplate

        #expect(template.contains(RAGPrompts.contextPlaceholder))
        #expect(template.contains(RAGPrompts.queryPlaceholder))
        #expect(template.contains("Context"))
        #expect(template.contains("Answer"))
    }

    @Test("Refine iterative template contains all placeholders")
    func testRefineIterativeTemplateStructure() throws {
        let template = RAGPrompts.refineIterativeTemplate

        #expect(template.contains(RAGPrompts.contextPlaceholder))
        #expect(template.contains(RAGPrompts.queryPlaceholder))
        #expect(template.contains(RAGPrompts.existingAnswerPlaceholder))
        #expect(template.contains("refine"))
    }

    @Test("Template validation succeeds for valid templates")
    func testTemplateValidationSucceeds() throws {
        try RAGPrompts.validateCompactTemplate()
        try RAGPrompts.validateRefineInitialTemplate()
        try RAGPrompts.validateRefineIterativeTemplate()
        try RAGPrompts.validateTreeSummarizeTemplate()
    }

    @Test("Template validation fails for missing placeholders")
    func testTemplateValidationFails() throws {
        let invalidTemplate = "Just a template without placeholders"

        do {
            try RAGPrompts.validateTemplate(
                invalidTemplate,
                requiredPlaceholders: [RAGPrompts.contextPlaceholder]
            )
            Issue.record("Expected validation to fail")
        } catch let error as ZoniError {
            #expect(error.localizedDescription.contains("missing"))
        }
    }

    @Test("Placeholder replacement works correctly")
    func testPlaceholderReplacement() throws {
        let template = RAGPrompts.compactTemplate

        let filled = template
            .replacingOccurrences(of: RAGPrompts.contextPlaceholder, with: "Test context")
            .replacingOccurrences(of: RAGPrompts.queryPlaceholder, with: "Test query")

        #expect(!filled.contains("{context}"))
        #expect(!filled.contains("{query}"))
        #expect(filled.contains("Test context"))
        #expect(filled.contains("Test query"))
    }

    @Test("Default system prompt includes citation guidance")
    func testDefaultSystemPromptContent() throws {
        let prompt = RAGPrompts.defaultSystemPrompt

        #expect(prompt.contains("context"))
        #expect(prompt.contains("Source"))
        #expect(prompt.lowercased().contains("do not") || prompt.lowercased().contains("don't"))
    }
}

// MARK: - QueryOptions Tests

@Suite("QueryOptions Tests")
struct QueryOptionsTests {

    @Test("Default options have valid values")
    func testDefaultOptions() {
        let options = QueryOptions.default

        #expect(options.retrievalLimit > 0)
        #expect(options.maxContextTokens > 0)
    }

    @Test("Custom options are preserved")
    func testCustomOptions() {
        let options = QueryOptions(
            retrievalLimit: 20,
            systemPrompt: "Custom prompt",
            temperature: 0.5,
            maxContextTokens: 2000
        )

        #expect(options.retrievalLimit == 20)
        #expect(options.maxContextTokens == 2000)
        #expect(options.temperature == 0.5)
        #expect(options.systemPrompt == "Custom prompt")
    }
}
