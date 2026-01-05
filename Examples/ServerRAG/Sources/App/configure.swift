// ServerRAG - Vapor-based RAG Server Example
//
// configure.swift - Application configuration.
//
// Sets up the RAG pipeline with mock providers for demonstration purposes.
// In production, replace mock providers with real implementations.

import Vapor
import Zoni
import ZoniServer
import ZoniVapor

// MARK: - Application Configuration

/// Configures the Vapor application with Zoni RAG services.
///
/// This function sets up:
/// - Mock embedding provider (no API key required)
/// - In-memory vector store (data resets on restart)
/// - Mock LLM provider (returns placeholder responses)
/// - Basic tenant management (allows any API key)
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

    // Create mock tenant manager (accepts any API key)
    let tenantManager = TenantManager(
        storage: MockTenantStorage()
    )

    // Configure ZoniVapor
    let config = ZoniVaporConfiguration(
        queryEngine: queryEngine,
        tenantManager: tenantManager,
        rateLimiter: TenantRateLimiter(),
        jobQueue: InMemoryJobQueue()
    )

    app.configureZoni(config)

    // Store components for direct access in routes
    app.storage[VectorStoreKey.self] = vectorStore
    app.storage[EmbeddingProviderKey.self] = embeddingProvider
    app.storage[ChunkerKey.self] = ParagraphChunker()

    // Register routes
    try routes(app)

    app.logger.info("ServerRAG configured successfully")
    app.logger.info("API available at http://localhost:8080")
}

// MARK: - Storage Keys

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
actor MockLLMProvider: LLMProvider {
    nonisolated let name = "mock"
    nonisolated let model = "mock-llm-v1"
    nonisolated let maxContextTokens = 4096

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

// MARK: - Mock Tenant Storage

/// A mock tenant storage that creates tenants on-the-fly.
///
/// This storage accepts any API key and creates a default tenant,
/// useful for testing without a real database.
actor MockTenantStorage: TenantStorage {
    private var tenants: [String: TenantContext] = [:]
    private var apiKeyMappings: [String: String] = [:]

    func find(tenantId: String) async throws -> TenantContext? {
        if let existing = tenants[tenantId] {
            return existing
        }

        // Create a default tenant on first access
        let context = TenantContext(
            tenantId: tenantId,
            tier: .standard,
            config: TenantConfiguration.forTier(.standard)
        )
        tenants[tenantId] = context
        return context
    }

    func findByApiKey(_ apiKey: String) async throws -> TenantContext? {
        // Check if we have a mapping for this API key
        if let tenantId = apiKeyMappings[apiKey] {
            return try await find(tenantId: tenantId)
        }

        // Create a new tenant for any API key
        let tenantId = "tenant_\(apiKey.prefix(8))"
        apiKeyMappings[apiKey] = tenantId

        let context = TenantContext(
            tenantId: tenantId,
            tier: .standard,
            config: TenantConfiguration.forTier(.standard)
        )
        tenants[tenantId] = context
        return context
    }

    func save(_ tenant: TenantContext) async throws {
        tenants[tenant.tenantId] = tenant
    }

    func delete(tenantId: String) async throws {
        tenants.removeValue(forKey: tenantId)
        apiKeyMappings = apiKeyMappings.filter { $0.value != tenantId }
    }
}
