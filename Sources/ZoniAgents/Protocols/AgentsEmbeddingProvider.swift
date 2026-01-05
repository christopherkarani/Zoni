// ZoniAgents - SwiftAgents Integration for Zoni RAG Framework
//
// AgentsEmbeddingProvider.swift - Protocol for embedding providers in agent contexts.

import Zoni

// MARK: - AgentsEmbeddingProvider Protocol

/// A protocol for embedding providers that can be used by SwiftAgents.
///
/// This protocol defines the interface that SwiftAgents expects for generating
/// vector embeddings. Zoni provides an adapter (`ZoniEmbeddingAdapter`) that
/// wraps any `Zoni.EmbeddingProvider` to conform to this protocol.
///
/// ## Usage with SwiftAgents
///
/// ```swift
/// // Wrap a Zoni embedding provider for use with SwiftAgents
/// let zoniProvider = OpenAIEmbedding(apiKey: "...")
/// let agentsProvider = ZoniEmbeddingAdapter(zoniProvider)
///
/// // Use with SwiftAgents vector memory
/// let memory = VectorMemory(embeddingProvider: agentsProvider)
/// ```
///
/// ## Implementing Custom Providers
///
/// You can create custom providers that conform directly:
///
/// ```swift
/// struct CustomEmbedding: AgentsEmbeddingProvider {
///     let dimensions = 768
///     let modelIdentifier = "custom-model"
///
///     func embed(_ text: String) async throws -> [Float] {
///         // Your implementation
///     }
/// }
/// ```
///
/// ## Concurrency
///
/// Conforming types must be `Sendable` to ensure thread-safe usage across
/// actor boundaries in SwiftAgents applications.
///
/// ## Error Handling
///
/// Methods should throw `ZoniError` types for consistency:
/// - `ZoniError.embeddingFailed`: API failures, rate limits, network errors
/// - `ZoniError.invalidConfiguration`: Misconfiguration, invalid API keys
public protocol AgentsEmbeddingProvider: Sendable {

    /// The number of dimensions in the embeddings produced by this provider.
    ///
    /// This value is critical for ensuring compatibility with vector stores
    /// and memory backends. Common values:
    /// - OpenAI text-embedding-3-small: 1536
    /// - OpenAI text-embedding-3-large: 3072
    /// - Cohere embed-english-v3.0: 1024
    /// - Local models: 384-1024
    var dimensions: Int { get }

    /// An identifier for the embedding model being used.
    ///
    /// This is used for logging, debugging, and tracking which model
    /// generated specific embeddings. Examples: "openai", "cohere", "ollama".
    var modelIdentifier: String { get }

    /// Generates an embedding vector for a single text.
    ///
    /// - Parameter text: The text to embed. Empty strings are provider-dependent.
    /// - Returns: A vector of floating-point values representing the text's
    ///   semantic meaning. The array length must equal `dimensions`.
    ///
    /// - Throws:
    ///   - `ZoniError.embeddingFailed`: If the API request fails due to
    ///     network errors, authentication issues, or rate limits.
    ///   - `ZoniError.invalidConfiguration`: If the provider is misconfigured.
    func embed(_ text: String) async throws -> [Float]

    /// Generates embedding vectors for multiple texts in a batch.
    ///
    /// Batch embedding is more efficient than calling `embed(_:)` repeatedly,
    /// as it reduces network overhead and may benefit from provider-side
    /// optimizations.
    ///
    /// - Parameter texts: The texts to embed. Empty array returns empty result.
    /// - Returns: An array of vectors in the same order as the input texts.
    ///   Each vector's length must equal `dimensions`.
    ///
    /// - Throws:
    ///   - `ZoniError.embeddingFailed`: If the API request fails due to
    ///     network errors, authentication issues, rate limits, or batch size limits.
    ///   - `ZoniError.invalidConfiguration`: If the provider is misconfigured.
    func embed(_ texts: [String]) async throws -> [[Float]]
}

// MARK: - Default Implementations

extension AgentsEmbeddingProvider {

    /// Default batch implementation that embeds texts sequentially.
    ///
    /// Override this method if your provider supports native batch embedding
    /// for better performance.
    ///
    /// - Note: This implementation supports task cancellation between items.
    public func embed(_ texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }

        var results: [[Float]] = []
        results.reserveCapacity(texts.count)

        for text in texts {
            // Support cancellation between items
            try Task.checkCancellation()

            let vector = try await embed(text)
            results.append(vector)
        }
        return results
    }
}
