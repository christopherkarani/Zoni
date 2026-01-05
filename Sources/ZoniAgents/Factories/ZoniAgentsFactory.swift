// ZoniAgents - SwiftAgents Integration for Zoni RAG Framework
//
// ZoniAgentsFactory.swift - Main factory for creating agent-ready Zoni components.

import Zoni

// MARK: - ZoniAgents Factory

/// Main factory for creating agent-ready Zoni components.
///
/// `ZoniAgents` provides convenient factory methods for wrapping Zoni components
/// to use with SwiftAgents. Use these methods to quickly set up RAG-enabled agents.
///
/// ## Quick Start
///
/// ```swift
/// import Zoni
/// import ZoniAgents
///
/// // Create embedding adapter
/// let embedder = ZoniAgents.embeddingProvider(OpenAIEmbedding(apiKey: "..."))
///
/// // Create memory backend
/// let memory = ZoniAgents.memoryBackend(vectorStore: InMemoryVectorStore())
///
/// // Get RAG tools
/// let tools = RAGToolBundle.searchOnly(retriever: vectorRetriever)
/// ```
///
/// ## Type Safety
///
/// Factory methods use generics to preserve concrete type information while
/// conforming to the appropriate protocols. This ensures Swift 6 strict
/// concurrency compliance.
public enum ZoniAgents {

    // MARK: - Embedding Provider Adapters

    /// Wraps a Zoni embedding provider for use with SwiftAgents.
    ///
    /// - Parameter provider: Any Zoni embedding provider.
    /// - Returns: An adapter conforming to `AgentsEmbeddingProvider`.
    ///
    /// ```swift
    /// let openai = OpenAIEmbedding(apiKey: "sk-...")
    /// let adapter = ZoniAgents.embeddingProvider(openai)
    ///
    /// let vector = try await adapter.embed("Hello world")
    /// ```
    public static func embeddingProvider<P: EmbeddingProvider>(
        _ provider: P
    ) -> ZoniEmbeddingAdapter<P> {
        ZoniEmbeddingAdapter(provider)
    }

    // MARK: - Vector Memory Backends

    /// Wraps a Zoni vector store for use as an agent memory backend.
    ///
    /// - Parameters:
    ///   - vectorStore: Any Zoni vector store.
    ///   - namespace: The namespace for isolating data. Default: "agent_memory".
    ///   - config: Configuration options. Default: `.default`.
    /// - Returns: An adapter conforming to `AgentsVectorMemoryBackend`.
    ///
    /// ```swift
    /// let store = InMemoryVectorStore()
    /// let memory = ZoniAgents.memoryBackend(vectorStore: store)
    ///
    /// try await memory.add(
    ///     id: "msg1",
    ///     content: "User asked about Swift",
    ///     embedding: vector,
    ///     metadata: ["role": "user"]
    /// )
    /// ```
    ///
    /// ## Namespace Isolation
    ///
    /// Each namespace is isolated using ID prefixing. This means:
    /// - Different namespaces can use the same logical IDs
    /// - Isolation persists across adapter restarts
    /// - Cross-namespace access is prevented at the storage level
    public static func memoryBackend<S: VectorStore>(
        vectorStore: S,
        namespace: String = "agent_memory",
        config: VectorStoreAdapterConfig = .default
    ) -> ZoniVectorStoreAdapter<S> {
        ZoniVectorStoreAdapter(
            vectorStore: vectorStore,
            namespace: namespace,
            config: config
        )
    }

    // MARK: - Retriever Adapters

    /// Wraps a Zoni retriever for simplified agent use.
    ///
    /// - Parameter retriever: Any Zoni retriever.
    /// - Returns: An adapter conforming to `AgentsRetriever`.
    ///
    /// ```swift
    /// let retriever = VectorRetriever(vectorStore: store, embeddingProvider: embedder)
    /// let adapter = ZoniAgents.retrieverAdapter(retriever)
    ///
    /// let results = try await adapter.retrieve(query: "How does async work?")
    /// ```
    public static func retrieverAdapter<R: Retriever>(
        _ retriever: R
    ) -> ZoniRetrieverAdapter<R> {
        ZoniRetrieverAdapter(retriever)
    }

    // MARK: - RAG Tools

    /// Returns a search tool configured with the given retriever.
    ///
    /// - Parameter retriever: The retriever to use for searches.
    /// - Returns: A configured RAGSearchTool.
    ///
    /// ```swift
    /// let tool = ZoniAgents.searchTool(retriever: vectorRetriever)
    /// // Add to agent's tool collection
    /// ```
    public static func searchTool(retriever: any Retriever) -> RAGSearchTool {
        RAGSearchTool(retriever: retriever)
    }
}
