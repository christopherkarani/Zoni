// ServerRAG - Vapor-based RAG Server Example
//
// configure.swift - Application configuration.
//
// Sets up the RAG pipeline with mock providers for demonstration purposes.
// In production, replace mock providers with real implementations.

import Vapor
import Zoni

// MARK: - Application Configuration

/// Configures the Vapor application with Zoni RAG services.
///
/// This function sets up:
/// - Mock embedding provider (no API key required)
/// - In-memory vector store (data resets on restart)
/// - Mock LLM provider (returns placeholder responses)
///
/// - Parameter app: The Vapor application to configure.
func configure(_ app: Application) async throws {
    // Create RAG pipeline components
    let embeddingProvider = MockEmbedding(dimensions: 384)
    let vectorStore = InMemoryVectorStore()
    let llmProvider = MockLLMProvider()

    // Create retriever
    let retriever = VectorRetriever(
        vectorStore: vectorStore,
        embeddingProvider: embeddingProvider
    )

    // Create query engine
    let queryEngine = QueryEngine(
        retriever: retriever,
        llmProvider: llmProvider
    )

    // Store components for direct access in routes.
    app.storage[QueryEngineKey.self] = queryEngine
    app.storage[VectorStoreKey.self] = vectorStore
    app.storage[EmbeddingProviderKey.self] = embeddingProvider
    app.storage[ChunkerKey.self] = ParagraphChunker()

    // Register routes
    try routes(app)

    app.logger.info("ServerRAG configured successfully")
    app.logger.info("API available at http://localhost:8080")
}

// MARK: - Storage Keys

/// Storage key for the query engine.
struct QueryEngineKey: StorageKey {
    typealias Value = QueryEngine
}

/// Storage key for the vector store.
struct VectorStoreKey: StorageKey {
    typealias Value = InMemoryVectorStore
}

/// Storage key for the embedding provider.
struct EmbeddingProviderKey: StorageKey {
    typealias Value = MockEmbedding
}

/// Storage key for the chunker.
struct ChunkerKey: StorageKey {
    typealias Value = ParagraphChunker
}

// MARK: - Application Extensions

extension Application {
    /// The query engine for answering RAG queries.
    var queryEngine: QueryEngine {
        guard let engine = storage[QueryEngineKey.self] else {
            fatalError("QueryEngine not configured")
        }
        return engine
    }

    /// The vector store for direct access in routes.
    var vectorStore: InMemoryVectorStore {
        guard let store = storage[VectorStoreKey.self] else {
            fatalError("VectorStore not configured")
        }
        return store
    }

    /// The embedding provider for direct access in routes.
    var embeddingProvider: MockEmbedding {
        guard let provider = storage[EmbeddingProviderKey.self] else {
            fatalError("EmbeddingProvider not configured")
        }
        return provider
    }

    /// The chunker for direct access in routes.
    var chunker: ParagraphChunker {
        guard let chunker = storage[ChunkerKey.self] else {
            fatalError("Chunker not configured")
        }
        return chunker
    }
}

// MARK: - Mock LLM Provider

/// A mock LLM provider that returns placeholder responses.
///
/// This provider generates responses based on the context provided,
/// making it useful for testing without API keys.
struct MockLLMProvider: LLMProvider, Sendable {
    let name = "mock"
    let model = "mock-llm-v1"
    let maxContextTokens = 4096

    func generate(
        prompt: String,
        systemPrompt: String?,
        options: LLMOptions
    ) async throws -> String {
        // Extract a brief summary from the prompt for a realistic response
        let contextPreview = prompt.prefix(200)
        return """
            Based on the provided context, here is my response:

            The documents contain information relevant to your query. \
            The retrieved content discusses topics found in your knowledge base.

            Context preview: "\(contextPreview)..."

            Note: This is a mock response. In production, configure a real LLM provider \
            (OpenAI, Anthropic, etc.) for actual text generation.
            """
    }

    func stream(
        prompt: String,
        systemPrompt: String?,
        options: LLMOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let response = try await self.generate(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    options: options
                )

                // Simulate streaming by yielding words
                let words = response.split(separator: " ")
                for word in words {
                    continuation.yield(String(word) + " ")
                    try await Task.sleep(for: .milliseconds(50))
                }

                continuation.finish()
            }
        }
    }
}
