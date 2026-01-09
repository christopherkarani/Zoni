// Zoni - Retrieval-Augmented Generation Framework for Swift
//
// HuggingFaceEmbedding.swift - HuggingFace Inference API embedding integration

import Foundation

// MARK: - HuggingFaceEmbedding

/// An embedding provider using the HuggingFace Inference API.
///
/// `HuggingFaceEmbedding` integrates with HuggingFace's hosted inference endpoints
/// to generate embeddings using a wide variety of open-source models. It supports:
/// - Popular embedding models like MiniLM, BGE, E5, and Jina
/// - Batch embedding for efficient processing
/// - Custom model support for any compatible HuggingFace model
///
/// Example usage with predefined model:
/// ```swift
/// let huggingface = HuggingFaceEmbedding(
///     apiKey: "hf_...",
///     model: .miniLM
/// )
///
/// // Single embedding
/// let embedding = try await huggingface.embed("Hello world")
///
/// // Batch embedding (more efficient)
/// let embeddings = try await huggingface.embed([
///     "First document",
///     "Second document"
/// ])
/// ```
///
/// Example usage with custom model:
/// ```swift
/// let customProvider = HuggingFaceEmbedding(
///     apiKey: "hf_...",
///     modelId: "intfloat/e5-base-v2",
///     dimensions: 768
/// )
/// ```
///
/// ## Available Models
/// - `miniLM`: sentence-transformers/all-MiniLM-L6-v2 (384 dimensions) - Fast and efficient
/// - `bgeLargeEN`: BAAI/bge-large-en-v1.5 (1024 dimensions) - High quality English
/// - `bgeBaseEN`: BAAI/bge-base-en-v1.5 (768 dimensions) - Balanced performance
/// - `e5Large`: intfloat/e5-large-v2 (1024 dimensions) - Excellent retrieval quality
/// - `multilingualE5`: intfloat/multilingual-e5-large (1024 dimensions) - 100+ languages
/// - `jina`: jinaai/jina-embeddings-v2-base-en (768 dimensions) - Long context support
///
/// ## Security
/// Never log or expose the API key. It is stored privately and only used
/// in the Authorization header of API requests.
///
/// ## Thread Safety
/// Implemented as an actor for safe concurrent use.
public actor HuggingFaceEmbedding: EmbeddingProvider {

    // MARK: - Types

    /// Available HuggingFace embedding models.
    ///
    /// These models are hosted on HuggingFace's inference infrastructure and
    /// provide high-quality embeddings for various use cases.
    public enum Model: String, Sendable, CaseIterable {
        /// sentence-transformers/all-MiniLM-L6-v2: 384 dimensions.
        /// Fast and efficient model, great for prototyping and lightweight applications.
        case miniLM = "sentence-transformers/all-MiniLM-L6-v2"

        /// BAAI/bge-large-en-v1.5: 1024 dimensions.
        /// State-of-the-art English embedding model with excellent retrieval quality.
        case bgeLargeEN = "BAAI/bge-large-en-v1.5"

        /// BAAI/bge-base-en-v1.5: 768 dimensions.
        /// Balanced model offering good quality with moderate computational requirements.
        case bgeBaseEN = "BAAI/bge-base-en-v1.5"

        /// intfloat/e5-large-v2: 1024 dimensions.
        /// High-quality retrieval-focused model from Microsoft.
        case e5Large = "intfloat/e5-large-v2"

        /// intfloat/multilingual-e5-large: 1024 dimensions.
        /// Supports over 100 languages with excellent cross-lingual retrieval.
        case multilingualE5 = "intfloat/multilingual-e5-large"

        /// jinaai/jina-embeddings-v2-base-en: 768 dimensions.
        /// Supports long context (8192 tokens) with strong performance.
        case jina = "jinaai/jina-embeddings-v2-base-en"

        /// The number of dimensions for this model.
        public var dimensions: Int {
            switch self {
            case .miniLM:
                return 384
            case .bgeLargeEN, .e5Large, .multilingualE5:
                return 1024
            case .bgeBaseEN, .jina:
                return 768
            }
        }

        /// Human-readable description of the model.
        public var description: String {
            switch self {
            case .miniLM:
                return "MiniLM (384 dims) - Fast and efficient"
            case .bgeLargeEN:
                return "BGE Large EN (1024 dims) - High quality English"
            case .bgeBaseEN:
                return "BGE Base EN (768 dims) - Balanced performance"
            case .e5Large:
                return "E5 Large (1024 dims) - Excellent retrieval"
            case .multilingualE5:
                return "Multilingual E5 (1024 dims) - 100+ languages"
            case .jina:
                return "Jina (768 dims) - Long context support"
            }
        }

        /// Whether this model supports multiple languages.
        public var isMultilingual: Bool {
            switch self {
            case .multilingualE5:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - EmbeddingProvider Properties

    /// The name of this provider.
    public nonisolated let name = "huggingface"

    /// The number of dimensions in embeddings.
    public nonisolated let dimensions: Int

    /// Maximum tokens per request (typical limit for most HuggingFace models).
    public nonisolated var maxTokensPerRequest: Int { 512 }

    /// Optimal batch size for HuggingFace Inference API.
    public nonisolated var optimalBatchSize: Int { 32 }

    // MARK: - Private Properties

    /// The HuggingFace API key.
    private let apiKey: String

    /// The model identifier.
    private let modelId: String

    /// Base URL for the HuggingFace Inference API.
    private let baseURL: URL

    // MARK: - Initialization

    /// Creates a HuggingFace embedding provider with a predefined model.
    ///
    /// - Parameters:
    ///   - apiKey: Your HuggingFace API key. Keep this secret!
    ///   - model: The embedding model to use. Defaults to MiniLM.
    public init(
        apiKey: String,
        model: Model = .miniLM
    ) {
        self.apiKey = apiKey
        self.modelId = model.rawValue
        self.dimensions = model.dimensions
        self.baseURL = URL(string: "https://api-inference.huggingface.co/pipeline/feature-extraction/\(model.rawValue)")!
    }

    /// Creates a HuggingFace embedding provider with a custom model.
    ///
    /// Use this initializer when you need to use a model not included in the
    /// predefined `Model` enum, such as a fine-tuned model or a newly released model.
    ///
    /// - Parameters:
    ///   - apiKey: Your HuggingFace API key. Keep this secret!
    ///   - modelId: The full model identifier (e.g., "organization/model-name").
    ///   - dimensions: The number of dimensions in the model's embeddings.
    public init(
        apiKey: String,
        modelId: String,
        dimensions: Int
    ) {
        self.apiKey = apiKey
        self.modelId = modelId
        self.dimensions = dimensions
        self.baseURL = URL(string: "https://api-inference.huggingface.co/pipeline/feature-extraction/\(modelId)")!
    }

    // MARK: - EmbeddingProvider Methods

    /// Generates an embedding for a single text.
    ///
    /// - Parameter text: The text to embed.
    /// - Returns: The embedding vector.
    /// - Throws: `ZoniError.embeddingFailed` or `ZoniError.rateLimited` on failure.
    public func embed(_ text: String) async throws -> Embedding {
        let embeddings = try await embed([text])
        guard let first = embeddings.first else {
            throw ZoniError.embeddingFailed(reason: "No embedding returned from HuggingFace")
        }
        return first
    }

    /// Generates embeddings for multiple texts in a batch.
    ///
    /// Batch embedding is more efficient than calling `embed(_:)` repeatedly.
    /// The returned embeddings are in the same order as the input texts.
    ///
    /// - Parameter texts: The texts to embed.
    /// - Returns: An array of embeddings in the same order as input.
    /// - Throws: `ZoniError.embeddingFailed` or `ZoniError.rateLimited` on failure.
    public func embed(_ texts: [String]) async throws -> [Embedding] {
        guard !texts.isEmpty else { return [] }

        // Build request
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "inputs": texts,
            "options": ["wait_for_model": true]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Execute request
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ZoniError.embeddingFailed(reason: "Network error: \(error.localizedDescription)")
        }

        // Validate HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZoniError.embeddingFailed(reason: "Invalid response type")
        }

        // Handle rate limiting
        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { Double($0) }
                .map { Duration.seconds($0) }
            throw ZoniError.rateLimited(retryAfter: retryAfter)
        }

        // Handle errors
        guard httpResponse.statusCode == 200 else {
            let errorMessage = parseErrorResponse(data)
            throw ZoniError.embeddingFailed(
                reason: "HuggingFace API error (\(httpResponse.statusCode)): \(errorMessage)"
            )
        }

        // Parse response - HuggingFace returns [[Float]] directly
        let vectors: [[Float]]
        do {
            vectors = try JSONDecoder().decode([[Float]].self, from: data)
        } catch {
            throw ZoniError.embeddingFailed(
                reason: "Failed to parse HuggingFace response: \(error.localizedDescription)"
            )
        }

        // Validate response
        guard vectors.count == texts.count else {
            throw ZoniError.embeddingFailed(
                reason: "Response count mismatch: expected \(texts.count), got \(vectors.count)"
            )
        }

        // Convert to Embeddings
        return vectors.map { Embedding(vector: $0, model: modelId) }
    }

    // MARK: - Private Methods

    /// Parses an error response body for a human-readable message.
    private func parseErrorResponse(_ data: Data) -> String {
        // Try to parse as JSON error response
        if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = errorDict["error"] as? String {
                return error
            }
            if let errorMessage = errorDict["message"] as? String {
                return errorMessage
            }
        }

        // Fall back to raw string if JSON parsing fails
        if let rawString = String(data: data, encoding: .utf8), !rawString.isEmpty {
            return rawString
        }

        return "Unknown error"
    }
}
