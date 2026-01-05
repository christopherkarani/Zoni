// ZoniAgents - SwiftAgents Integration for Zoni RAG Framework
//
// ZoniAgents.swift - Module exports and documentation.

/// ZoniAgents provides seamless integration between Zoni RAG framework and SwiftAgents.
///
/// ## Overview
///
/// ZoniAgents is a bridge module that allows SwiftAgents to leverage Zoni's RAG capabilities:
///
/// - **Embedding Providers**: Use Zoni's embedding providers (OpenAI, Cohere, Ollama, etc.)
///   with SwiftAgents' vector memory
/// - **Vector Memory**: Use Zoni's vector stores as agent memory backends
/// - **RAG Tools**: Pre-configured tools for knowledge base search, querying, and ingestion
///
/// ## Architecture
///
/// ```
/// SwiftAgents Framework
///          ↓ imports
///     ZoniAgents (Bridge)
///          ↓ imports
///     Zoni RAG Framework
/// ```
///
/// ## Quick Start
///
/// ```swift
/// import Zoni
/// import ZoniAgents
///
/// // 1. Create Zoni components
/// let embedder = OpenAIEmbedding(apiKey: "sk-...")
/// let vectorStore = InMemoryVectorStore()
///
/// // 2. Wrap for SwiftAgents
/// let agentEmbedder = ZoniAgents.embeddingProvider(embedder)
/// let agentMemory = ZoniAgents.memoryBackend(vectorStore: vectorStore)
///
/// // 3. Use with SwiftAgents
/// let vector = try await agentEmbedder.embed("Hello world")
/// try await agentMemory.add(
///     id: "msg1",
///     content: "Important information",
///     embedding: vector,
///     metadata: ["source": "conversation"]
/// )
/// ```
///
/// ## Components
///
/// ### Protocols
///
/// - ``AgentsEmbeddingProvider``: Protocol for embedding providers in agent contexts
/// - ``AgentsVectorMemoryBackend``: Protocol for vector memory backends
/// - ``AgentTool``: Type alias confirming Zoni.Tool compatibility with SwiftAgents
///
/// ### Adapters
///
/// - ``ZoniEmbeddingAdapter``: Wraps Zoni embedding providers
/// - ``ZoniVectorStoreAdapter``: Wraps Zoni vector stores for agent memory
/// - ``ZoniRetrieverAdapter``: Wraps Zoni retrievers for simplified retrieval
///
/// ### Factories
///
/// - ``ZoniAgents``: Main factory for creating agent-ready components
/// - ``RAGToolBundle``: Pre-configured tool bundles for common use cases
///
/// ### Types
///
/// - ``AgentRetrievalResult``: Simplified retrieval result for agent use
/// - ``MemorySearchResult``: Result from vector memory searches
/// - ``AgentToolDefinition``: Serializable tool definition for prompts

// Re-export Zoni types commonly needed with ZoniAgents
@_exported import Zoni
