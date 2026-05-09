// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// EmbeddingProvider.swift - Protocol for generating vector embeddings from text

// MARK: - EmbeddingProvider Protocol

/// A protocol for generating vector embeddings from text.
///
/// Implement this protocol to integrate with embedding providers
/// like OpenAI, Cohere, local models, or Apple's NaturalLanguage.
///
/// Conforming types must be `Sendable` to ensure thread-safety when used
/// in concurrent contexts across the RAG pipeline.
///
/// ## Example Implementation
/// ```swift
/// struct OpenAIEmbeddingProvider: EmbeddingProvider {
///     let name = "openai"
///     let dimensions = 1536
///     let maxTokensPerRequest = 8191
///
///     func embed(_ text: String) async throws -> Embedding {
///         // Call OpenAI API to generate embedding
///         let vector = try await callOpenAI(text: text)
///         return Embedding(vector: vector, model: "text-embedding-3-small")
///     }
///
///     func embed(_ texts: [String]) async throws -> [Embedding] {
///         // Batch call to OpenAI API
///         let vectors = try await callOpenAI(texts: texts)
///         return vectors.map { Embedding(vector: $0, model: "text-embedding-3-small") }
///     }
/// }
/// ```
///
/// ## Thread Safety
/// All implementations must be `Sendable` and safe to use from any actor context.
/// The embedding methods are `async` to support both local and remote providers.
public protocol EmbeddingProvider: Sendable {

    /// The name of the embedding provider.
    ///
    /// This identifier is used for logging, debugging, and configuration purposes.
    /// Examples: "openai", "cohere", "local", "apple-nl".
    var name: String { get }

    /// The number of dimensions in the embeddings produced by this provider.
    ///
    /// This value must match the vector store configuration when storing embeddings.
    /// Common values:
    /// - OpenAI text-embedding-3-small: 1536
    /// - OpenAI text-embedding-3-large: 3072
    /// - Cohere embed-english-v3.0: 1024
    var dimensions: Int { get }

    /// The maximum number of tokens that can be processed in a single request.
    ///
    /// Texts exceeding this limit may need to be truncated or split.
    /// This is typically defined by the embedding model's context window.
    var maxTokensPerRequest: Int { get }

    /// The optimal batch size for this provider.
    ///
    /// This value represents the recommended number of texts to include in a
    /// single batch request for optimal throughput and cost efficiency.
    /// The default implementation returns 100.
    var optimalBatchSize: Int { get }

    /// Generates an embedding for a single text.
    ///
    /// This method converts input text into a high-dimensional vector representation
    /// that captures semantic meaning. The resulting embedding can be used for
    /// similarity search, clustering, and other vector operations.
    ///
    /// - Parameter text: The text to embed. Should not exceed `maxTokensPerRequest`.
    /// - Returns: The embedding vector representing the semantic content of the text.
    /// - Throws: `ZoniError.embeddingFailed` if the embedding generation fails,
    ///   or `ZoniError.rateLimited` if the provider's rate limit is exceeded.
    func embed(_ text: String) async throws -> Embedding

    /// Generates embeddings for multiple texts in a batch.
    ///
    /// Batch embedding is more efficient than calling `embed(_:)` repeatedly,
    /// as it reduces network overhead and may benefit from provider-side
    /// optimizations. The returned embeddings are in the same order as the
    /// input texts.
    ///
    /// - Parameter texts: The texts to embed. For optimal performance, the count
    ///   should not exceed `optimalBatchSize`. Each text should not exceed
    ///   `maxTokensPerRequest`.
    /// - Returns: An array of embeddings in the same order as the input texts.
    /// - Throws: `ZoniError.embeddingFailed` if embedding generation fails,
    ///   or `ZoniError.rateLimited` if the provider's rate limit is exceeded.
    func embed(_ texts: [String]) async throws -> [Embedding]
}

// MARK: - Default Implementations

extension EmbeddingProvider {

    /// Default optimal batch size.
    ///
    /// Returns 100 as a reasonable default for most providers.
    /// Override this property if your provider has different optimal batch sizes.
    public var optimalBatchSize: Int { 100 }
}
