// ZoniAgents - SwiftAgents Integration for Zoni RAG Framework
//
// ZoniEmbeddingAdapter.swift - Adapter wrapping Zoni EmbeddingProvider for agents.

import Zoni

// MARK: - ZoniEmbeddingAdapter

/// Adapts a Zoni `EmbeddingProvider` to conform to `AgentsEmbeddingProvider`.
///
/// This adapter allows any Zoni embedding provider (OpenAI, Cohere, Ollama, etc.)
/// to be used with SwiftAgents' vector memory and other agent features.
///
/// ## Usage
///
/// ```swift
/// import Zoni
/// import ZoniAgents
///
/// // Wrap a Zoni embedding provider
/// let openai = OpenAIEmbedding(apiKey: "sk-...")
/// let adapter = ZoniEmbeddingAdapter(openai)
///
/// // Use with SwiftAgents
/// let vector = try await adapter.embed("Hello world")
/// print(vector.count) // 1536
/// ```
///
/// ## Thread Safety
///
/// This adapter is `Sendable` and can be safely used across actor boundaries.
/// The generic constraint on `Provider` ensures compile-time verification of
/// `Sendable` conformance for Swift 6 strict concurrency.
///
/// ## Error Handling
///
/// Methods throw specific `ZoniError` types:
/// - `ZoniError.embeddingFailed`: API request failures, rate limits
/// - `ZoniError.invalidConfiguration`: Invalid inputs
public struct ZoniEmbeddingAdapter<Provider: EmbeddingProvider>: AgentsEmbeddingProvider, Sendable {

    // MARK: - Properties

    /// The wrapped Zoni embedding provider.
    private let provider: Provider

    /// The number of dimensions in embeddings produced by this adapter.
    public var dimensions: Int {
        provider.dimensions
    }

    /// The model identifier for logging and debugging.
    ///
    /// This value comes from the wrapped provider's `name` property.
    public var modelIdentifier: String {
        provider.name
    }

    // MARK: - Initialization

    /// Creates a new adapter wrapping the given Zoni embedding provider.
    ///
    /// - Parameter provider: A Zoni embedding provider to wrap.
    public init(_ provider: Provider) {
        self.provider = provider
    }

    // MARK: - AgentsEmbeddingProvider

    /// Generates an embedding vector for a single text.
    ///
    /// - Parameter text: The text to embed. Can be empty (provider-dependent behavior).
    /// - Returns: A vector of floating-point values with `dimensions` elements.
    ///
    /// - Throws:
    ///   - `ZoniError.embeddingFailed`: If the provider's API request fails due to
    ///     network errors, authentication issues, rate limits, or invalid input.
    public func embed(_ text: String) async throws -> [Float] {
        let embedding = try await provider.embed(text)
        return embedding.vector
    }

    /// Generates embedding vectors for multiple texts.
    ///
    /// This method leverages Zoni's batch embedding for efficiency.
    ///
    /// - Parameter texts: The texts to embed. Empty array returns empty result.
    /// - Returns: An array of vectors in the same order as the input texts.
    ///
    /// - Throws:
    ///   - `ZoniError.embeddingFailed`: If the provider's API request fails due to
    ///     network errors, authentication issues, rate limits, or batch size limits.
    public func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        let embeddings = try await provider.embed(texts)
        return embeddings.map { $0.vector }
    }

    // MARK: - Public Utilities

    /// Access the underlying Zoni embedding provider.
    ///
    /// Use this to access provider-specific features not exposed through
    /// the `AgentsEmbeddingProvider` protocol, such as:
    /// - OpenAI-specific dimension customization
    /// - Provider-specific rate limit handling
    /// - Advanced configuration options
    ///
    /// ```swift
    /// let adapter = ZoniEmbeddingAdapter(openaiProvider)
    /// let provider = adapter.underlyingProvider
    /// // Access OpenAI-specific features...
    /// ```
    public var underlyingProvider: Provider {
        provider
    }
}
